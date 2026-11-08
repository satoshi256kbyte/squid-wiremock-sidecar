# フェーズ3 R05（jq）の結果記録

## 1. 置き換え対象の数え直し（T-R0253、FR-R0227）

作業の開始時に、`tests/` と `scripts/` を `grep` で数え直した。
対象の検索語は `python3 -c`、`python3 -B -c`、`python3 -` の heredoc、`json.load`、
`"count"`、`urlPath`、`sed -n` である。

| ファイル | 場所 | 種類 | 扱い |
| --- | --- | --- | --- |
| `tests/m03-wiremock-scenarios.sh` | 47行 `validate_json` | `python3 -` の heredoc で `json.load` | 置き換える（T-R0257） |
| `tests/m03-wiremock-scenarios.sh` | 57行 `validate_mapping` | `python3 -` の heredoc で必須キーを確認 | 置き換える（T-R0257） |
| `tests/m07-scenario-isolation.sh` | 448行 | `python3 -c` で `urlPath` を取る | 置き換える（T-R0259） |
| `tests/m07-scenario-isolation.sh` | 約216行 | 2つの定義の比較 | 置き換える（T-R0259） |
| `tests/m08-e2e-suite.sh` | 615行 | `sed` で `"count"` を取る | 置き換える（T-R0261） |
| `tests/m08-e2e-suite.sh` | 524〜537行 | `key=value` の行を `sed` で取る | 置き換えない（FR-R0225） |
| `tests/m09-execution-and-ci.sh` | 87行 | `python3` の実体を探す | 置き換えない |
| `tests/m09-execution-and-ci.sh` | 131、317、326、336行ほか | `python3 -B -c` で JSON を読む | 置き換える（T-R0262、T-R0263） |
| `scripts/e2e-lib.sh` | 127、180、195行 | socket の確認、`/__admin/requests` の JSON 集計 | 未決（利用者の判断待ち） |
| `scripts/e2e-contract.sh` | 107行 | `taskdef.json` から `family` を取る | 未決（利用者の判断待ち） |

## 2. 未完了

- `scripts/e2e-lib.sh` と `scripts/e2e-contract.sh` を置き換えに含めるか。タスク表の対象に入っていない。
- `plan.md` 9.2節の表の行番号の更新。実際の置き換えは grep で数え直した位置で行った。
- T-R0266 から T-R0271（判定の比較、smoke、レビュー、品質ゲート、コミット）。

## 3. 旧の判定の記録（9.3節、T-R0253 の残り）

`m03` の `validate_json` と `validate_mapping`（置き換え前の Python 実装）を、
4つの入力で実行した。終了コードは次のとおり。
入力と実行スクリプトは `$KIROCREW_SCRATCH/t3-baseline/` にある。

| 入力 | validate_json | validate_mapping |
| --- | --- | --- |
| 正しい入力（request と response が揃う） | 0 | 0 |
| 壊れたJSON（`{`） | 1 | 1 |
| キーの欠落（`request.urlPath` がない） | 0 | 1 |
| 空の配列（`[]`） | 0 | 1 |
| `null` | 0 | 1 |

判定の注意: 旧の `validate_json` は、`[]` と `null` を有効なJSONとして成功させる。
plan.md 9.3節の「null は失敗」を `validate_json` に当てはめると、旧の判定が変わる。
そのため `validate_json` の新しい式は `jq .`（`-e` を付けない）とし、旧の判定を保つ。
`validate_mapping` は `jq -e` の条件式で、旧と同じく `[]` と `null` を失敗にする。

## 4. 除外の一覧（t_json_extraction_uses_jq の基準）

JSON を読む `python3` は、次の基準で置き換えるか残すかを決めた。
取り出しの値だけを jq に移す（plan 9.1 節）。

| 場所 | 種類 | 扱い | 理由 |
| --- | --- | --- | --- |
| `tests/m03` の `validate_json`、`validate_mapping` | JSON の読みと必須項目の確認 | 置き換え済み | 単純な検査 |
| `tests/m07` 約216行 | 2つの定義の比較 | 置き換え済み | JSON の値の比較 |
| `tests/m07` 約448行 | `name` から `urlPath` を取る | 置き換え済み | 単純な値の取り出し |
| `tests/m08` 約615行 | `"count"` を `sed` で取る | 置き換え済み | JSON の値の取り出し |
| `tests/m09` の値の取り出し5か所 | `package.json`、テンプレート、タスク定義の値 | 置き換え済み | 単純な値の取り出し |
| `tests/m09` の `mutate`、`desc_mutate`、`runner_mutate`、`contract_base`、`contract_c6` | JSON を書き換えて写しを作る | 残す | 取り出しではない（壊した入力や変更後の写しを作る） |
| `tests/m09` の `contract_c4` | Docker の inspect を複数の条件で確かめる | 残す | 単純な値の取り出しではない |
| `tests/m09` の `key=value` の `sed`、壊したテンプレートを作る `sed` | JSON でない行、文字列の置換 | 残す | FR-R0225 |
| `tests/m07` 約284行、約425、486行、`tests/m08` 約526〜537行 | Markdown、`key=value` の行 | 残す | FR-R0225 |
| `tests/m07`、`tests/m08`、`tests/m09` の信号の検査の `python3` | 信号の検査 | 残す | FR-R0234 |
| `scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh` | 複雑な整合検査 | 残す | FR-R0226 |
| `scripts/e2e-lib.sh`、`scripts/e2e-contract.sh` | socket の確認、JSON 集計、`family` の取り出し | 未決 | 対象外。利用者の判断待ち |

