# AWS へのデプロイ

サイドカー構成（Client と Squid。WireMock なし）を AWS（ECS Fargate）に置く方法を説明する。
CDK を使う方法と、`render` で作ったタスク定義を手動で登録する方法がある。どちらも、実行は利用者が自分の環境で行う。
CI は AWS に接続しない。

## タスク定義の元

タスク定義の元は、ローカルと CI が使うものと同じ `ecs/task-definition.template.json` の1つだけである。
構成と、一本化の検査（`check-production`、`check-cdk`）は [アーキテクチャ](../ARCHITECTURE.md) を参照。

| 方法 | タスク定義の作り方 | 作るもの |
| --- | --- | --- |
| CDK | `cdk/lib/taskdef.ts` が雛形を読み、イメージ、ログ、ロールなどを置き換える（`SQUID_UPSTREAM` は `direct` 固定） | VPC、クラスタ、ログ、ロール、タスク定義 |
| 手動 | `render --profile production` | タスク定義の JSON だけ |

## CDK でデプロイする

CDK のコードには、コンテナ名、環境変数、ヘルスチェック、依存関係を書かない。一本化していることは `check-cdk` が確かめる。

```bash
npm ci --prefix cdk
npm run synth --prefix cdk             # cdk/cdk.out に CloudFormation を出す
sh scripts/e2e.sh check-cdk            # synth の出力が、render の本番用の出力と一致するか
```

`synth` と `check-cdk` は AWS に接続しない。CI もこの2つだけを行う。

デプロイ（利用者の AWS 環境で行う。初回は `cdk bootstrap` が要る）:

```bash
cd cdk
npx cdk deploy                         # Client の宛先を変えるときは -c apiBaseUrl=https://<ホスト>
```

デプロイすると、出力に `ClusterName`、`TaskDefinitionArn`、`SubnetIds`、`SecurityGroupId` が出る。
タスクの起動（`run-task`）は、利用者が行う。サービスは作らない。

```bash
aws ecs run-task --cluster <ClusterName> --task-definition <TaskDefinitionArn> --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[<SubnetIds>],securityGroups=[<SecurityGroupId>]}'
```

Client の宛先や環境変数を、その実行だけ変えるときは、`--overrides` を使う。たとえば `/status/500` を叩くには、
次の引数を足す。

```bash
--overrides '{"containerOverrides":[{"name":"client","environment":[{"name":"TEST_API_PATH","value":"/status/500"}]}]}'
```

| 項目 | 内容 |
| --- | --- |
| ネットワーク | 専用の VPC。プライベートサブネットと NAT Gateway 1つ。セキュリティグループは、アウトバウンドの 443 だけ |
| VPC Block Public Access | アカウント全体で有効な場合に備え、この VPC だけ `allow-egress` で除外する |
| 費用 | NAT Gateway は時間で課金される。使い終わったら `npx cdk destroy` で消す |
| 宛先 | `apiBaseUrl` は `https://` だけ。ドメインは `squid-config/whitelist.txt` に入れる。CDK がイメージを作り直す |
| アーキテクチャ | ARM64 固定。イメージも ARM64 でビルドする |
| ログ | CloudWatch Logs（保持は1週間）。`CLIENT_STATUS` はここで確認する |
| 環境 | スタックに `env` を渡さない。渡すと、`cdk.out` や `cdk.context.json` にアカウント ID が残るため |
| 削除後 | `cdk destroy` は、CDK のアセットとして ECR に置いたイメージを消さない。不要なら手動で消す |

## 手動でタスク定義を登録する

CDK を使わずに、本番向けのタスク定義だけを作り、検査し、登録する方法。
イメージの作成と ECR への push は、利用者の環境で行う。Squid のイメージは `ecs/squid/Dockerfile`、
Client のイメージは `Dockerfile.test-client` から作る。

1. 本番向けのタスク定義を作る。本番は `--profile production --upstream direct` だけを受け付ける（WireMock は指定できない）。

   | 引数 | 内容 |
   | --- | --- |
   | `--api-base-url` | Client が叩く先（`TEST_API_BASE_URL`）。本番は `https://` だけ。必須 |
   | `--log-group`、`--log-region` | ログの設定。一緒に指定する。省略できる |
   | `--execution-role-arn`、`--task-role-arn` | ロール。省略できる |
   | `--cpu-architecture` | Fargate の CPU アーキテクチャ（`arm64` か `x86_64`）。省略すると指定しない（既定は x86_64）。arm64 の Mac でビルドしたイメージには `arm64` を指定する |

   ```bash
   python3 -B scripts/e2e-taskdef.py render \
     --template ecs/task-definition.template.json --out taskdef-production.json \
     --client-image <ECR のホスト>/<client のリポジトリ>:<タグ> \
     --squid-image <ECR のホスト>/<squid のリポジトリ>:<タグ> \
     --profile production --upstream direct \
     --api-base-url https://httpbin.org \
     --log-group <ロググループ名> --log-region <リージョン> \
     --execution-role-arn <実行ロールの ARN> --task-role-arn <タスクロールの ARN> \
     --cpu-architecture arm64
   ```

2. 本番向けの条件を満たすか検査する。合格すると `OK: 本番向けの検査に合格` と出る。

   ```bash
   sh scripts/e2e.sh check-production taskdef-production.json
   ```

3. 検査を通ったファイルを、ECS に登録する。

   ```bash
   aws ecs register-task-definition --cli-input-json file://taskdef-production.json
   ```

## 共通の注意

| 項目 | 内容 |
| --- | --- |
| 叩く先 | `httpbin.org` を許可リスト（`squid-config/whitelist.txt`）に入れてある。別のドメインを使うときは、許可リストへ足して Squid のイメージを作り直す。`httpbin.org` については [テスト方式](テスト方式.md#aws-での確認) を参照 |
| HTTPS | Squid が `CONNECT` で中継する（中身は復号しない）。ローカルと CI は HTTP のまま WireMock を使う |
| セキュリティグループ | タスクの送信の 443 を許可する |
| 止め方 | タスクは Client が終わっても止まらない（Squid が `essential` のため）。検証後は `aws ecs stop-task` で止める |
| 公開物 | アカウント ID、ARN は、PR や報告に書かない（プレースホルダーに置き換える） |
