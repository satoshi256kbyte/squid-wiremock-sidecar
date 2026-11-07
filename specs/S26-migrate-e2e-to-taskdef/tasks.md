# S26 実装タスク

## 進め方

`spec.md`、`clarify.md`、`plan.md`の決定を実装する。各実装バッチは3〜5タスクに分け、
同じ対象ファイルを持つタスクは同時に実行せず、表のバッチ内順序に従って直列化する。バッチDは対象を分け、
文書更新と`package.json`更新を別タスクにする。実機のDockerを使うsmokeとcontractは、実装サブエージェントに実行させない。

フェーズごとに移行前後の比較を保存し、品質ゲートを通過してから次へ進む。コミットは利用者の指示後に
フェーズごとに1つ作る。pushとPR作成は利用者の端末で実行する。

## フェーズ1 共通関数と入口

対象範囲は`plan.md` 2〜3章と9章フェーズ1である。未確認のpause通信とClient環境変数は、
このフェーズでsmokeを実行して早期に確認する。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T2601 | 固定ポートを保護するmkdirロックと、8080・3128・4566の空き確認を追加する。所有者以外の解放を拒否する。unitでは`SWSC_LOCK_DIR`を各実行専用の`$KIROCREW_SCRATCH`配下へ上書きし、実ホストの既定ロックを使わない。 | `scripts/e2e-lib.sh`、`tests/m09-execution-and-ci.sh` | FR-2606、NFR-2602 | `lock_acquire_busy`、`lock_release_non_owner`、`check_ports_free` | `SWSC_LOCK_DIR`を分離した`sh tests/m09-execution-and-ci.sh unit`が終了コード0になる。 | 実装サブエージェント | A-1 |
| T2602 | Clientの任意環境変数、WireMockのpath件数、Squidログ検査の共通関数を追加する。制御文字を含む値は拒否する。 | `scripts/e2e-lib.sh`、`tests/m09-execution-and-ci.sh` | FR-2603、FR-2614、NFR-2603 | `client_once_env_rejects_control`、`wiremock_count_path`、`squid_log_check` | `sh tests/m09-execution-and-ci.sh unit`が終了コード0になり、引数が要素単位で渡る。 | 実装サブエージェント | A-2 |
| T2603 | runnerのラベル・接頭辞管理と、e2e入口のlock、port検査、trap、cleanupの順序を共通化する。`test:ci`はトップレベルでlockを1回だけ取得し、配下の検査へ`SWSC_LOCK_HELD=1`を渡して二重取得を避ける。 | `scripts/e2e-runner.sh`、`scripts/e2e.sh`、`tests/m09-execution-and-ci.sh` | FR-2601、FR-2605、FR-2609、NFR-2601 | `managed_empty`、`entry_trap_exit_143`、`runner_labels` | `sh -n scripts/e2e.sh scripts/e2e-lib.sh scripts/e2e-runner.sh`と`sh tests/m09-execution-and-ci.sh unit`が終了コード0になる。 | 実装サブエージェント | A-3 |
| T2604 | M09 smokeを基準に、pause namespaceからWireMockへ到達することと、M04・M06の環境変数渡しを早期確認する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-1-results.md` | FR-2604、FR-2606、NFR-2603 | なし（実機通信はsmokeで確認） | メインが`sh tests/m09-execution-and-ci.sh smoke`、M04とM06のsmokeを実行し、終了コード0と未確認事項を記録する。 | メイン | — |
| T2605 | フェーズ1の品質ゲートを実行し、移行前後の基盤結果、実行環境、未実行層、識別情報検査を記録する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-1-results.md` | FR-2601、FR-2603、FR-2605、FR-2606、NFR-2601〜2603、NFR-2605 | なし | `sh scripts/quality-gate.sh`と`python3 -B -m py_compile scripts/e2e-taskdef.py`が終了コード0で、結果ファイルが保存される。 | メイン | — |
| T2606 | フェーズ1の差分と結果を確認した後、利用者の指示を待ってフェーズ1のコミットを作る。pushは行わない。 | 変更対象全体 | NFR-2606 | なし | `git diff --check`が終了コード0で、利用者がフェーズ1だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ2 M02〜M05