検査 `t_json_extraction_uses_jq` は、次を確かめる。
`tests/m03` と `tests/m07` に `json.load(` が無いこと。
`tests/m09` では、`mutate` など上の6関数を除いて `json.load(` が無いこと。
`json.load(` の形だけを数えるため、コメントの語では失敗しない。

## 5. m03 の置き換えの判定（T-R0257）

`validate_json` と `validate_mapping` を、`jq` に置き換えた。
5つの入力で、旧の判定（section 3）と比べた。

| 入力 | 旧 json / mapping | 新 json / mapping | 差 |
| --- | --- | --- | --- |
| 正しい入力 | 0 / 0 | 0 / 0 | なし |
| 壊れたJSON | 1 / 1 | 5 / 1 | 終了コードの値だけ違う（どちらも非0） |
| キーの欠落 | 0 / 1 | 0 / 1 | なし。表示は `request.urlPath` で旧と同じ |
| 空の配列 | 0 / 1 | 0 / 1 | なし |
| `null` | 0 / 1 | 0 / 1 | なし |

## 6. m03 の unit モード（T-R0256）

`tests/m03-wiremock-scenarios.sh` に `unit` と `smoke` のモードを足した。
引数を省略すると `smoke` になり、既存の品質ゲートの呼び出しは変わらない。
`unit` は Docker を使わず、`validate_json` と `validate_mapping` だけを確かめる。

| 検査名 | 入力 | 期待 |
| --- | --- | --- |
| `unit_validate_json_rejects_broken_json` | `{` | 失敗 |
| `unit_validate_json_keeps_empty_array_and_null` | `[]`、`null` | 成功（旧の判定を保つ） |
| `unit_validate_mapping_accepts_complete_mapping` | 正しい mapping | 成功 |
| `unit_validate_mapping_rejects_missing_key` | `request.urlPath` が無い | 失敗し、標準エラーに `request.urlPath` |
| `unit_validate_mapping_rejects_empty_array_and_null` | `[]`、`null` | 失敗 |

結果: 5件すべて通過（`sh tests/m03-wiremock-scenarios.sh unit`、終了コード 0）。

注意: 赤から始めていない。判定の置き換えの後に検査を足したため。
期待値は section 3 の旧の判定と一致させた。
旧の Python 実装でこの5件を直接実行してはいない。
`smoke` は Docker を使うため、この作業では実行していない（T-R0268 で実行する）。

## 7. m07 の置き換え（T-R0258、T-R0259）

`tests/m07-scenario-isolation.sh` の JSON の取り出し2か所を jq に置き換えた。
`unit` モードは既にあったため、そこに検査を足した。

| 箇所 | 旧 | 新 |
| --- | --- | --- |
| 2定義の比較（約216行） | `python3 -` の埋め込み | `unit_error_500_then_200_definitions_match`。`jq -e -s` で2ファイルを配列として読む |
| `name` から `urlPath` を取る（約448行） | `python3 -c` の1行 | `mapping_urlpath_by_name`。`jq -r --arg n`。無い name は空、urlPath の無い一致は失敗 |

検査:

- `unit_error_500_then_200_definitions_match`: 旧の状態遷移の検査を、名前つきの検査にした。新しく足した検査ではない。
- `unit_mapping_urlpath_lookup_missing_name`（T-R0258）: 一致する name、無い name、urlPath の無い一致の3つを確かめる。

結果:

- `sh tests/m07-scenario-isolation.sh unit` は 45 件すべて通過（終了コード 0）。
- 否定の確かめ: `status` を 201 に変えた2つ目の定義は、`jq -e` が終了コード 1 で失敗する。
- `sh -n` と shellcheck（`-S style`）は通過。SC2016 は、理由つきの `disable` で扱った。

注意: `smoke` は Docker を使うため、この作業では実行していない（T-R0268 で実行する）。
`mapping_urlpath_by_name` は `smoke_names_match` からも使うが、その検査は smoke でしか動かない。

## 8. m09 の JSON の読み（T-R0262、T-R0263）

