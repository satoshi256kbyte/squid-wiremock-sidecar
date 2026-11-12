import * as path from 'node:path';
import { App } from 'aws-cdk-lib';
import { stageAssets } from '../lib/assets';
import { SidecarStack } from '../lib/sidecar-stack';

const app = new App();

const repoRoot = path.resolve(__dirname, '..', '..');
const assets = stageAssets(repoRoot, path.resolve(__dirname, '..', '.assets'));

// Client が叩く先。-c apiBaseUrl=https://... で変えられる。https:// だけを受け付ける。
const apiBaseUrl = String(app.node.tryGetContext('apiBaseUrl') ?? 'https://httpbin.org');

new SidecarStack(app, 'SwscSidecar', {
  assets,
  apiBaseUrl,
  templatePath: path.join(repoRoot, 'ecs', 'task-definition.template.json'),
  // Why: env を渡さない（環境に依存しないスタックにする）。アカウントとリージョンは、デプロイ時の認証情報で決まる。
  // env を渡すと、AZ などの検索結果（cdk.context.json）や cdk.out にアカウント ID が残り、公開物に混ざるおそれがある。
});
