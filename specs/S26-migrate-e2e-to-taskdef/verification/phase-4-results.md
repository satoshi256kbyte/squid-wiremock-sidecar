# S26 フェーズ4 検証結果

フェーズ4（S14、品質ゲート、CI、文書。T2620〜T2624、T2628）のローカルの結果を記録する。
実装はサブエージェント（Claude Haiku 5.5）、実機の検証、修正、品質ゲートはメインエージェントが行った。
実行環境はLinux aarch64のEC2（2026-11-07）である。AWSアカウント識別子、ARN、認証情報は記録しない。
CIの初回実行とcontract（T2625）、CIの実測値の反映（T2626）は、このファイルの対象外である。

## 1. 変更範囲

| ファイル | 変更 |
| --- | --- |
| `tests/s14-taskdef-contract.sh`（新規） | S14の契約をDockerを使わずに検査する。`s14_acl_lines`、`s14_derived_config_parse`、`s14_mapping_readonly`、`s14_squid_not_published`の4件 |
| `scripts/quality-gate.sh` | `docker-compose config`と`docker-compose ps`の残存検査を削除する。残存検査を`swsc_check_managed_empty`へ置き換える。M02をゲートで実行する。S14の契約検査を追加する。旧S14（`tests/s14-compose-port-binding.sh`）はゲートから外す |
| `.github/workflows/e2e-test.yml` | `test-ci` stepで、`npm run test:ci`の後にM08の4シナリオを実行する。job名、step名、timeoutは変えない |
| `scripts/e2e-lib.sh` | `test:ci`の名前指定で、子を起動した直後に届いた信号でも子を止める（下の2章） |
| `tests/m09-execution-and-ci.sh` | Compose向けの検査を新しい前提へ直す。品質ゲート、CI、S14連携のunitを追加する |
| `README.md`、`AGENTS.md`、`docs/`の現行文書6件 | 新基盤の入口、ロック、Squid非公開、品質ゲート、cleanupへ更新する |

`package.json`は変更していない（T2623a）。M09のunitが、npmの入口を`sh scripts/e2e.sh <操作>`の形に固定しているためである。
旧S14の`tests/s14-compose-port-binding.sh`は残した。削除はフェーズ5で判断する。

## 2. 実装中に直した点

| 問題 | 対応 |
| --- | --- |
| `test:ci`の名前指定で、`&`の直後から子のPIDを記録するまでの間に信号が届くと、子が止まらない。M09のunitで1回だけ起きた（フェーズ3の再レビューで「判定不能」とした時間窓） | 子を作る前に印を立て、trapは印があれば`$!`を使う。子の終了後は印を下ろし、回収済みのPIDを使わない。M09のunitを10回続けて実行し、全て通過した |
| S14の契約検査が、契約の入力（`scripts/e2e-runner.sh`、`scripts/e2e-taskdef.py`、`ecs/`）だけの変更では実行されない（`evidence-code-review`のSHOULD） | S14の契約検査を独立したブロックへ移し、`scripts/e2e`と`ecs/`の変更でも1回だけ実行する。条件は変数に置き、M09のブロックを探すunitと区別する |
| 文書の更新で、M09の文書検査が3件落ちた | 文書の「CI の初回実行で実測する」と「移行完了後に削除」の文言を戻す。READMEのSquidの行は、新しい記述（pauseのnamespaceの中、ホストへは公開しない）が正しいため、M09の検査を新しい行へ合わせる |

## 3. 計画との差

| 項目 | 計画（plan.md 6章） | 実装 | 理由 |
| --- | --- | --- | --- |
| M08の4シナリオの置き場 | `npm run test:ci`の検査列へ直列で追加する | CIの`test-ci` stepで、`npm run test:ci`の後に`sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000`を実行する | `npm run test:ci`の値を変えると、M09の契約（npmの入口は`sh scripts/e2e.sh <操作>`）が壊れる。ローカルでは同じ1行で同じ検査ができ、文書にそう書いた。required status check名は変わらない |

## 4. 実行結果

| 層 | 内容 | 結果 |
| --- | --- | --- |
| 構文 | `sh -n`（変更・追加した全shファイル） | 通過 |
| Compose呼び出し | `grep -n 'docker-compose\|docker compose'`（`scripts/quality-gate.sh`、CI定義、`tests/s14-taskdef-contract.sh`） | 0件 |
| unit | S14契約、M09 | 4件、223件。全て通過。M09は10回続けて通過 |
| Markdown検査 | `npm run -s lint:md` | 指摘0件 |
| 品質ゲート | `sh scripts/quality-gate.sh` | 通過（446秒）。M02〜M08のsmoke、S14契約、M09のunitとsmokeを含む |
| 後始末 | `swsc.managed=true`のコンテナ、ロック、`.e2e/`、`e2e-logs/` | 残っていない |

品質ゲートが`docker-compose`の無い環境で通過したのは、このフェーズが初めてである。

## 5. 残っているCompose の記述

| 場所 | 理由 |
| --- | --- |
| `README.md`の「旧 Compose 手順」 | 移行完了後に、`docker-compose.yml`の削除（T2630）と同時に削除する |
| `docs/ローカル実行とCI.md`の旧基盤の注記 | 現行の手順ではないことを示す |
| `docs/ローカル実行とCI.md`のunitの説明 | 偽の`docker-compose`をPATHに置いて、呼ばれないことを確かめる仕組みの説明 |
| `docs/E2Eテスト.md`のCompose時代の所要時間 | 履歴として、その旨を明記して残す |
| `docs/roadmap.md`、`docs/requirements.md`の履歴 | M01の履歴。過去の決定は書き換えない |
| `scripts/e2e-contract.sh`、`tests/m09-execution-and-ci.sh` | 旧基盤の可能性を示す診断文と、偽の`docker-compose`を使う検査 |
| `tests/s14-compose-port-binding.sh` | 旧S14。ゲートから外した。フェーズ5で扱う |

