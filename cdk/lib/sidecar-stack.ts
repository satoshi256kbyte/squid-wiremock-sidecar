import { CfnOutput, Fn, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { DockerImageAsset, Platform } from 'aws-cdk-lib/aws-ecr-assets';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { StagedAssets } from './assets';
import { buildTaskDefinitionProps } from './taskdef';

export interface SidecarStackProps extends StackProps {
  readonly assets: StagedAssets;
  // Client が叩く先。https:// だけを受け付ける（taskdef.ts が検査する）。
  readonly apiBaseUrl: string;
  readonly templatePath: string;
}

// ECS のサイドカー構成（Client と Squid）を、WireMock なしで AWS に置く。
// 範囲はタスク定義まで。サービスは作らず、タスクの起動（run-task）は利用者が行う。
export class SidecarStack extends Stack {
  constructor(scope: Construct, id: string, props: SidecarStackProps) {
    super(scope, id, props);

    // Why: ARM64 固定。arm64 の Mac でビルドしたイメージと、Fargate の ARM64 を合わせる。
    const clientImage = new DockerImageAsset(this, 'ClientImage', {
      directory: props.assets.clientDir,
      file: 'Dockerfile.test-client',
      platform: Platform.LINUX_ARM64,
    });
    const squidImage = new DockerImageAsset(this, 'SquidImage', {
      directory: props.assets.squidDir,
      platform: Platform.LINUX_ARM64,
    });

    // Why: アカウント全体で VPC Block Public Access が block-bidirectional になっているため、この VPC だけ除外する。
    // NAT Gateway 経由の送信だけを許可する allow-egress にする（インバウンドは許可しない）。
    const vpc = new ec2.Vpc(this, 'Vpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.251.0.0/24'),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        { name: 'public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 26 },
        { name: 'private', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 26 },
      ],
    });
    new ec2.CfnVPCBlockPublicAccessExclusion(this, 'BpaExclusion', {
      internetGatewayExclusionMode: 'allow-egress',
      vpcId: vpc.vpcId,
    });

    // アウトバウンドは 443 だけ（外部 API への HTTPS と、ECR からのイメージ取得）。インバウンドは作らない。
    const securityGroup = new ec2.SecurityGroup(this, 'TaskSecurityGroup', {
      vpc,
      allowAllOutbound: false,
      description: 'swsc sidecar task: egress 443 only',
    });
    securityGroup.addEgressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'HTTPS');

    const cluster = new ecs.Cluster(this, 'Cluster', { vpc });

    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const executionRole = new iam.Role(this, 'ExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });
    clientImage.repository.grantPull(executionRole);
    squidImage.repository.grantPull(executionRole);

    const taskDefinition = new ecs.CfnTaskDefinition(
      this,
      'TaskDefinition',
      buildTaskDefinitionProps({
        templatePath: props.templatePath,
        clientImage: clientImage.imageUri,
        squidImage: squidImage.imageUri,
        apiBaseUrl: props.apiBaseUrl,
        logGroupName: logGroup.logGroupName,
        region: this.region,
        executionRoleArn: executionRole.roleArn,
      }),
    );

    // run-task に必要な値。run-task 自体は利用者が実行する。
    new CfnOutput(this, 'ClusterName', { value: cluster.clusterName });
    new CfnOutput(this, 'TaskDefinitionArn', { value: taskDefinition.ref });
    new CfnOutput(this, 'SubnetIds', {
      value: Fn.join(',', vpc.selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }).subnetIds),
    });
    new CfnOutput(this, 'SecurityGroupId', { value: securityGroup.securityGroupId });
  }
}
