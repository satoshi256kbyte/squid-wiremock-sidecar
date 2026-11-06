# S26 実装計画

## 1. 設計の要点と方針

M09 の `scripts/e2e.sh` と pause 方式を、M02〜M08 と S14 の唯一の実行基盤にする。
既存の Client 出力、終了コード、WireMock の期待値は変えず、Compose のサービス名を検査から外す。

| 方針 | 対応する要件 |
| --- | --- |
| 共通起動、Client 実行、リセット、収集、停止を既存基盤へ接続する | FR-2601、FR-2603、FR-2604、NFR-2601、NFR-2603 |
| `swsc-` と `swsc.managed=true` の両方で資源を限定する | FR-2605、FR-2609 |
| 固定ポートを入口単位の mkdir ロックと事前検査で保護する | FR-2606、NFR-2602 |
| M08 の4シナリオを `test:ci` の直列検査へ追加する | FR-2602、FR-2607、NFR-2604 |
| S14 の Compose 展開検査を削除し、必要な契約だけを unit または smoke に移す | FR-2608、FR-2610 |
| 現行コード、文書、CI、設定を更新し、Compose は最後に削除する | FR-2611、FR-2612、FR-2613、NFR-2606 |
| WireMock 内部要求の除外と M08 TERM の再発検査を維持する | FR-2614 |
| ログ、成果物、文書から AWS 識別情報を除去する | NFR-2605 |

`spec.md` の Q-2601〜Q-2609 と `clarify.md` の推奨案を確定方針として扱う。
`api.example.com` から WireMock への実機疎通と、Client への特殊な環境変数渡しは未確認である。

## 2. 既存基盤と共通ヘルパー

### 2.1 再利用する公開インターフェース

| 既存関数または CLI | 利用方法 |
| --- | --- |
| `swsc_start_main`、`swsc_test_run` | 起動済み環境の準備、Client 検査、既存の終了コードを再利用する |
| `swsc_runner_start_all` | WireMock、pause、Squid の起動順と待機を再利用する |
| `swsc_runner_run_client` | taskdef の依存条件を確認して Client を一回実行する |
| `swsc_wiremock_reset` | `DELETE /__admin/requests` による受信記録のリセットに使う |
| `wiremock_reset`、`wiremock_verify_reset` | M07、M08 のシナリオリセットに使う。内部要求除外を変更しない |
| `swsc_collect`、`swsc_stop` | 失敗時を含む収集と、ラベル付き資源の後始末に使う |
| `e2e-taskdef.py render` | `swsc_render` 経由で taskdef を作る唯一の経路にする |
| `e2e-taskdef.py docker-args` | `swsc_runner_prepare` 経由で `.args`、`.env`、依存情報を作る |

根拠は `scripts/e2e-lib.sh:93-171、206-328、366-516`、
`scripts/e2e-runner.sh:9-191`、`scripts/e2e-taskdef.py:199-501` である。

### 2.2 追加するヘルパー

共通の低水準処理は `scripts/e2e-lib.sh` に追加する。
シナリオ固有の判定や検査名は各検査入口に残し、共通ファイルを過度に大きくしない。

| 関数 | 引数と終了コード | 責務 |
| --- | --- | --- |
| `swsc_lock_acquire` | なし。取得0、既存または失敗1 | 固定ポート用ディレクトリロックを取得する |
| `swsc_lock_release` | なし。解放0、対象不一致1 | 自分のロックだけを解放する |
| `swsc_check_ports_free` | `port...`。全て空き0、使用中または検査失敗1 | 指定されたポートを socket で確認する |
| `swsc_client_once_env` | `run_dir run_id base_url out err [NAME=VALUE...]`。Client の終了コード | `.args` に URL と任意の環境変数を追加して一回実行し、標準出力と標準エラーを分離する |
| `swsc_wiremock_count_path` | `url_path`。件数出力0、取得または解析失敗1 | 管理 API の path 件数を返す。内部要求を混ぜない |
| `swsc_squid_log_check` | `pattern...`。全一致0、不一致または取得失敗1 | `docker exec` で access log を読み、指定した文字列を検査する |
| `swsc_check_managed_empty` | なし。空0、残存または Docker 失敗1 | ラベルと接頭辞に一致する残存資源を検査する |