## 6. 次の作業へ渡す事項

| 事項 | 内容 |
| --- | --- |
| T2625（利用者） | フェーズ4のコミットの後、PRを作成し、Composeが残る状態で初回CIとcontractを実行する。`test-ci` stepの所要時間（M08の4シナリオ分の増分）を記録する |
| T2626 | CIの実測値を`docs/ローカル実行とCI.md`の「所要時間の目安」へ反映する。ローカルの参考値は、品質ゲート約445秒、M07 smoke約150秒、M08 smoke約70秒、`test:ci`の4シナリオ約26秒 |
| フェーズ5 | `docker-compose.yml`、READMEの旧手順、旧S14（`tests/s14-compose-port-binding.sh`）を削除し、一回限りのgrepを行う |

## 7. コミット前の必須レビューと最終の品質ゲート（2026-11-07）

スキルごとに独立したサブエージェント（Claude Sonnet 5.5、effort medium）で、直列に実行した。

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Critical・High・Mediumなし。SHOULD 1件 | 対応した（2章、S14の契約検査の実行条件） |
| `security-review`（対応後の差分） | Critical・High・Mediumなし。Low 1件、要確認1件 | Lowは対応しない。共有ホストでは`SWSC_LOCK_DIR`を利用者専用にする、という文書の追記で、任意である。要確認は下の表 |

レビュー後の最終の品質ゲートは通過した（448秒）。M02〜M08のsmoke、S14の契約検査、M09のunitとsmokeを含む。
後始末の後、`swsc.managed=true`のコンテナ、ロック、`.e2e/`、`e2e-logs/`は残っていない。

T2625（初回CI）で確かめること:

| 確認 | 内容 |
| --- | --- |
| `test-ci` stepの時間 | `npm run test:ci`とM08の4シナリオの合計が、10分以内に収まること |
| 失敗時のアーティファクト | `e2e-logs/`に、アカウントIDやARNが出ていないこと（`security-review`の要確認） |
| 実AWS | 不要。CIのダミー認証情報の範囲に収まる |

## 8. 初回CIの失敗と修正（2026-11-07、PR #29）

| 項目 | 内容 |
| --- | --- |
| 結果 | `e2e`の`unit` stepが最初の検査で失敗した。後続のstepは実行されず、`test-ci`の所要時間は測れていない |
| ログ | `find: '/tmp/tmp.X/swsc-lock-case.Y': No such file or directory`の2行と終了コード1 |
| 原因 | M09のunitで、全体用のロック置き場（`UNIT_LOCK_BASE`）の既定が`$TMP`の中だった。`check()`が検査ごとに`$TMP`の中身を消すため置き場も消え、続く`find`が失敗して`set -e`で止まった。手元は`KIROCREW_SCRATCH`があり、置き場が`$TMP`の外にできるため隠れていた（フェーズ1から） |
| 修正 | `lock_case_dir`の既定を`${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}`にする |
| 確認 | 直す前の版は、`KIROCREW_SCRATCH`と`TMPDIR`を外したCIと同じ条件で同じエラーになった。直した版は同じ条件で223件全て通過し、`/tmp/swsc-lock-case.*`は残らなかった |
| レビュー | `evidence-code-review`はCritical・High・Mediumなし、Low 1件（検査が途中で失敗すると、空の置き場が`/tmp`に1件残る。CIのランナーは使い捨てで、手元はscratchに置くため対応しない）。`security-review`は指摘0件 |

## 9. 初回CIの実測（T2625、T2626）

修正後のCI（PR #29、`ed048e3`、`ubuntu-24.04`）は成功した。PRの状態は`CLEAN`である。

| ステップ | 結果 | 所要時間 | 上限 |
| --- | --- | --- | --- |
| `unit` | 223件通過 | 29秒 | 3分 |
| `test-ci` | `npm run test:ci`とM08の4シナリオがPASS | 57秒 | 10分 |
| `smoke` | 通過 | 85秒 | 8分 |
| `contract` | 6件通過 | 37秒 | 5分 |
| ジョブ全体 | 成功 | 212秒 | 15分 |

M08の4シナリオのシナリオ部分は9秒（`normal` 1秒、`error-500-then-200` 1秒、`ratelimit-429` 6秒、`slow-5000` 1秒）だった。
`test-ci`はM09の初回（37秒）から約20秒増えた。どの上限も実測の4倍以上の余裕があるため、上限は変えていない。
実測値と上限の根拠は、`docs/ローカル実行とCI.md`の「所要時間の目安」へ反映した。CI定義は、`smoke`と`contract`の「仮置き」のコメントだけを直した。job名とstep名は変えていない。

contractはCIで通過したため、T2625の確認はCIの結果で足りるとした。
失敗時のアーティファクトは、成功のため作られていない。識別情報が出ないことの実物での確認は、未実施である。

T2626のコミット前の必須レビュー:

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Critical・High・Mediumなし。SHOULD 1件、BETTER 1件（上限の根拠の書き方） | 対応した。`unit`は偽の`docker`で検査し、起動の待ち上限に依存しないと書く。`test-ci`と`smoke`は、起動ごとにWireMockの待ちとSquidのhealthy待ちがあると書く |
| `security-review` | 指摘0件 | なし |
