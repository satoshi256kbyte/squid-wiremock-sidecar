# R01 フェーズ5 検証結果

フェーズ5（文書と上限の見直し。T-R0142〜T-R0147、T-R0155）の結果を記録する。
文書は実装サブエージェント（Claude Haiku 5.5）が3回の依頼（E: 3タスクの文書、E2: evidence の指摘、E3: security の指摘）で書いた。レビューと検査はメインエージェントが行った。
実行環境はLinux aarch64の2コアのEC2（2026-11-08）である。AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 文書（T-R0142〜T-R0144）

| ファイル | 変えた内容 |
| --- | --- |
| `AGENTS.md` | 品質ゲートの表の `sh -n` を shellcheck に改めた。導入（`mise install --locked`）と、未導入時の失敗を書いた |
| `docs/ローカル実行とCI.md` | R01 の章を追加した（前提、版の固定、ゲートの shellcheck、CI の step、`mise.lock` の再生成、自動信頼の限界、件数、実行時間）。M09 の既存の章は残した |
| `README.md` | Prerequisites に mise と shellcheck を足した。M07、M08、S14 が固定する行は変えていない |

## 2. 必須レビュー（T-R0146）

| レビュー | 重大な指摘（Critical、High、Medium） | 指摘 | 対応 |
| --- | ---: | --- | --- |
| `evidence-code-review` | 0 | SHOULD 2件、NITS 1件 | 直した。`github_token` の既定値と `mise trust` の注意を足した。`min_version` は下限と書き分けた。除外の数え方を、指令の行で管理する書き方に直した |
| `security-review` | 0 | Low 2件 | 直した。`sha256` は1値なので、「足す」の書き方をやめた。linux-x64 の値は文書から消し、参照にした |

直した後の2件の文書の検査は、lint、`git diff --check`、m09 unit（225件）で確かめた。
Low の修正は、もう一度のレビューを要しない。

## 3. 最終の検査（T-R0147、T-R0155）

最終の品質ゲートを1回実行した。M02〜M09 の unit と smoke を含むので、T-R0155 を兼ねる。

| 検査 | 結果 |
| --- | --- |
| `sh scripts/quality-gate.sh` | `quality-gate: passed`（534秒） |
| M02〜M05 smoke | すべて passed |
| M06 unit（133件）と smoke | 通過 |
| M07 unit（44件）と smoke（60件） | 通過 |
| M08 unit（19件）と smoke（30件） | 通過 |
| S14 unit | 5件中5件通過 |
| M09 unit（225件）と smoke（11件） | 通過（smoke は118秒） |
| `npm run -s lint:md` | 0件 |
| `git diff --check` | 指摘なし |
| 管理対象（`swsc.managed=true`）のコンテナの残り | 0件 |

フェーズ4の品質ゲートは527秒、このフェーズ5の最終は534秒である。文書だけの変更でも、ゲートの時間は約7秒増えた。ばらつきの範囲内と見ている。

## 4. 残りの作業（利用者の端末）

| タスク | 内容 | 状態 |
| --- | --- | --- |
| T-R0145 | 初回 CI の実測（`shellcheck` step と job 全体）を文書に反映し、上限（3分、mise-action の上限は無し）を見直す | 初回 CI の後 |
| T-R0148 | コミット5を作る | 利用者の指示を待つ |
| T-R0149 | feature ブランチを push し、既存 PR を更新する。required checks（`e2e`、`shellcheck`）を確かめる | 利用者の端末 |
| T-R0137 | 任意の `aws-well-architected-review-lite` を実行するか | 利用者の判断 |
| T-R0138 | macOS と Linux での `mise install --locked` と版の一致 | 利用者の端末 |
| 版違いの失敗 | `mise.toml` を書き換えて確かめる方法が、リポジトリを変えるため、未実施 | 利用者の端末で確かめる |

## 5. 削除したもの、残したもの

- 削除: レビュー用のスナップショット、ゲートの一時ファイル（`.e2e/`）、ログ。
- 残したもの: なし。作業ツリーは、フェーズ5の3文書だけが未コミットである。