`tests/m09-execution-and-ci.sh` の値の取り出し5か所を `jq -e` に置き換えた。
jq の実体は `run_unit` の先頭で、`resolve_tool` により固定版を照合して得る。
contract と smoke の入口では照合しない（認証情報の無い環境で、既存の検査の文言を保つため）。

| 検査 | 旧 | 新 |
| --- | --- | --- |
| `t_package_json_delegates_six_scripts` | `python3` で `scripts` を読む | `jq -e`（6つの script と `lint:md`） |
| `t_template_is_valid_json_with_two_containers` | `python3` で名前と `networkMode` を読む | `jq -e` |
| `t_render_local_sets_upstream_and_mock_destination` | `python3` で squid の環境変数を読む | `jq -e`（`map` と `add` で辞書にする） |
| `t_render_fixes_task_level_values_and_omits_roles` | `python3` で task の値を読む | `jq -e` |
| `t_client_has_proxy_settings_and_no_health_check` | `python3` で client の環境変数を読む | `jq -e` |

結果:

- `sh tests/m09-execution-and-ci.sh unit` は 234 件すべて通過（終了コード 0）。
- 置き換えた5件について、変えた入力で `jq -e` が失敗することを確かめた。
- `sh -n` と shellcheck（`-S style`）は通過。
- `contract` と `smoke` は、この作業では実行していない。
  `contract` は利用者の端末と CI で実行する。`smoke` は T-R0268 で実行する。

注意: plan 9.2 節の行番号は古い。この作業では、grep で数え直した位置で置き換えた。

## 9. m08 の件数の取り出し（T-R0260、T-R0261）

`tests/m08-e2e-suite.sh` の `wiremock_count` の `sed` を、`wiremock_count_value`（jq）に置き換えた。
jq の実体は `m08_jq` が最初に使うときだけ照合する。
unit の検査 `unit_count_extraction_rejects_empty_and_null` を追加した。

旧の `sed` と新の判定を、同じ入力で比べた。

| 入力 | 旧（sed） | 新（jq） |
| --- | --- | --- |
| 空 | 失敗 | 失敗 |
| `"count":null` | 失敗 | 失敗 |
| `"count":"3"`（文字列） | 失敗 | 失敗 |
| `"count":-1` | 失敗 | 失敗 |
| `"count": 3` | 3 | 3 |
| `"count":0` | 0 | 0 |
| `"count":2.5` | 2（小数を切り捨てて成功） | 失敗（整数だけを受け付ける） |

最後の行は、旧と新の判定が違う唯一の入力である。
件数は整数であるため、新しい判定を採る。

結果: `sh tests/m08-e2e-suite.sh unit` は 20 件すべて通過（終了コード 0）。shellcheck は通過。

## 10. 文書（T-R0264、T-R0265）

- `AGENTS.md`: jq の取り出し方（`jq -e`、`null` と `false` は失敗）と、
  品質ゲートの先頭で jq の版を照合することを書いた。
- `docs/ローカル実行とCI.md`: 「JSON の値の取り出し」の節を足した。
  `jq -e` の扱い、整数だけを受け付ける値、残す `python3` と `sed` の一覧（理由つき）を書いた。
- `markdownlint` は、この記録の行の長さと、リストの前後の空行を直して通す。

## 11. 進捗

- 完了: T-R0253、T-R0254、T-R0255、T-R0256、T-R0257、T-R0258、T-R0259、T-R0260、T-R0261、T-R0262、T-R0263、T-R0264、T-R0265。
- 未完了: T-R0266 から T-R0271。
- 未決: `scripts/e2e-lib.sh` と `scripts/e2e-contract.sh` を対象に入れるか。

## 12. scripts の JSON の読み（scripts/e2e-lib.sh、scripts/e2e-contract.sh）

利用者の判断を受けて、次の2か所を jq に置き換えた。

| 場所 | 旧 | 新 |
| --- | --- | --- |
| `scripts/e2e-contract.sh` の `family` の取り出し | `python3` で `taskdef.json` を読む | `"$_jq" -e -r '.family'`。`null` と `false` は失敗する |
| `scripts/e2e-lib.sh` の `swsc_wiremock_total` | `python3` で `/api/` の件数を数える | `swsc_count_api_requests`（jq）。`swsc_wiremock_total` はそれを呼ぶ |

残したもの:

- `swsc_wiremock_count_path`: 経路の完全一致の件数と、`requests[]` と `meta.total` の整合を確かめる。
  失敗ごとに個別の文言を出すため、section 4 の基準（`contract_c4` と同じ）により残す。
- `swsc_port_in_use`: socket の確認で、JSON を読まない。

