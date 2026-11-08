# R02-R05 フェーズ1 検証結果（commit 1: R02 actionlint と YAML の構造比較）

フェーズ1（T-R0218〜T-R0233）の結果を記録する。
実行環境は Linux aarch64 の 2 コアの EC2（2026-11-08）である。識別情報と利用者の絶対パスは記録しない。

## 1. 旧の判定の記録と U11（T-R0218）

| 項目 | 結果 |
| --- | --- |
| U11: actionlint の引数の渡し方 | `actionlint <ファイル>` は、現在のワークフローを終了コード 0 で通す。`actionlint -shellcheck <shellcheck の実体> <ファイル>` も終了コード 0 で通す。`run:` の形は、1行の単一引用符の値とする（`run: \|` の形は、検査 `t_wf_run_lines_have_no_expression_or_block_scalar` が拒否する） |
| 式の誤りの検出 | 存在しないコンテキストの式を含む一時のワークフローで、actionlint は終了コード 1 で失敗する（検査 `t_actionlint_rejects_expression_error`） |
| 旧の18関数の複製 | **未実施**。置き換えの前に旧の M09 を複製し、旧の判定を記録する作業は、実施していない。旧の判定は、置き換え後の検査が、壊した定義を落とすことで代替して確かめた（第3章） |

## 2. 実装（T-R0219〜T-R0225）

| 変更 | 内容 |
| --- | --- |
| step 数の更新 | 11 step（actionlint を shellcheck の次に足す）。検査の期待を更新 |
| `scripts/lib/resolve-tool.sh`（新規） | 関数 `resolve_tool` の定義だけ。読み込んでも副作用なし。mise の照合と版の取り出し |
| `scripts/quality-gate.sh` | `resolve_tool` を使う。`actionlint_gate`（`-shellcheck` を付ける）。yq の版の照合（Markdown の前）。M09 の実行条件に `scripts/lib/` などを足した |
| `.github/workflows/e2e-test.yml` | actionlint の step（2分、run は1行）。`unit` の前 |

## 3. 構造比較への置き換え（T-R0221〜T-R0223）

| 項目 | 結果 |
| --- | --- |
| 旧の補助関数（`wf_block`、`wf_has_line`、`wf_top_block`、`wf_step_timeout`） | 削除済み。`git grep` で定義と使用は0件（`t_wf_step_timeouts_...` の名前の中の部分一致は除く） |
| PyYAML の分岐（`import yaml`、SKIP の表示） | 削除済み |
| 契約の検査 | `yq -e` の式で構造比較する。`null` と `false` は失敗。map の比較は `keys \| join` で行う |
| 壊した定義の確認 | Haiku が、`yq` の式で、壊した定義（`persist-credentials: true`、`smoke` の中の `docker compose`、`retention-days: 30`、`smoke` の改名）を作り、対応する検査が落ちることを確かめた |
| 未実施の確認 | 旧の検査と新の式の、1件ずつの対応表（T-R0228）は作っていない。壊した定義の10件（plan 7.4 節）の全件は確かめていない |

## 4. 失敗の状態（T-R0229）

| 状態 | 結果 |
| --- | --- |
| mise が無い | `resolve_tool` が `FAILED: miseが未導入…` を出し、終了コード 1 |
| actionlint が未導入（空のデータ置き場） | `FAILED: actionlintが未導入…` を出し、終了コード 1 |
| 版違い | **未確認** |
| 式の誤りを含むワークフロー | actionlint が終了コード 1 |

## 5. 時間（T-R0230）

| 検査 | 結果 |
| --- | --- |
| `sh scripts/quality-gate.sh`（commit 1） | `quality-gate: passed`、243秒 |
| M09 unit（229件） | 229件すべて通過 |
| M09 smoke（11件） | 通過（118秒） |
| commit 0 との比較 | commit 0 の品質ゲートは 244秒（同じ条件の値）。差は小さい |

## 6. 必須レビューと修正（T-R0231）

| レビュー | 指摘 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Medium 1（`wf_yq_bin` がリポジトリの外で失敗する）、Low 3（actionlint の検査が部分一致、secrets のキーを見ていない、文書の順序の記述）、NITS 2 | 直した。再レビュー（修正の範囲）は指摘なし |
| `security-review` | Low 2（テスト側の `mise` 呼び出しに `MISE_LOCKED=1` が無い。`resolve_tool` の検査がコメントで通る） | 直した。`mise which` の2行に `MISE_LOCKED=1` を付けた。`resolve_tool` の検査は、コメントを除いてから探すようにした。ワークフロー側の2変数の step は、R01 の理由（Why コメント）のとおり変えていない |

## 7. 品質ゲート（T-R0232）

`sh scripts/quality-gate.sh` は `quality-gate: passed`（243秒）。
内訳: `git diff --check`、shellcheck（`-s sh -S style`）、actionlint（`-shellcheck` 付き）、lint:md、S14 unit、M09 unit（229件）、M09 smoke（11件）。
識別情報の検査（12桁の数字、`arn:aws`、`AKIA`、利用者の絶対パス）は、commit 1 の追加行で0件。管理対象のコンテナの残りは0件。

## 8. 残った確認

| 項目 | 状態 |
| --- | --- |
| T-R0218 の旧の18関数の複製と旧の判定 | 未実施。第1章に記録した |
| T-R0228 の対応表（旧→新、壊した定義の10件） | 未実施。第3章に記録した |
| T-R0229 の版違い | 未実施 |
| 初回の CI での actionlint step の実測 | commit 1 の後、利用者の端末で行う |
