import * as fs from 'node:fs';
import * as ecs from 'aws-cdk-lib/aws-ecs';

// タスク定義の元は ecs/task-definition.template.json の1つだけ。ここでは、その雛形を読み、
// 許可したキーだけを通し、プレースホルダーと AWS 固有の値を置き換える。
// Why: コンテナ名、環境変数、ヘルスチェック、依存関係を、CDK のコードに書かないため（R14）。
// Why: 雛形のキーは ECS の API の JSON と同じ camelCase で、CDK の L1 の props も camelCase のため、キーの変換は要らない。

const TOP_KEYS = new Set([
  'family', 'networkMode', 'requiresCompatibilities', 'cpu', 'memory', 'containerDefinitions',
]);
const CONTAINER_KEYS = new Set([
  'name', 'image', 'essential', 'environment', 'portMappings', 'dependsOn', 'healthCheck', 'command', 'entryPoint',
]);
const PLACEHOLDER = /^\{\{([A-Z_]+)\}\}$/;
// Why: render（scripts/e2e-taskdef.py）の LOG_STREAM_PREFIX と同じ値。一致しているかは check-cdk が確かめる。
const LOG_STREAM_PREFIX = 'swsc-e2e';
const API_BASE_URL_ENV = 'TEST_API_BASE_URL';
// Why: 本番は https:// だけ。パスや認証情報を入れて値が漏れないよう、スキームとホスト（とポート）に絞る（R15）。
const API_BASE_URL_RE = /^https:\/\/[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?$/;

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type Obj = { [key: string]: Json };

export interface TaskDefinitionInput {
  readonly templatePath: string;
  readonly clientImage: string;
  readonly squidImage: string;
  readonly apiBaseUrl: string;
  readonly logGroupName: string;
  readonly region: string;
  readonly executionRoleArn: string;
}

function asObject(value: Json, where: string): Obj {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${where} がオブジェクトではない`);
  }
  return value;
}

function rejectUnknown(node: Obj, allowed: Set<string>, where: string): void {
  for (const key of Object.keys(node)) {
    if (!allowed.has(key)) {
      throw new Error(`${where} に許可されていない項目がある: ${key}`);
    }
  }
}

// 文字列全体がプレースホルダーのときだけ置き換える。未知の名前は拒否する。
function fill(node: Json, values: Record<string, string>): Json {
  if (Array.isArray(node)) {
    return node.map((v) => fill(v, values));
  }
  if (typeof node === 'object' && node !== null) {
    return Object.fromEntries(Object.entries(node).map(([k, v]) => [k, fill(v, values)]));
  }
  if (typeof node === 'string') {
    const m = PLACEHOLDER.exec(node);
    if (m) {
      const name = m[1];
      if (!(name in values)) {
        throw new Error(`未知のプレースホルダー: ${name}`);
      }
      return values[name];
    }
  }
  return node;
}

export function buildTaskDefinitionProps(input: TaskDefinitionInput): ecs.CfnTaskDefinitionProps {
  if (!API_BASE_URL_RE.test(input.apiBaseUrl)) {
    throw new Error('apiBaseUrl は https://<ホスト> の形だけ（パスは付けない）');
  }
  const template = asObject(JSON.parse(fs.readFileSync(input.templatePath, 'utf-8')) as Json, 'タスク定義の雛形');
  rejectUnknown(template, TOP_KEYS, 'トップレベル');

  // Why: SQUID_UPSTREAM は direct に固定する。AWS 用のスタックは WireMock を使わない（R15）。
  const filled = asObject(
    fill(template, {
      CLIENT_IMAGE: input.clientImage,
      SQUID_IMAGE: input.squidImage,
      SQUID_UPSTREAM: 'direct',
    }),
    'タスク定義',
  );

  const containers = filled.containerDefinitions;
  if (!Array.isArray(containers) || containers.length === 0) {
    throw new Error('containerDefinitions が空または配列ではない');
  }
  const out = containers.map((c) => {
    const container = asObject(c, 'コンテナ定義');
    rejectUnknown(container, CONTAINER_KEYS, `コンテナ定義 ${String(container.name)}`);
    const next: Obj = { ...container };
    if (container.name === 'client') {
      const env = (Array.isArray(container.environment) ? container.environment : []).filter(
        (e) => asObject(e, 'environment').name !== API_BASE_URL_ENV,
      );
      env.push({ name: API_BASE_URL_ENV, value: input.apiBaseUrl });
      next.environment = env;
    }
    next.logConfiguration = {
      logDriver: 'awslogs',
      options: {
        'awslogs-group': input.logGroupName,
        'awslogs-region': input.region,
        'awslogs-stream-prefix': LOG_STREAM_PREFIX,
      },
    };
    return next;
  });

  return {
    ...(filled as unknown as ecs.CfnTaskDefinitionProps),
    containerDefinitions: out as unknown as ecs.CfnTaskDefinition.ContainerDefinitionProperty[],
    executionRoleArn: input.executionRoleArn,
    runtimePlatform: { cpuArchitecture: 'ARM64', operatingSystemFamily: 'LINUX' },
  };
}