jq の照合: `swsc_jq` は、最初に使うときだけ `resolve_tool jq` で固定版を照合する。
検査の sandbox は PATH を絞るため mise が見えない。そこで `run_unit` が照合済みの jq を
`SWSC_JQ` として渡す（`swsc_jq` は `SWSC_JQ` が設定されていれば照合しない）。
利用者の環境で `SWSC_JQ` を設定すると、照合を経ずに任意の実行ファイルが使われる。
そのため、この変数は検査専用として扱い、docs には書かない。

検査:

- `t_count_api_requests_counts_only_api_urls`（新規）: `/api/` の件数だけを数える。
- `t_json_extraction_uses_jq`: `scripts/e2e-contract.sh` に `json.load(` が無いこと、
  `scripts/e2e-lib.sh` の `json.load(` は `swsc_wiremock_count_path` の中だけにあること。

同じ入力での旧と新（7入力）: `/api/` の件数、空、`requests` の欠落、`url` が数字、`url` の欠落、
`requests` が文字列、空の配列。すべて旧と同じ結果だった。

注意: `family` が `null` のとき、旧は `"None"` を出して成功していた。新は失敗する（後の describe で失敗するため、早く止まるようにした）。

結果:

- `sh tests/m09-execution-and-ci.sh unit` は 235 件すべて通過。
- `sh tests/m07-scenario-isolation.sh unit` は 45 件、`sh tests/m08-e2e-suite.sh unit` は 20 件すべて通過。
- shellcheck（`-S style`）は、変更した5ファイルで通過。SC2031 は、`SWSC_JQ` の受け渡しに理由つきの `disable` で扱った。
- 実機の `contract` と `smoke`（Docker、AWS）は、この作業では実行していない。

## 13. Docker の smoke（T-R0268）

Docker（`/var/run/docker.sock`）で、変更したファイルに対応する smoke を直列で実行した。
各実行の後に、残ったコンテナ、ネットワーク、ボリューム、ロックファイルを数えた。すべて 0 だった。

| 検査 | 結果 | 補足 |
| --- | --- | --- |
| `sh tests/m03-wiremock-scenarios.sh smoke` | 通過 | 置き換えた `validate_json`、`validate_mapping` は、smoke の前半で動く |
| `sh tests/m07-scenario-isolation.sh smoke` | 通過（61 件） | unit は 45 件。名前から urlPath を引く jq の処理を実機で通る |
| `sh tests/m08-e2e-suite.sh smoke` | 通過（31 件） | 件数の取り出しを、実機の WireMock の応答で jq が読む |
| `sh tests/m09-execution-and-ci.sh smoke` | 通過（11 件） | unit は 235 件。所要 120 秒 |

smoke の終わりに出た `curl: (56)` と `wiremock_reset` の失敗は、
故障を起こす検査（遅延、再接続）と、停止後の後始末の表示である。どの検査も失敗にはなっていない。

注意: 実機の `contract`（MiniStack）は、利用者の端末と CI で実行する。この作業では実行していない。

## 14. 品質ゲート（T-R0270）

`sh scripts/quality-gate.sh` を、Node を PATH に入れて実行した。結果は `quality-gate: passed`（終了コード 0）。
ゲートが実行した検査: git の差分検査、shellcheck、actionlint、gitleaks（検出 0）、Markdown の lint、
`m03`、`m07`、`m08` の smoke（unit を含む）、S14 の unit、`m09` の unit と smoke。
実行の後の一時ファイルは、ログを含めて削除した。

まだ実行していない検査: `evidence-code-review` と `security-review`（T-R0269）。

## 15. コミット 3 のレビュー（T-R0269）

- `evidence-code-review`（修正前のスナップショット、d1f1c98 + 作業ツリー）: Critical、High、Medium は無し。
  SHOULD 1件を修正した。`validate_json` が空ファイルと `{} {}` を成功にしていたため、
  `jq -e -s 'length == 1'` にした。単体の検査 `unit_validate_json_rejects_empty_and_multiple_values` を追加した。
  BETTER 1件（jq の照合がサブシェルで繰り返される）は、結果に影響しないため、そのまま残した。
- `security-review`（修正後のスナップショット）: Critical、High、Medium は無し。Low 2件。
  - Low: 本番の入口が `SWSC_JQ` を無検証で使う。設定できるのは利用者のシェル、`.envrc`、CI の `env:` に限られる。
    権限は利用者と同じで、昇格にはならない。受け入れる。
  - Low: INT、TERM で終わると `/tmp` に空の一時ディレクトリが残る場合がある。秘密情報は含まない。受け入れる。
- 修正後の `validate_json` を、旧の Python 実装と5入力で比べた（空、`{} {}`、`[]`、`null`、壊れた JSON）。すべて旧と一致した。

未実施: 修正後のスナップショットに対する `evidence-code-review` の再実行（AGENTS.md の規則 7 の「入力検証を変えた」に該当する）。