対象範囲は`plan.md` 3.2のM02〜M05である。Compose呼び出しを検査から外し、Client出力、
終了コード、受信数、allowlist、Squidログを移行前後で比較する。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T2607 | M02を新基盤の起動、proxy要求、WireMock登録、Squidログ検査へ移行する。期待する本文と受信記録を維持する。 | `tests/m02-routing-smoke.sh` | FR-2601〜2604、FR-2614、NFR-2601、NFR-2603 | なし（既存スクリプトはモード引数を持たない） | `sh -n tests/m02-routing-smoke.sh`が終了コード0で、compose呼び出しが残らない。実機の実行はT2611でメインが行う。 | 実装サブエージェント | B |
| T2608 | M03をrunner起動、mapping静的検査、管理API、後処理へ移行する。無効入力と遅延を含む既存の判定を維持する。 | `tests/m03-wiremock-scenarios.sh` | FR-2601〜2604、NFR-2601、NFR-2603 | なし（既存スクリプトはモード引数を持たない） | `sh -n tests/m03-wiremock-scenarios.sh`が終了コード0で、compose呼び出しが残らない。実機の実行はT2611でメインが行う。 | 実装サブエージェント | B |
| T2609 | M04を共通Client実行へ移行し、標準出力、診断出力、200・500、proxy未設定の終了コードを維持する。 | `tests/m04-test-client.sh` | FR-2601〜2603、FR-2614、NFR-2601、NFR-2603 | なし（既存スクリプトはモード引数を持たない） | `sh -n tests/m04-test-client.sh`が終了コード0で、compose呼び出しが残らない。実機の実行はT2611でメインが行う。 | 実装サブエージェント | B |
| T2610 | M05をpause共有namespaceへ移行し、許可要求、許可外403、WireMock受信数0、TCP_DENIEDを確認する。 | `tests/m05-proxy-integration.sh` | FR-2601〜2605、FR-2614、NFR-2601〜2603 | なし（既存スクリプトはモード引数を持たない） | `sh -n tests/m05-proxy-integration.sh`が終了コード0で、compose呼び出しが残らない。実機の実行はT2611でメインが行う。 | 実装サブエージェント | B |
| T2611 | M02〜M05の実機smokeをメインが直列実行し、移行前後の出力、終了コード、受信数、ログを比較する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-2-results.md` | FR-2602〜2604、FR-2614、NFR-2603、NFR-2605 | なし | 対象4スクリプトのsmokeがすべて終了コード0で、比較記録と識別情報検査結果が保存される。 | メイン | — |
| T2612 | フェーズ2の品質ゲートと結果記録を実行する。失敗時のログ名と、次フェーズへ渡す未確認事項を残す。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-2-results.md` | FR-2601〜2606、NFR-2601〜2605 | なし | `sh scripts/quality-gate.sh`と`git diff --check`が終了コード0で、結果ファイルが保存される。 | メイン | — |
| T2613 | フェーズ2の差分と結果を確認した後、利用者の指示を待ってフェーズ2のコミットを作る。pushは行わない。 | 変更対象全体 | NFR-2606 | なし | `git diff --check`が終了コード0で、利用者がフェーズ2だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ3 M06〜M08