`swsc_client_once_env` は値をシェル文字列へ連結せず、各 `-e` を一要素の引数として渡す。
環境変数名と値に改行などの制御文字があれば1で止める。
`swsc_wiremock_count_path` は M08 の期待値比較に使い、リセット状態の検証は
`scripts/scenario-lib.sh` の `wiremock_verify_reset` を使う。

シナリオ名から URL パスへの変換は `scenario_path`、列挙は `scenario_names`、
静的検査は `scenario_check_static` を使う。M07 と M08 は同じ mapping directory を渡し、
`wiremock_verify_reset` の `/squid-internal-` 除外を維持する。

## 3. ポート排他と信号

### 3.1 ロック

ロックは `${SWSC_LOCK_DIR:-/tmp/swsc-e2e-ports.lock}` に置く。
`mkdir` の原子性だけを使うため、macOS と Linux の両方で動作する。
既定の置き場を `$TMPDIR` にしない。`$TMPDIR` はプロセスや端末ごとに異なる場合があり、
別の端末やエージェントのシェルとロックを共有できず、排他が効かなくなるためである。
8080、3128、4566 はホスト全体の資源なので、ホスト共通の固定の場所に置く。
ロックの中に所有者の PID と開始時刻を書き、取得に失敗したときの診断に使う（自動では剥がさない）。
ロック取得後に `swsc_check_ports_free 8080 3128 4566` を実行し、失敗時も解放する。

| 順序 | 処理 |
| --- | --- |
| 1 | 検査入口でロックを取得する |
| 2 | 8080、3128、4566 の空きを確認する |
| 3 | 新基盤の起動、検査、収集、停止を行う |
| 4 | 管理対象の残存を確認する |
| 5 | trap でロックを解放して終了コードを返す |

`test:ci` は起動から停止までロックを保持する。単独の `start` と `test` は各入口の
処理中にロックを保持し、並列実行しないことを文書化する。固定資源を継続利用する場合は
`test:ci` を使う。強制終了でロックが残った場合に自動で古いロックを剥がさない。
利用者は `ls -ld "$SWSC_LOCK_DIR"` と実行プロセス、管理対象コンテナを確認し、
実行中でないことを確認してからロックディレクトリを `rmdir` する。

ロック取得、ポート検査、起動の順を全入口で統一する。unit検査とサブエージェントの検査では、実ホストの既定ロックを使わず、
`SWSC_LOCK_DIR`を各実行専用の`$KIROCREW_SCRATCH`配下へ上書きする。CIのランナーは実行ごとに新規で、
既存ロックがないことを前提とする。既存ロックを自動削除せず、残っていれば失敗として原因を記録する。
INT と TERM は終了コード130、143を
保持し、trap の EXIT で収集、停止、ロック解放を行う。後始末中は同じ処理を二重にしても
壊れないようにし、`docker rm -f` とラベル検査を使う。

単独の入口は自分でロックを取得・解放する。`test:ci`はトップレベルで1回だけロックを取得し、
配下の検査へ`SWSC_LOCK_HELD=1`を渡して二重取得を避け、全検査と停止が終わってから解放する。

### 3.2 検査ごとの移行

