import * as fs from 'node:fs';
import * as path from 'node:path';

// イメージのビルド文脈を、scripts/e2e-lib.sh の swsc_build_images と同じ内容で作る。
// Why: ローカルと CI で検証したイメージと、AWS へ置くイメージの中身を同じにするため。
// Why not リポジトリ全体を文脈にする: node_modules などを送ってしまうため。
export interface StagedAssets {
  readonly clientDir: string;
  readonly squidDir: string;
}

function copy(root: string, from: string, toDir: string, to?: string): void {
  fs.mkdirSync(toDir, { recursive: true });
  fs.copyFileSync(path.join(root, from), path.join(toDir, to ?? path.basename(from)));
}

export function stageAssets(repoRoot: string, workDir: string): StagedAssets {
  const clientDir = path.join(workDir, 'client');
  const squidDir = path.join(workDir, 'squid');
  fs.rmSync(workDir, { recursive: true, force: true });

  copy(repoRoot, 'Dockerfile.test-client', clientDir);
  copy(repoRoot, 'test-client/entrypoint.sh', path.join(clientDir, 'test-client'));
  copy(repoRoot, 'test-client/retry-lib.sh', path.join(clientDir, 'test-client'));

  copy(repoRoot, 'squid-config/squid.conf', squidDir);
  copy(repoRoot, 'squid-config/whitelist.txt', squidDir);
  copy(repoRoot, 'ecs/squid/Dockerfile', squidDir);
  copy(repoRoot, 'ecs/squid/derive-config.sh', squidDir);
  copy(repoRoot, 'ecs/squid/entrypoint.sh', squidDir);

  return { clientDir, squidDir };
}