対象範囲は`plan.md` 3.2と9章フェーズ3である。retry、timeout、reset、4シナリオ、INT/TERM、
cleanupを新基盤で確認し、M08 smokeは2回連続で実行する。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T2614 | M06を任意環境変数付きClient実行へ移行し、retry、timeout、Retry-After、終了コード28、ログ収集を維持する。 | `tests/m06-client-resilience.sh` | FR-2601〜2603、FR-2614、NFR-2601〜2603 | `m06_retry_after`、`m06_timeout_exit_28` | `sh tests/m06-client-resilience.sh unit`が終了コード0で、compose呼び出しが残らない。smokeはT2617でメインが行う。 | 実装サブエージェント | C |
| T2615 | M07のreset、状態遷移、2周の再現、入口trap、INT/TERM、ラベル残存確認を新基盤へ接続する。 | `scripts/scenario-lib.sh`、`tests/m07-scenario-isolation.sh` | FR-2601〜2605、FR-2614、NFR-2601〜2603 | `m07_reset_excludes_internal`、`m07_signal_exit_codes` | `sh tests/m07-scenario-isolation.sh unit`が終了コード0で、compose呼び出しが残らない。smokeはT2617でメインが行う。 | 実装サブエージェント | C |
| T2616 | M08をtest:ciの直列検査へ移行し、normal、500後成功、429、timeoutの出力、終了コード、受信数を維持する。 | `tests/m08-e2e-suite.sh`、`scripts/e2e.sh` | FR-2601〜2607、FR-2614、NFR-2601〜2604 | `m08_scenario_expectations`、`m08_term_cleanup` | `sh tests/m08-e2e-suite.sh unit`が終了コード0になり、4シナリオを`test:ci`から選択できる。 | 実装サブエージェント | C |
| T2617 | M06〜M08のsmokeを直列実行し、M08の4シナリオとTERMケースを2回連続で実測する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-3-results.md` | FR-2602、FR-2603、FR-2607、FR-2614、NFR-2602〜2605 | なし | 対象smokeが終了コード0で、各シナリオの秒数、stderr、終了コード、残存、TERM結果を2回分保存する。 | メイン | — |
| T2618 | フェーズ3の品質ゲートと比較記録を実行し、`wiremock_verify_reset`の内部要求除外を差分確認する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-3-results.md` | FR-2602、FR-2607、FR-2614、NFR-2601〜2605 | なし | `sh scripts/quality-gate.sh`、`sh tests/m09-execution-and-ci.sh unit`、`git diff --check`が終了コード0になる。 | メイン | — |
| T2619 | フェーズ3の差分と結果を確認した後、利用者の指示を待ってフェーズ3のコミットを作る。pushは行わない。 | 変更対象全体 | NFR-2606 | なし | `git diff --check`が終了コード0で、利用者がフェーズ3だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ4 S14・品質ゲート・CI・文書

対象範囲は`plan.md` 4〜7章と9章フェーズ4である。S14のCompose展開検査を削除し、必要な契約を
unitまたは新基盤へ移す。フェーズ4の変更をコミットした後に同じPRを作成し、Composeが残る状態で初回CIとcontractを実行する。実測値の反映とCompose削除はフェーズ5で行う。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T2620 | S14の固定ACL行、派生設定parse、WireMock mappingの読み取り専用、Squid非公開を契約検査へ移す。Compose展開検査は削除する。 | `tests/s14-taskdef-contract.sh`、`tests/m09-execution-and-ci.sh` | FR-2608、FR-2610、NFR-2601、NFR-2603、NFR-2605 | `s14_acl_lines`、`s14_derived_config_parse`、`s14_mapping_readonly` | `sh tests/s14-taskdef-contract.sh unit`と`sh tests/m09-execution-and-ci.sh unit`が終了コード0になる。 | 実装サブエージェント | D |
| T2621 | quality-gateからCompose configとproject残存検査を削除し、Docker失敗を見逃さないlabel残存検査へ置換する。 | `scripts/quality-gate.sh` | FR-2609、FR-2610、NFR-2601、NFR-2602 | `managed_resource_check_failure` | `sh scripts/quality-gate.sh`が終了コード0で、`swsc.managed=true`の検査失敗をstatus=1にする。 | 実装サブエージェント | D |
| T2622 | CIのjob名とstep名を維持し、M08の4シナリオを`test:ci`へ追加する。timeoutは実測後にだけ変更する。 | `.github/workflows/e2e-test.yml` | FR-2607、FR-2609、FR-2611、NFR-2603、NFR-2604 | `ci_test_ci_scenarios` | `git diff --check`とCI定義の静的検査が終了コード0で、既存のrequired status check名が変わらない。 | 実装サブエージェント | D |
| T2623 | README、現行docs、AGENTS.mdの入口、lock、CI範囲、cleanupを移行後の前提へ更新する。過去Spec Kit成果物は変更しない。 | `README.md`、`docs/*.md`、`AGENTS.md` | FR-2611、NFR-2604〜2606 | `docs_current_entry` | `npm run -s lint:md`と`git diff --check`が終了コード0で、現行文書だけにCompose前提が残らない。 | 実装サブエージェント | D-1 |
| T2623a | `package.json`のnpm入口を維持し、Composeを呼ぶscriptを追加しない。 | `package.json` | FR-2611、NFR-2606 | `package_entry` | `npm run -s lint:md`と`git diff --check`が終了コード0になる。 | 実装サブエージェント | D-2 |
| T2624 | フェーズ4のsmoke、unit、品質ゲート、Markdown lint、CI静的検査をメインが実行する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-4-results.md` | FR-2607〜2611、NFR-2601〜2606 | なし | `sh tests/m09-execution-and-ci.sh smoke`、`sh scripts/quality-gate.sh`、`npm run -s lint:md`が終了コード0になる。 | メイン | — |
| T2628 | フェーズ4のローカル結果、文書差分、品質ゲートを確認し、PR作成前の結果を保存する。CI実測とIssueのクローズ確認は後続タスクで行う。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-4-results.md` | FR-2608〜2611、NFR-2604〜2606 | なし | `sh scripts/quality-gate.sh`と`git status --short`が期待どおりで、結果ファイルが保存される。 | メイン | — |
| T2629 | フェーズ4の差分と結果を確認した後、利用者の指示を待ってフェーズ4のコミットを作る。pushは行わない。 | 変更対象全体 | NFR-2606 | なし | `git diff --check`が終了コード0で、利用者がフェーズ4だけを含むコミットを作成する。 | 利用者 | — |
| T2625 | T2629でフェーズ4をコミットした後、利用者が同じPRを作成し、Composeが残る状態でCI初回実行とcontractを確認する。実測値をメインへ渡す。 | CI、`tests/m09-execution-and-ci.sh` | FR-2607、FR-2611、NFR-2603、NFR-2604 | なし（contractは利用者実行） | 初回CIのrequired checksが成功し、`sh tests/m09-execution-and-ci.sh contract`が終了コード0になる。 | 利用者 | — |