| 検査 | 現在の Compose 呼び出し | 置き換え先 | 期待値を変えない確認 |
| --- | --- | --- | --- |
| M02 | WireMock への登録、proxy curl、`squid` の `exec` | `e2e.sh` の起動、管理 API、proxy curl、`swsc_squid_log_check` | 本文、受信記録、許可外失敗、access log の行を同じ値で比較 |
| M03 | `up`、起動待ち、mapping と本文の JSON 検査、`down` | `swsc_runner_start_all`、`scenario_check_static`、管理 API、`swsc_stop` | mapping 件数、必須項目、ステータス、遅延、無効入力の終了コードを維持 |
| M04 | `run test-client`、`-e` による失敗経路、`down` | `swsc_client_once_env` と taskdef の Client | Client の標準出力、診断出力、200、500、proxy 未設定の終了コードを維持 |
| M05 | `up`、Client、`squid` log、allowlist 外要求、`down` | pause の共有 namespace、`swsc_client_once_env`、`swsc_squid_log_check` | 許可要求の200、WireMock受信、許可外403、`TCP_DENIED` を維持 |
| M06 | `run` の retry、timeout、Client 内 shell、`down` | 任意環境変数付き Client 実行、`swsc_collect`、`swsc_stop` | 500/503/429、Retry-After、終了コード28、parse_retry_after を同じ値で確認 |
| M07 | `up`、reset、Client、Compose 残存確認、信号 | `scenario-lib.sh`、`swsc_client_once_env`、ラベル残存確認、入口 trap | reset、状態遷移、2周の再現、INT/TERM の130/143とcleanupを維持 |
| M08 | `m08-e2e` の `up`、4回の `run`、reset、信号、`down` | `test:ci` の検査列、scenario mapping、path 件数、ラベル cleanup | normal、500後成功、429、timeout の出力、終了コード、受信数、順序を維持 |
| S14 | `config`、`ps`、`exec`、Compose override と `down` | M09 unit と新しい taskdef/Squid smoke 契約検査 | loopback、ACL、parse、読み取り専用入力、403、拒否 log を別表の検査で確認 |

M06 の Docker `stop`、`restart`、`kill` を再現しない。M06 の実装に該当するのは
Client 実行、ログ収集、停止である。M07 と M08 の INT/TERM は既存の子プロセス送信方式を
残し、子の実行対象を新基盤の入口へ置き換える。判定は終了コード、`swsc.managed=true`
の残存、作業ディレクトリの空、cleanup の記録で行う。

M08 smoke は移行後に同一条件で2回連続実行し、各回の TERM ケースを記録する。
1回でも終了コード、cleanup、残存判定が外れたら合格にしない。以前に1回だけ失敗した
TERM ケースは、失敗時の子 stderr と信号から終了までの時間を保存し、再発か環境依存かを
レビューで判定する。

## 4. S14 の置き換え

| S14 の項目 | 分類 | 置き換え先と検査名 |
| --- | --- | --- |
| Compose のサービス名、`sidecar`、展開 JSON | 削除 | 検査しない。taskdef と固定コンテナ名の unit で構造だけ確認する |
| Compose の `ps` 表示形式、Compose project 名 | 削除 | `swsc-` と `swsc.managed=true` の残存検査へ置き換える |
| WireMock の loopback 公開 | M09 unit で済む | `tests/m09-execution-and-ci.sh` の Runner 公開範囲検査 |
| MiniStack の loopback 公開、Docker socket 不使用 | M09 unit で済む | 同入口の taskdef 引数検査と socket 不使用検査 |
| Squid と WireMock の派生元入力コピー | M09 unit で済む | `swsc_stage_squid_context` と読み取り専用入力の unit 検査 |
| 固定 ACL 行の完全一致 | 新規検査 | `tests/s14-taskdef-contract.sh` の `squid_acl_lines` |
| 派生設定の `squid -k parse` | 新規検査 | 同ファイルの `derived_config_parse`。mock と direct を分ける |
| 許可外要求の403と `TCP_DENIED` | 新規検査 | M05 smoke の `offlist_denied_and_logged` |
| WireMock mapping の読み取り専用渡し | 新規検査 | `tests/s14-taskdef-contract.sh` の `wiremock_mapping_readonly` |
| Squid の非 loopback 公開拒否 | 新規検査 | 同ファイルの `squid_not_host_published` |

S14 の Compose 展開入力が無くなるため、Compose 固有のサービス名、network 名、override、
展開 JSON の比較は復活させない。新規検査は taskdef の `docker-args` 出力、
`e2e-runner.sh` の `-p 127.0.0.1:8080:8080`、Squid の派生入力を根拠にする。

## 5. 品質ゲート

`scripts/quality-gate.sh` は、共通の差分、`sh -n`、Markdown を先に実行し、
移行対象に対して unit、対象 smoke、M08 4シナリオ、残存資源検査を直列に行う。
`tests/m09-execution-and-ci.sh` の unit と smoke は既存どおり登録し、contract は利用者の
端末と CI だけで実行する。

