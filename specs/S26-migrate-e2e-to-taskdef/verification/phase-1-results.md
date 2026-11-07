# S26 フェーズ1 検証結果

フェーズ1（共通関数と入口。T2601〜T2605）の結果を記録する。
実行主体は、実装がサブエージェント、実機の検証と品質ゲートがメインエージェントである。
AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 変更範囲

| ファイル | 変更 |
| --- | --- |
| `scripts/e2e-lib.sh` | ロックとポート確認、環境変数付きClient実行、パス完全一致の受信数、Squidログ検査、管理対象の残存検査、入口へのロック組み込み |
| `scripts/e2e-contract.sh` | `contract`の先頭でロックを取り、MiniStack削除の後に解放する |
| `tests/m09-execution-and-ci.sh` | T2601〜T2603のunit。実ホストのロックを使わないよう、`SWSC_LOCK_DIR`をscratchへ上書きする |

`scripts/e2e.sh`と`scripts/e2e-runner.sh`は変更していない。入口のtrapは`scripts/e2e-lib.sh`の関数が持つため、
ロックの組み込みもそこで完結した。M03〜M08とS14は、変更したファイルを読み込まないため、影響を受けない。

## 2. 実行結果

| 層 | 内容 | 結果 |
| --- | --- | --- |
| 構文 | `sh -n`（変更した全shファイル）、`python3 -B -m py_compile scripts/e2e-taskdef.py` | 通過 |
| 差分 | `git diff --check` | 通過 |
| unit | `sh tests/m09-execution-and-ci.sh unit` | 214件中214件通過（約76秒）。着手前は192件 |
| smoke（実Docker） | `sh tests/m09-execution-and-ci.sh smoke` | 11件中11件通過。1回目252秒、2回目131秒、品質ゲート内123秒 |
| 品質ゲート | `sh scripts/quality-gate.sh` | 通過（200秒） |
| contract | 利用者の端末とCI | 未実行（フェーズ4のCIで実行する） |

smokeの1回目が252秒だったのは、その時点の環境の状態による。同じsmokeの2回目は131秒、品質ゲート内は123秒で、
M09の以前の値（約110〜130秒）と同じである。原因は特定していない。

## 3. 実機で確認した内容（T2604）

M04とM06はこの時点でComposeに依存しているため、それらのsmokeは実行していない。
代わりに、新しい関数を実機のスタック（`swsc-wiremock`、`swsc-pause`、`swsc-squid`）に対して直接確かめた。

| 確認 | 結果 |
| --- | --- |
| 許可ドメインへの要求 | 終了コード0、HTTP 200。pause共有のネットワークからWireMockへ届く |
| パスの完全一致 | `/api/users/123`の受信数が1、`/api/users/12`が0 |
| 環境変数の上書き | `TEST_API_PATH`が`docker run`に届き、WireMockが404を返した。受信数は上書き先が1、既定のパスが0 |
| 空白と記号を含む値 | コマンドとして実行されず、値のままClientへ届く（Clientが不正なURLと判定した） |
| 改行を含む値 | dockerを呼ばずに終了コード2で止まる。値は表示しない |
| 許可外ドメイン | HTTP 403。Squidのログに`TCP_DENIED`が一致する |
| Squidログ検査 | 一致は0、不一致は1、`$(id)`のようなシェル記号は固定文字列として扱われ実行されない |
| ロック | `start`の終了後にロックが解放される。smokeの項目6と7（8080の占有で止まる、理由に旧基盤を示す）が通過 |

## 4. 識別情報の検査と後始末

| 項目 | 結果 |
| --- | --- |
| 追加した行のアカウント識別子、ARN、利用者の絶対パス | なし |
| `swsc-`のコンテナとネットワーク | 0件 |
| ロック（`/tmp`と検査用） | 残っていない |
| `__pycache__`、`e2e-logs/` | なし |

## 5. 次フェーズへ渡す事項

| 事項 | 内容 |
| --- | --- |
| 未接続の関数 | `swsc_check_managed_empty`は定義だけで、どの操作からも呼ばれていない。T2621で品質ゲートへ接続する |
| unitの一時停止 | サブエージェントの1回目のunitが途中で止まり、再実行で通った。メインの3回の実行では再現しなかった。原因は未特定 |
| 実行環境の注意 | macOSには`timeout`コマンドが無い。時間制限が要るときはPythonの`subprocess`を使う |
| 未実行の層 | contractはCIで実行する。M04とM06の実機smokeは、フェーズ2と3の移行後に実行する |

## 6. 再実行の結果（2026-11-07、Linux aarch64のEC2）

フェーズ1の完了確認として、別の環境で再実行した。AWSアカウント識別子、ARN、認証情報は記録しない。

| 層 | 内容 | 結果 |
| --- | --- | --- |
| unit | `sh tests/m09-execution-and-ci.sh unit` | 215件中215件通過 |
| smoke（実Docker） | `sh tests/m09-execution-and-ci.sh smoke` | 11件中11件通過（単独137秒、品質ゲート内115秒） |
| Markdown検査 | `npm run -s lint:md`（Node v22、markdownlint-cli2 0.24.0） | 73ファイル、指摘0件 |
| 品質ゲート | `sh scripts/quality-gate.sh` | 失敗（下記の環境要因のみ） |
| 後始末 | `swsc.managed=true`のコンテナ | 0件 |

### 品質ゲートの失敗の内訳

| 項目 | 原因 | 判定 |
| --- | --- | --- |
| `docker-compose config --quiet` | この環境に`docker-compose`が無い | 環境要因。本Issueで削除する項目（T2621）。成功とは断定しない |
| `markdownlint-cli2`未導入 | 初回は`node`と`npm`が無かった | 解消済み。Node v22を導入し、`npm ci`の後に`lint:md`が通過 |

品質ゲートの全体通過は、`docker-compose`を使える環境、またはT2621でCompose項目を削除した後に確認する。
未実行の層は、次のとおりである。

- contract（フェーズ4のCIで実行する）
- M04とM06の実機smoke（フェーズ2と3の移行後に実行する。T2604のこの部分は未完了で、3章の関数の直接確認で代えた）

unitの件数は、2章が214件、この章が215件である。1件の増加の原因は未確認である。

## 7. コミット前の必須レビュー（2026-11-07）

スキルごとに独立したサブエージェント（Claude Sonnet 5.5、effort medium）で、直列に実行した。
対象は6章の追記と、フェーズ1の実装（`scripts/e2e-lib.sh`、`.github/workflows/e2e-test.yml`など）である。

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Critical・High・Mediumなし。SHOULD 1件、NITS 1件 | 6章の未実行の層（M04・M06の実機smoke）の追記、unit件数の差の注記で解消 |
| `security-review` | Critical・High・Mediumなし。Low 1件 | 対応しない。固定ロックパス（`/tmp`直下）は、共有マルチユーザー環境の可用性だけの低下で、CIと単一利用者の端末では実害がない。必要なら`SWSC_LOCK_DIR`の既定値を利用者専用にする（フェーズ2以降で検討） |

確認していない範囲は、収集物のマスク規則の網羅性と、`tests/m09-execution-and-ci.sh`、`scripts/quality-gate.sh`の全行である。
`evidence-code-review`の指摘はSHOULDとNITSだけで、再レビューの対象に当たらない。