## フェーズ5 Compose削除と一回限りのgrep

フェーズ1〜4のゲートが通過し、移行前提のCIと現行文書が更新済みであることを前提にする。
フェーズ4のコミット後に同じPRで初回CIとcontractを実行し、実測値を反映してからComposeを削除する。
削除後の呼び出しgrepを一回だけ実行し、最終検証後に同じPRを更新する。Issueのクローズ確認はPRマージ後に行う。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T2626 | T2625の初回CI実測時間、M08のシナリオ秒数、timeout根拠をdocsと検証記録へ反映する。job名とstep名は変更しない。Compose削除前に完了する。 | `docs/ローカル実行とCI.md`、`.github/workflows/e2e-test.yml`、`specs/S26-migrate-e2e-to-taskdef/verification/phase-4-results.md` | FR-2611、NFR-2604、NFR-2605 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、実測値と根拠が記録される。 | メイン | — |
| T2630 | 全フェーズの検証記録、品質ゲート、CI、現行文書の完了を確認してから`docker-compose.yml`を削除する。 | `docker-compose.yml` | FR-2612、NFR-2601、NFR-2606 | なし | `git diff -- docker-compose.yml`が削除を示し、`git status --short`が想定した削除だけを含む。 | メイン | — |
| T2631 | 現行コード、現行文書、CI、設定だけを対象にCompose呼び出しを一回grepし、除外理由と終了コードを記録する。 | `specs/S26-migrate-e2e-to-taskdef/verification/compose-grep.txt` | FR-2613、NFR-2605、NFR-2606 | なし | `git grep -nE`の呼び出し結果が0件で、対象範囲、除外一覧、日時を記録する。 | メイン | — |
| T2632 | 削除後のquality gate、sh構文、M09 unit、Markdown lint、CI静的検査、git statusを実行してフェーズ5結果を保存する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-5-results.md` | FR-2609、FR-2612、FR-2613、NFR-2601、NFR-2605、NFR-2606 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、結果ファイルが保存される。 | メイン | — |
| T2633 | フェーズ5完了後、evidence-code-reviewを変更差分と関連実装へ適用し、Critical・High・Mediumの指摘を0件にする。 | 変更対象と関連実装 | FR-2601〜2614、NFR-2601〜2606 | なし | `evidence-code-review`の結果、重大度Critical・High・Mediumの未対応指摘がないことを記録する。 | メイン | — |
| T2634 | T2633の完了後、security-reviewを同じ差分と関連するCI・ネットワーク・入力境界へ適用し、重大指摘を解消する。 | 変更対象、CI、ネットワーク、文書 | FR-2604〜2613、NFR-2601〜2606 | なし | `security-review`の結果、重大度Critical・High・Mediumの未対応指摘がないことを記録する。 | メイン | — |
| T2635 | 必須レビューの修正を反映した後、最終品質ゲートを1回だけ実行する。結果を最終検証記録へ追記する。 | `specs/S26-migrate-e2e-to-taskdef/verification/phase-5-results.md` | FR-2609、FR-2612、FR-2613、NFR-2601、NFR-2605、NFR-2606 | なし | `sh scripts/quality-gate.sh`が終了コード0で、レビュー結果と最終実行結果が記録される。 | メイン | — |
| T2636 | CI/CDを変更したため、任意の`aws-well-architected-review-lite`を実行するか利用者に確認し、実行しない場合も判断を記録する。 | 変更対象とレビュー記録 | NFR-2604、NFR-2605 | なし | 利用者の判断が記録され、実行する場合はレビュー結果が保存される。 | 利用者 | — |
| T2637 | 必須レビューと最終品質ゲートの完了後、利用者の指示を待ってフェーズ5のコミットを作る。pushは行わない。 | 変更対象全体 | NFR-2606 | なし | `git diff --check`が終了コード0で、利用者がフェーズ5だけを含む5つ目のコミットを作成する。 | 利用者 | — |
| T2638 | 5コミットの内容と最終検証を確認した後、利用者の端末でfeatureブランチをpushし、既存PRを更新する。 | Git履歴、PR | FR-2611〜2613、NFR-2604〜2606 | なし | `git push origin feature/s26-migrate-e2e-to-taskdef`が成功し、更新後のPRでrequired checksが開始される。 | 利用者 | — |
| T2627 | PRのマージ後、利用者の指示を受けてIssue #26と#27のクローズ条件を確認し、#21へM08 TERM再発の有無と検証記録を結果として記録する。 | Issue #21、#26、#27 | FR-2614、NFR-2605 | なし | `gh issue view 26 --json state`と`gh issue view 27 --json state`がCLOSEDを返し、#21に実測結果の記録が残る。 | 利用者 | — |

## FR/NFRカバレッジ

| 要件 | 対応タスク |
| --- | --- |
| FR-2601 | T2603、T2607〜T2610、T2614〜T2616、T2620 |
| FR-2602 | T2611、T2617、T2624、T2626 |
| FR-2603 | T2602、T2603、T2607〜T2610、T2614〜T2616 |
| FR-2604 | T2603、T2604、T2607、T2610、T2615、T2620 |
| FR-2605 | T2603、T2610、T2615、T2617、T2621 |
| FR-2606 | T2601、T2604、T2611、T2617 |
| FR-2607 | T2616、T2622、T2625、T2626 |
| FR-2608 | T2620、T2628 |
| FR-2609 | T2603、T2621、T2622、T2632、T2635 |
| FR-2610 | T2620、T2621 |
| FR-2611 | T2622〜T2629、T2623a、T2638 |
| FR-2612 | T2630、T2632、T2635 |
| FR-2613 | T2631、T2632、T2635 |
| FR-2614 | T2602、T2607、T2609、T2610、T2614〜T2618、T2627 |
| NFR-2601 | T2603、T2605、T2607〜T2610、T2614〜T2616、T2620〜T2624、T2630〜T2635 |
| NFR-2602 | T2601、T2604、T2611、T2617、T2621 |
| NFR-2603 | T2602、T2604、T2607〜T2611、T2614〜T2617、T2620、T2622、T2624、T2625 |
| NFR-2604 | T2616、T2617、T2622、T2624〜T2626、T2636、T2638 |
| NFR-2605 | T2605、T2611、T2617、T2620、T2624、T2626〜T2635 |
| NFR-2606 | T2603、T2605、T2606、T2612、T2613、T2618、T2619、T2623、T2623a、T2628、T2629、T2630、T2632〜T2638 |

## tasks.md索引

| フェーズ | tasks.mdの開始行 | tasks.mdの終了行 |
| --- | ---: | ---: |
| フェーズ1 | 12 | 25 |
| フェーズ2 | 26 | 40 |
| フェーズ3 | 41 | 54 |
| フェーズ4 | 55 | 71 |
| フェーズ5 | 72 | 91 |
| FR/NFRカバレッジ | 92 | 116 |
| 索引 | 117 | 127 |