現在の Compose 参照5箇所は次のように扱う。

| 参照 | 現在の役割 | 移行後 |
| --- | --- | --- |
| 変更条件の `docker-compose.yml` | Compose 変更時の分岐 | M02〜S14 と新基盤の対象条件へ統合 |
| `docker-compose config --quiet` | 設定展開 | 削除 |
| ループ内の Compose 対象条件 | 各 smoke の選択 | 新基盤の検査選択へ置換 |
| 既定 project の残存確認 | Compose 残存の検出 | ラベル付き資源の残存確認 |
| `m08-e2e` project の残存確認 | M08 固有残存の検出 | 同じラベル付き資源の確認へ統合 |

残存確認は `docker ps -a --filter label=swsc.managed=true` を明示的に実行し、
コマンド失敗も status=1 とする。`|| true` で包んだ Docker 呼び出しを残さない。
終了コードを失わないように、一時変数への代入と `if ! ...; then status=1; fi` を使う。

現時点の実測を見積りの基準にする。

| 区分 | 既存の目安 | 計画上の扱い |
| --- | --- | --- |
| M09 unit | 約73秒 | 毎回実行する |
| M09 smoke | 約110〜130秒 | メインエージェントと CI で実行する |
| M03〜M07、S14 | 合計約246秒 | 移行対象の変更時に直列実行する |
| M08 smoke | 約85〜88秒 | 4シナリオと信号ケースを含めて実測する |

合計時間と timeout は推測で固定しない。CI 実測後に `docs/ローカル実行とCI.md` と
workflow の値を更新する。

## 6. CI の変更

`.github/workflows/e2e-test.yml` の job 名 `e2e` と既存の step 名、required status check に
影響する名称は変えない。M08 の4シナリオは専用 step を作らず、`npm run test:ci` の検査列へ
直列で追加する。ローカルの `test:ci` と CI の入口、シナリオ、期待値、cleanup を一致させる。初回CIとcontractは、
フェーズ4のコミット後、Compose削除前に同じPRで実行する。実測値のdocsとworkflowへの反映は、初回CIの完了後かつ
フェーズ5のCompose削除前に行う。Compose削除後のCIは、同じPRの更新として再実行する。

CI 実測後に次を順に見直す。

1. `test-ci` の実行時間と、4シナリオ追加による増分を記録する。
2. `unit`、`smoke`、`contract` の各 timeout に、直近の実測と待機上限を反映する。
3. job 全体が15分以内か確認し、必要な場合だけ workflow の仮値を変更する。
4. step 名、job 名、required status check 名が変わっていないことを確認する。

M08 のシナリオ別結果、実行秒数、CI の timeout 根拠は、識別情報を含まない検証記録と
`docs/ローカル実行とCI.md` に残す。

## 7. 文書と設定の変更

| ファイル | 変更する記述 |
| --- | --- |
| `README.md` | Docker Compose の機能説明、構成図の表現、構成一覧、Prerequisites、旧 pnpm 手順を削除し、npm 入口、lock、M08 の CI 範囲を記載する |
| `docs/ローカル実行とCI.md` | Compose の旧節と M08 の旧入口を削除し、固定ポート、lock、timeout 実測、4シナリオ、cleanup を記載する |
| `docs/E2Eテスト.md` | M08 の Compose 実行、project 名、残存確認を taskdef、scenario mapping、label 検査へ更新する |
| `docs/ポート公開範囲.md` | `docker-compose ps` と `sidecar` の説明を、loopback 公開と pause namespace の説明へ更新する |
| `docs/シナリオ隔離.md` | Compose の down と project 隔離を、reset、入口 lock、ラベル cleanup へ更新する |
| `docs/requirements.md`、`docs/roadmap.md` | 現行手順として残る Compose の記述だけを taskdef 方式へ更新し、履歴の意味は変えない |
| `AGENTS.md` | Compose config の品質ゲートを削除し、移行対象 smoke、label 残存、M09 unit/smoke の表へ更新する |
| `package.json` | 既存の `start`、`test`、`logs`、`stop`、`clean`、`test:ci` の npm 入口を維持し、Compose を呼ぶ script を追加しない |
| `.github/workflows/e2e-test.yml` | step 名と job 名を維持し、実測後に timeout の仮値だけを見直す |

