# ローカル実行と CI

## 前提

- Docker、Node.js 22+、curl
- mise 2026.11.3 以上。導入は `mise install --locked`（`mise.toml` と `mise.lock` の固定版だけを入れる）
- 導入するツール: shellcheck、actionlint、gitleaks、jq

## ローカルの実行

```bash
npm run test:ci    # 起動、検査、収集、停止を続けて実行する
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000  # 4シナリオ
```

- 固定ポート 8080、14566、15000 は、入口のロック（既定は `/tmp/swsc-e2e-ports.lock`）で1つの実行だけに限る。
- 失敗したときは、`e2e-logs/` に収集したログが残る。
- 後片付けは `npm run stop`（資源の削除）と `npm run clean`（生成物と収集ログの削除）。

## CI（`.github/workflows/e2e-test.yml`）

PR と push で、次の順に実行する。

| step | 内容 | 上限 |
| --- | --- | --- |
| shellcheck | 全 `.sh` を `-s sh -S style` で検査する | 3 分 |
| actionlint | ワークフローを検査する | 2 分 |
| gitleaks | 識別情報の値を検出する（`.gitleaks.toml`、値は出さない） | 2 分 |
| test-ci | `npm run test:ci` と、4シナリオの `test:ci` | 10 分 |
| collect / upload | 失敗時に収集したログを成果物に上げる | - |
| stop | 残ったコンテナを必ず消す | - |

CI では Secrets を使わない。ワークフローの `env` に書くのはダミーの値だけで、実 AWS には接続しない。