過去の `specs/M02`〜`specs/M09`、S14 の Spec Kit 成果物と、今回の `spec.md`、
`clarify.md`、`tasks.md` は変更しない。文書更新後は `npm run -s lint:md` を実行する。

## 8. Compose 削除の手順

フェーズ5では、初回CIとcontractの実測値を先にdocsとworkflowへ反映し、その後に`docker-compose.yml`を削除する。削除前に全検査、品質ゲート、CI、
現行文書を移行済みとして、削除後に同じ入口を実行可能な状態にする。削除と実測反映は同じPRの追補として扱う。

削除で失敗する経路は、M03〜M08 の `up`、`run`、`exec`、`down`、S14 の config と
Compose override、品質ゲートの config と project 残存確認である。削除だけでは、
`|| true` 内の呼び出し、実行されない分岐、unit だけで smoke を通さない経路を見逃す。
したがって、削除後に静的 grep と実行検査を両方行う。

一回限りの確認は、現行コード、現行文書、CI、設定だけを対象にする。コメント、過去の
Spec Kit 成果物、履歴文書は除外し、呼び出しとしての `docker-compose` と `docker compose`
を探す。コマンドの形は次のとおりとし、結果を値のマスクされた記録へ保存する。

```sh
git grep -nE '(^|[[:space:]"'"'"'(=])docker(-compose| compose)([[:space:]]|$)' \
  -- scripts tests ecs .github docs README.md AGENTS.md package.json \
  ':(exclude)specs/**' > specs/S26-migrate-e2e-to-taskdef/verification/compose-grep.txt
```

上記の対象にコメントが含まれる場合は、同じ結果をコメント除外フィルタへ通し、
呼び出し0件であることを記録する。
`tests/m09-execution-and-ci.sh` は FR-920 の検出パターンと偽の `docker-compose` を持ち、
文字列としての `docker-compose` が残る。これは呼び出しではないため、除外ファイルとして明示し、
理由と該当行を同じ記録に残す。除外を暗黙にしない。grep の終了コード、対象範囲、除外一覧、実行日時を
`specs/S26-migrate-e2e-to-taskdef/verification/compose-grep.txt` に残す。
その後、`sh -n`、M09 unit、品質ゲート、CI、Markdown lint、`git status --short` を確認する。

## 9. フェーズ分割と成果物

PR は1つとし、次の5コミットに分ける。各フェーズで品質ゲートが通る状態を保ち、
フェーズ間で `spec.md`、`clarify.md`、`tasks.md`、過去の Spec Kit 成果物、
`.kiro/settings/cli.json` は変更しない。

| フェーズ | 対象 | 完了条件とコミット単位 |
| --- | --- | --- |
| 1 | `scripts/e2e.sh`、`scripts/e2e-lib.sh`、必要な runner、共通検査 | helper、lock、入口が `sh -n` と M09 unit を通る。未確認の pause 通信と Client env を smoke で早期確認する |
| 2 | M02〜M05 と関連検査 | 新基盤で本文、終了コード、受信数、allowlist、Squid log を比較し、各対象スクリプトの直接実行と共通基盤の unit が通る |
| 3 | M06〜M08、`scripts/scenario-lib.sh` の接続 | retry、timeout、reset、4シナリオ、INT/TERM、2回の M08 smoke が通る |
| 4 | S14、quality gate、CI、README、docs、AGENTS、package | S14の置換検査、M09 unit、quality gate、Markdown lint、CI静的検査が通り、フェーズ4をコミットできる |
| 5 | `docker-compose.yml` 削除、grep 記録、最終確認 | フェーズ4コミット後の初回CIとcontractを実測し、根拠を反映してから削除、grep、最終ゲートを行い、同じPRを更新する |

各フェーズの移行前後の出力、終了コード、シナリオ結果、実行秒数は、
`specs/S26-migrate-e2e-to-taskdef/verification/phase-<番号>-results.md` に保存する。
次フェーズへ渡す記録には、実行環境、未実行の層、失敗時のログ名、比較対象、
識別情報の検査結果を含める。AWS 識別子、ARN、認証情報、未マスクの実値は記録しない。

## 10. 検証境界とレビュー

| 層 | 実行内容 | 実行主体 |
| --- | --- | --- |
| unit | Docker なしの関数、taskdef、scenario、lock、呼び出し順の検査 | メインエージェントまたはサブエージェント |
| smoke | 実 Docker の pause、Squid、WireMock、Client 通信と信号 | メインエージェントだけ |
| contract | 利用者の端末または CI の MiniStack contract | 利用者の端末と CI |
| review | フェーズ5後の evidence-code-review と security-review | 2件を直列で実行 |

本計画作成時は Docker を起動せず、テストを実行しない。実装後の smoke と contract を
実行済みとは扱わない。`sh -n`、grep、Markdown lint は各フェーズの完了条件に従う。

## 11. リスクと未確認

| リスクまたは未確認 | 対応 |
| --- | --- |
| pause namespace で `api.example.com` の要求が `swsc-wiremock` peer へ届くこと | M09 の smoke（許可ドメインが200、受信数が `/api/` のみ）と M09 の初回 CI で確認済み。フェーズ1では再確認だけを行い、追加の調査をしない |
| M04/M06 の複数の `-e` 指定を現行 Client 実行方式へ渡せること | `swsc_client_once_env` の unit と、M04/M06 smoke の実測で確認する |
| Squid の access log を新しい `docker exec` 経路で読めること | M02/M05 smoke と収集結果で確認する |
| 4566 の contract と 8080/3128 の smoke が同じ lock で競合しないこと | 入口ごとの取得順と、CI の直列実行を unit と CI で確認する |
| TERM の単発失敗が移行後も起きること | M08 smoke を2回実行し、失敗時の stderr、終了コード、残存を保存する |
| `ubuntu/squid:latest` の差分で parse またはログ形式が変わること | 実行時の基底 digest を収集し、実測値とともに記録する |

実機で確認していないものを、設計上の期待値や既存コード上の事実と混同しない。

## 12. FR/NFR と設計の対応

| ID | 設計、実装、検証の対応 |
| --- | --- |
| FR-2601 | M02〜S14 の入口を `e2e.sh`、pause、taskdef に統一する |
| FR-2602 | Client 出力、終了コード、4シナリオ、受信数の移行前後比較を保存する |
| FR-2603 | 起動待ち、Client、reset、log、cleanup を共通 helper へ接続する |
| FR-2604 | pause namespace、`swsc-wiremock` peer、読み取り専用 mapping で通信経路を置換する |
| FR-2605 | `swsc-` と `swsc.managed=true` の両方で停止、削除、残存確認を行う |
| FR-2606 | mkdir lock と 8080/3128/4566 の事前検査を全入口へ適用する |
| FR-2607 | `test:ci` の直列列へ M08 の4シナリオを追加する |
| FR-2608 | S14 の Compose 展開を削除し、M09 unit と新規契約検査へ分ける |
| FR-2609 | quality gate の config と Compose project 検査を削除し、label 検査へ移す |
| FR-2610 | M09 unit の FR-920 相当の検出を再利用し、恒久的な Compose grep は作らない |
| FR-2611 | README、docs、AGENTS、CI、scripts の現行前提を更新する |
| FR-2612 | フェーズ5の先頭で `docker-compose.yml` を削除する |
| FR-2613 | 現行範囲だけを対象に一回限りの呼び出し grep を行い記録する |
| FR-2614 | `wiremock_verify_reset` の内部要求除外と M08 TERM の再発検査を維持する |
| NFR-2601 | Compose 併用、切り戻し、救済経路を残さず taskdef に一本化する |
| NFR-2602 | 固定ポートを lock と直列実行で保護し、別入口の並列実行を禁止する |
| NFR-2603 | ローカルと CI で同じ入口、mapping、期待値、cleanup を使う |
| NFR-2604 | CI 実測後に timeout と所要時間の根拠を docs と workflow に記録する |
| NFR-2605 | 収集物、文書、検証記録から AWS 識別情報と認証情報を除外する |
| NFR-2606 | 過去の Spec Kit 成果物を変更せず、現行文書だけを更新する |
