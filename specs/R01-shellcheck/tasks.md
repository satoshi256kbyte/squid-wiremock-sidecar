# R01 実装タスク

## 進め方

`spec.md`、`clarify.md`、`plan.md`の決定を実装する。実装サブエージェントへの1回の依頼は3〜4タスクまでとし、
各依頼で触る`.sh`は数ファイルに収める。同じ対象ファイルを持つタスクは同時に実行せず、
表のバッチ内順序に従って直列化する。依頼には作業ディレクトリ、対象タスク番号、読む行範囲、
5分以内に最初のファイル変更がなければ再試行せず止まったツールを報告して終了する条件を書く。
Dockerを使うsmoke、品質ゲート、レビューはメインが実行し、実装サブエージェントには実行させない。

フェーズは`plan.md` 6章の5コミット（`clarify.md`のQ-R0111）に対応する。PRは1つとし、
フェーズごとに品質ゲートを通してから次へ進む。コミットは利用者の指示後にフェーズごとに1つ作る。
pushとPR作成は利用者の端末で実行する。AGENTS.mdの「コミット前の必須レビュー」に従い、
各フェーズのコミット前に`evidence-code-review`と`security-review`を差分へ適用する。

指摘の解消は、先に`# shellcheck source=`を入れ、指摘を取り直してから、コード別に直す（`plan.md` 4.1）。
安全に関わる指摘（SC2086、SC2046、SC2016、SC2012）で、判定・終了コード・出力を変えずに直せず、
値の出どころも示せない行は、除外も修正もせず一覧にして利用者の判断に上げる（`plan.md` 4.5）。
一覧は`specs/R01-shellcheck/verification/`に置く。

一般的なツール（shellcheck、mise）を使い、自前のチェック用シェルは作らない（NFR-R0101）。
検証で作った一時ファイル、miseのデータ置き場に使った一時ディレクトリ、worktreeは、各フェーズの記録タスクで削除し、
`git status --short`で残っていないことを確かめる。一時ファイルを作る確認は`plan.md` 8.1節の手順に従う。
実行時間は、ローカルの実測が約74秒（m09が52.6秒、残り19ファイルが21.8秒。`plan.md` 10節）であり、
2分では余裕が小さいため、CIの`shellcheck`stepの上限は最初から3分にする（利用者の判断、2026-11-07）。
初回CIの実測は、フェーズ4の末尾で取得し、フェーズ5で上限を見直す。

`analyze.md`の指摘への対応で、T-R0150〜T-R0155を追加した。番号は既存のタスクを振り直さないため末尾から振り、
実行の順序は各表の行の順とする。smokeとunitは、決定の反映（T-R0151、T-R0152）の後に実行する。

## フェーズ1 版の宣言（コミット1）

対象範囲は`plan.md` 2〜2.1節、6章コミット1、9章である。この時点の品質ゲートは`sh -n`のままである。
`mise.lock`は4つの環境のSHA256を公式の情報源と照合して記録する。照合の事実は
`$KIROCREW_SCRATCH/r01-plan-facts.md`にあり、スクラッチがセッションの終了で消える前に、T-R0103でメインが記録へ写す。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0101 | `mise.toml`に`min_version = "2026.11.3"`と`[tools]`の`shellcheck = "0.11.0"`だけを書く。`.shellcheckrc`に`shell=sh`、`severity=style`、`external-sources=true`、`source-path=SCRIPTDIR`の4行だけを書く。`[tasks]`、`[hooks]`、`[env]`、`[plugins]`、`disable=`は書かない。 | `mise.toml`、`.shellcheckrc` | FR-R0101、FR-R0108、FR-R0110、NFR-R0109 | なし（静的検査`t_shellcheck_config_and_mise_toml_are_restricted`はT-R0131で追加する） | `git diff --check`が終了コード0で、2ファイルが`plan.md` 2.1節の内容と一致する。 | 実装サブエージェント | A |
| T-R0102 | `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`で`mise.lock`を新規に作る。`mise trust`は内容を確かめる前に実行しない。 | `mise.lock` | FR-R0101、FR-R0115、NFR-R0102、NFR-R0110 | なし | `mise.lock`が4つの環境のURLとSHA256を持ち、差分がshellcheckの公式URLとSHA256だけである。 | メイン | — |
| T-R0103 | `mise.lock`の4つの環境のURLが公式のGitHubリリースの資産であり、SHA256が公式の配布物（GitHub APIの`digest`）と一致することを、`r01-plan-facts.md`の照合結果から検証記録へ写す。mise本体の検証方法（CIは`sha256`とminisign、ローカルは`SHASUMS256.txt`）も記録する。 | `specs/R01-shellcheck/verification/phase-1-results.md` | NFR-R0102、NFR-R0110 | なし | 4環境ぶんのURLとSHA256、照合元、mise本体の検証方法が記録に残り、`mise.lock`の値と一致する。 | メイン | — |
| T-R0104 | `mise install --locked`と`mise current shellcheck`（`0.11.0`）を確認する。失敗側として、lockに無い版（`is not in the lockfile`）とチェックサムの不一致（`Checksum mismatch`）を、リポジトリ外の複製で確認する。リポジトリの`mise.toml`と`mise.lock`は書き換えない。複製と`MISE_DATA_DIR`に使った一時ディレクトリは、記録の後に絶対パスを指定して削除する。 | `specs/R01-shellcheck/verification/phase-1-results.md` | FR-R0101、FR-R0102、NFR-R0102、NFR-R0103、NFR-R0108 | なし | 導入が成功し、2つの失敗が終了コード1で再現し、結果が記録される。一時ディレクトリを削除したことと、削除したパスの種類が記録に残る。 | メイン | — |
| T-R0150 | FR-R0102の改訂（`mise exec`を使わず、`mise which shellcheck`の実体を実行し、期待する版は`mise current shellcheck`で得る）が、`spec.md`のFR-R0102、`clarify.md`のQ-R0110（結論欄を含む）、`plan.md` 1.1節・3節・11章で一致していることを`grep`で確かめる。未導入の`mise exec`がPATH上の別のshellcheckで成功する事実（`r01-plan-facts.md`）が理由として書かれていることも確かめ、結果を記録する。 | `specs/R01-shellcheck/verification/phase-1-results.md` | FR-R0102 | なし | 4つの文書で実行方法の記述が一致し、`mise exec -- shellcheck`を実行方法とする記述が残っていない。結果が記録される。 | メイン | — |
| T-R0105 | フェーズ1の差分に`evidence-code-review`と`security-review`を適用する。`mise.toml`の内容制限、`mise.lock`の差分、`.shellcheckrc`にコード単位の無効化がないことを確かめる。 | 変更対象全体 | FR-R0108、FR-R0115、NFR-R0109、NFR-R0110 | なし | Critical・High・Mediumの未対応指摘がなく、レビューの確認範囲が記録される。 | メイン | — |
| T-R0106 | フェーズ1の品質ゲートを実行し、導入の実測、識別情報検査、未実行層、残した一時物を記録する。 | `specs/R01-shellcheck/verification/phase-1-results.md` | FR-R0101、FR-R0108、FR-R0110、NFR-R0102、NFR-R0106、NFR-R0108 | なし | `sh scripts/quality-gate.sh`と`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0107 | フェーズ1の差分と結果を確認した後、利用者の指示を待ってコミット1を作る。pushは行わない。 | 変更対象全体 | NFR-R0104 | なし | `git diff --check`が終了コード0で、利用者がフェーズ1だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ2 m09以外の44件の解消（コミット2）

対象範囲は`plan.md` 4.1〜4.3節である。19ファイルの44件を、ファイルごとに0件にする。
各ファイルの修正の前後で、そのファイルだけに`shellcheck`を実行して0件を確かめる。
実行は`mise which shellcheck`で得たmise管理の実体で行う。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0108 | `test-client/entrypoint.sh`のSC1091は、最終の`.shellcheckrc`では出ない（件数の基準は`plan.md` 4.6節）。`# shellcheck source=retry-lib.sh`の宣言が`.shellcheckrc`と合わせて意図どおりかを確認する（宣言は残してよい）。`scripts/e2e.sh`と`tests/m02-routing-smoke.sh`のSC2034を、参照元を確かめて削除または理由付きの個別除外にする。 | `test-client/entrypoint.sh`、`scripts/e2e.sh`、`tests/m02-routing-smoke.sh` | FR-R0107、FR-R0109、FR-R0111 | なし | 3ファイルの`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-1 |
| T-R0109 | `tests/m03-wiremock-scenarios.sh`、`tests/m04-test-client.sh`、`tests/m05-proxy-integration.sh`のSC2034（`SWSC_ROOT`）を、理由付きの個別除外にする。 | `tests/m03-wiremock-scenarios.sh`、`tests/m04-test-client.sh`、`tests/m05-proxy-integration.sh` | FR-R0107、FR-R0111 | なし | 3ファイルの`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-1 |
| T-R0110 | `scripts/e2e-lib.sh`の7件（SC2034、SC2012、SC2154）を解消する。SC2012は`find`への修正か、検査が管理する入力である根拠付きの除外にする。SC2154はtrap内代入の誤検出として理由を書く。 | `scripts/e2e-lib.sh` | FR-R0107、FR-R0111 | なし | `scripts/e2e-lib.sh`の`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-1 |
| T-R0111 | `tests/s14-taskdef-contract.sh`の8件（SC2329の6関数、SC2016、SC1003）を解消する。関数の参照を`git grep`で確かめ、文字列で組み立てて呼ぶ関数は除外、参照が0件のものだけ削除する。 | `tests/s14-taskdef-contract.sh` | FR-R0107、FR-R0111 | なし | `tests/s14-taskdef-contract.sh`の`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-2 |
| T-R0112 | `tests/m06-client-resilience.sh`の4件（SC1090、SC2016、SC2086、SC2034）と、`tests/m07-scenario-isolation.sh`の3件（SC2043、SC2012、SC2034）を解消する。 | `tests/m06-client-resilience.sh`、`tests/m07-scenario-isolation.sh` | FR-R0107、FR-R0109、FR-R0111 | なし | 2ファイルの`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-2 |
| T-R0113 | `tests/m08-e2e-suite.sh`の16件（SC2031が6、SC2030が2、SC1090が3、SC2034、SC2016、SC2086、SC2043、SC2012が各1）を解消する。サブシェルを外す修正はしない。 | `tests/m08-e2e-suite.sh` | FR-R0107、FR-R0109、FR-R0111 | なし | `tests/m08-e2e-suite.sh`の`shellcheck -s sh -S style`の件数が0になる。 | 実装サブエージェント | B-2 |
| T-R0114 | SC2086、SC2046、SC2016、SC2012のうち、修正も根拠付きの除外もできなかった行を、ファイルと行番号、コード、周辺の要約、修正案と除外案、それぞれの影響として一覧にする。該当が無ければ「0件」と記録する。 | `specs/R01-shellcheck/verification/phase-2-decisions.md` | FR-R0111 | なし | 一覧が保存され、識別情報と利用者の絶対パスを含まない。 | メイン | — |
| T-R0115 | T-R0114の一覧について、修正か除外かを選ぶ。除外を選ぶ場合は理由を自分の言葉で書く。決定は`specs/R01-shellcheck/`の記録に残す。決定が出るまでコミット2を進めない。 | `specs/R01-shellcheck/verification/phase-2-decisions.md` | FR-R0111 | なし | 全行に決定が記録される。一覧が0件なら確認だけで終わる。 | 利用者 | — |
| T-R0151 | T-R0115の決定を、一覧の行だけを対象にコードへ反映する（修正、または利用者が書いた理由付きの個別除外）。一覧が0件なら省略し、省略したことを記録する。反映の後に、対象ファイルの`shellcheck -s sh -S style`が0件であることを確かめる。 | 一覧にある`.sh` | FR-R0107、FR-R0111 | なし | 一覧の全行が反映され、m09以外の19ファイルの件数が0になる。 | 実装サブエージェント | B-3 |
| T-R0116 | T-R0151の反映の後に、変更したファイルに対応するM02〜M08のsmoke（Docker使用）と`sh tests/m09-execution-and-ci.sh unit`を直列で実行し、結果が変わらないことを確かめる（AC-R0109、AC-R0108）。 | `specs/R01-shellcheck/verification/phase-2-results.md` | FR-R0111、NFR-R0104 | なし | 対象smokeとunitが終了コード0で、結果と所要時間が記録される。 | メイン | — |
| T-R0117 | フェーズ2の差分に`evidence-code-review`と`security-review`を適用する。`git grep -n 'shellcheck disable'`で全除外を列挙し、コードと理由の有無、SC2086・SC2046・SC2016・SC2012の根拠を1件ずつ確かめる（AC-R0107、AC-R0108）。ファイル全体に効く先頭の`# shellcheck disable=`は機械的に検出されないため、列挙した各行が対象行の直前にあり、ファイル先頭にないことを1件ずつ確かめる。 | 変更対象全体 | FR-R0107、FR-R0108、FR-R0111 | なし | Critical・High・Mediumの未対応指摘がなく、除外の一覧と確認範囲（ファイル全体の除外がないこと）が記録される。 | メイン | — |
| T-R0118 | フェーズ2の品質ゲートを実行し、19ファイルのshellcheckが0件であること、修正と除外のコード別件数（`plan.md` 4.6）、識別情報検査、残した一時物を記録する。 | `specs/R01-shellcheck/verification/phase-2-results.md` | FR-R0107、FR-R0111、NFR-R0104、NFR-R0106、NFR-R0108 | なし | `sh scripts/quality-gate.sh`と`git diff --check`が終了コード0で、m09以外の19ファイルが0件である。 | メイン | — |
| T-R0119 | フェーズ2の差分と結果を確認した後、利用者の指示を待ってコミット2を作る。pushは行わない。 | 変更対象全体 | NFR-R0104 | なし | `git diff --check`が終了コード0で、利用者がフェーズ2だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ3 m09の112件の解消（コミット3）

対象範囲は`plan.md` 4.4節である。対象は`tests/m09-execution-and-ci.sh`の1ファイルで、
同じファイルを触るため、バッチ内は表の順に直列で実行する。コード別に分け、行番号が変わるため、
各タスクの開始時に指摘を取り直す。ゲートとワークフローの行を引用した文字列を含む行は変更しない。
コメントの追加と最小の修正だけを行う。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0120 | SC1090の23件を解消する。読み込み先が決まる行は`# shellcheck source=`、一時ファイルを読む行は`source=/dev/null`と理由を書く。完了後に指摘を取り直す。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0109、FR-R0111 | なし | SC1090の件数が0になり、`sh tests/m09-execution-and-ci.sh unit`が終了コード0になる。 | 実装サブエージェント | C-1 |
| T-R0121 | SC2031の20件とSC2030の18件を解消する。サブシェルによる隔離が意図の行は理由付きで個別に除外し、サブシェルを外す修正はしない。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0111 | なし | SC2030とSC2031の件数が0になり、`sh tests/m09-execution-and-ci.sh unit`が終了コード0になる。 | 実装サブエージェント | C-1 |
| T-R0122 | 取り直した一覧のSC2016のうち、行番号の小さい順に20件を解消する。偽のコマンド本文、子のshellの文字列、入力値の意図を1件ずつ確かめ、理由を書く。迷う行は修正に回し、できなければ一覧に残す。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0111 | なし | 対象20件が除外または修正され、一覧に残す行が記録され、unitが終了コード0になる。 | 実装サブエージェント | C-1 |
| T-R0123 | 残りのSC2016（19件）を同じ基準で解消する。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0111 | なし | SC2016の残りが0件（一覧に残す行を除く）で、unitが終了コード0になる。 | 実装サブエージェント | C-2 |
| T-R0124 | SC2329の9件（`git grep`と文字列としての参照を確かめ、参照があれば除外、0件なら削除）、SC2012の1件（行700、検査が管理する入力の根拠）、SC2015の1件（意図どおりの`&&`と`\|\|`）、SC2086の1件（行289の`$_list`の出どころ）を解消する。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0111 | なし | 4つのコードの件数が0（一覧に残す行を除く）で、unitが終了コード0になる。 | 実装サブエージェント | C-2 |
| T-R0125 | m09で修正も根拠付きの除外もできなかったSC2086、SC2046、SC2016、SC2012の行を、フェーズ2と同じ形式で一覧にする。該当が無ければ「0件」と記録する。 | `specs/R01-shellcheck/verification/phase-3-decisions.md` | FR-R0111 | なし | 一覧が保存され、識別情報と利用者の絶対パスを含まない。 | メイン | — |
| T-R0126 | T-R0125の一覧について、修正か除外かを選ぶ。除外を選ぶ場合は理由を自分の言葉で書く。決定が出るまでコミット3を進めない。 | `specs/R01-shellcheck/verification/phase-3-decisions.md` | FR-R0111 | なし | 全行に決定が記録される。一覧が0件なら確認だけで終わる。 | 利用者 | — |
| T-R0152 | T-R0126の決定を、一覧の行だけを対象にコードへ反映する（修正、または利用者が書いた理由付きの個別除外）。一覧が0件なら省略し、省略したことを記録する。反映の後に、`tests/m09-execution-and-ci.sh`の`shellcheck -s sh -S style`が0件であることと、`sh tests/m09-execution-and-ci.sh unit`を確かめる。 | `tests/m09-execution-and-ci.sh` | FR-R0107、FR-R0111 | なし | 一覧の全行が反映され、m09の件数が0になり、unitが終了コード0になる。 | 実装サブエージェント | C-3 |
| T-R0127 | T-R0152の反映の後に、20ファイルすべての`shellcheck -s sh -S style`が0件であること、`sh tests/m09-execution-and-ci.sh unit`、`smoke`（Docker使用）が終了コード0であることを確かめ、結果を記録する。 | `specs/R01-shellcheck/verification/phase-3-results.md` | FR-R0107、FR-R0111、NFR-R0104 | なし | 20ファイルが0件で、unitとsmokeが終了コード0になる。 | メイン | — |
| T-R0128 | フェーズ3の差分に`evidence-code-review`と`security-review`を適用する。除外の全件列挙、コードと理由の有無、4つの安全に関わるコードの根拠、判定・終了コード・出力が変わっていないことを1件ずつ確かめる（AC-R0107、AC-R0108）。 | 変更対象全体 | FR-R0107、FR-R0108、FR-R0111 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0129 | フェーズ3の品質ゲートを実行し、全体の修正と除外のコード別件数（`plan.md` 4.6）、識別情報検査、残した一時物を記録する。 | `specs/R01-shellcheck/verification/phase-3-results.md` | FR-R0107、FR-R0111、NFR-R0104、NFR-R0106、NFR-R0108 | なし | `sh scripts/quality-gate.sh`と`git diff --check`が終了コード0で、結果ファイルが保存される。 | メイン | — |
| T-R0130 | フェーズ3の差分と結果を確認した後、利用者の指示を待ってコミット3を作る。pushは行わない。 | 変更対象全体 | NFR-R0104 | なし | `git diff --check`が終了コード0で、利用者がフェーズ3だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ4 品質ゲートの置き換えとCI（コミット4）

対象範囲は`plan.md` 3、5、7、8章である。先にM09 unitを新しい期待へ更新して赤にし、
品質ゲートとワークフローの変更で緑にする。M09 unitにDocker、AWS CLI、miseの実行を入れない。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0131 | 新しい検査2件を追加し、壊れる4件の期待とタイムアウト・`run:`の検査を新しい形へ更新する。判定は弱めない。名前を`..._shellcheck3_unit3_...`へ改め、`shellcheck`の`timeout-minutes`が3であることを確かめる。`t_wf_each_step_runs_its_command`の更新には、`shellcheck`stepの`run:`が`mise which shellcheck`と自動の導入を止める2つの環境変数を持つ確認と、mise-actionのstepの`install_args`が`--locked`を持つ確認を加える。 | `tests/m09-execution-and-ci.sh` | FR-R0103、FR-R0106、FR-R0108、FR-R0114、NFR-R0101、NFR-R0109 | 追加: `t_gate_runs_shellcheck_with_pinned_options`、`t_shellcheck_config_and_mise_toml_are_restricted`。更新: `t_wf_uses_only_checkout_and_upload_artifact`、`t_wf_steps_run_in_plan_order`、`t_ci_test_ci_scenarios`、`t_wf_yaml_parses_with_expected_shape`、`t_wf_step_timeouts_are_unit3_test_ci10_smoke8_contract5`、`t_wf_each_step_runs_its_command` | `sh tests/m09-execution-and-ci.sh unit`が、ゲートとワークフローが未変更のため上記ケースで失敗する（赤）。 追加・更新した行を含め、`shellcheck -s sh -S style tests/m09-execution-and-ci.sh`の指摘が0件のままである（SC2016を避ける書き方にする。除外を入れた場合は、AC-R0107のレビューの対象に含める）。 | 実装サブエージェント | D |
| T-R0132 | `sh -n`のループを、`plan.md` 3節の処理（`command -v mise`、`mise current`、`mise which`、版比較、`git ls-files -z`の一時ファイル、`xargs -0`、`trap`）に置き換える。3つの環境変数を明示し、`\|\| true`を使わない。失敗メッセージに導入手順を含める。品質ゲートは`set -eu`で動くため、`mise current`と`mise which`の取得は`if !`などで受け、導入手順つきの`FAILED:`を出してから`status=1`にする（`var=$(...)`で直接受けない。`plan.md` 3節）。 | `scripts/quality-gate.sh` | FR-R0102、FR-R0103、FR-R0104、FR-R0105、FR-R0106、FR-R0110、NFR-R0101 | `t_gate_runs_shellcheck_with_pinned_options`が緑になる | `sh scripts/quality-gate.sh`が終了コード0で、`sh -n`のループと`mise exec`が残らない。 | 実装サブエージェント | D |
| T-R0133 | `unit`の前に、`jdx/mise-action`（コミットSHA固定、`with:`に`version`、`sha256`、`cache: false`、`env: false`、`install_args: --locked shellcheck`）と、`timeout-minutes: 3`の`shellcheck`stepを追加する。`${{`は使わず、`env:`のキーは増やさない。`shellcheck`stepの`run:`は、自動の導入を止める2つの環境変数を`$(...)`の中の`mise which shellcheck`にだけ付ける（`plan.md` 5.2節）。mise-actionのstepに`timeout-minutes`は付けない。job名`e2e`、`permissions`、`persist-credentials: false`は変えない。 | `.github/workflows/e2e-test.yml` | FR-R0114、FR-R0115、NFR-R0101、NFR-R0110 | `t_wf_uses_only_checkout_and_upload_artifact`、`t_wf_steps_run_in_plan_order`、`t_ci_test_ci_scenarios`、`t_wf_yaml_parses_with_expected_shape`、`t_wf_each_step_runs_its_command`が緑になる | `sh tests/m09-execution-and-ci.sh unit`が終了コード0になり、`run:`に式（`${{`）が入らず、`env:`の行が増えず、`install_args`が`--locked`を持つ。 | 実装サブエージェント | D |
| T-R0134 | `plan.md` 8.1節の手順で、意図的な構文エラー（`if`の閉じ忘れ、クォートの閉じ忘れ、`fi`の過不足）を持つ一時ファイルで品質ゲートが失敗することを確かめる。次に、mise無し、shellcheck未導入（空の一時データ置き場）、版違いで失敗と導入手順の表示を確かめる。一時ファイルは`git reset -- <パス>`と削除で片付ける。各状態で、`set -eu`で止まらず、導入手順つきの`FAILED:`が表示されることを確認項目にする。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0102、FR-R0105、FR-R0112、NFR-R0108 | なし | 各状態で終了コードが非0になり、PATH上の別のshellcheckでは通らず、`git status --short`に一時ファイルが残らない。 | メイン | — |
| T-R0154 | AC-R0104のために、構文エラー以外の指摘（未クォートの変数など、構文は正しく`-S style`が報告する内容）を含む一時ファイルで、品質ゲートが非0で失敗することを`plan.md` 8.1節の手順（`git add -N`、`git reset -- <パス>`、絶対パスでの削除）で確かめる。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0103、FR-R0106、NFR-R0108 | なし | 終了コードが非0で、shellcheckの指摘が表示され、`git status --short`に一時ファイルが残らない。 | メイン | — |
| T-R0135 | M09 unitとsmoke、`sh scripts/quality-gate.sh`、変更したファイルに対応するM02〜M08のsmokeを実行する。品質ゲートの実行時間を置き換えの前後で実測する。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0103、FR-R0104、FR-R0106、NFR-R0104、NFR-R0105 | なし | 各検査が終了コード0で、実行時間（目安約74秒）が記録される。 | メイン | — |
| T-R0136 | フェーズ4の差分に`evidence-code-review`と`security-review`を適用する。`mise-action`のSHA固定、`permissions`、`persist-credentials`、`cache`と`env`、自動信頼の限界（`plan.md` 5.4節）を確かめる。 | 変更対象全体 | FR-R0114、FR-R0115、NFR-R0109、NFR-R0110 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0137 | CI定義を変えたため、任意の`aws-well-architected-review-lite`を実行するかを判断する。実行しない場合も判断を記録する。 | `specs/R01-shellcheck/verification/phase-4-results.md` | NFR-R0105 | なし | 判断が記録され、実行する場合はレビュー結果が保存される。 | 利用者 | — |
| T-R0138 | macOS（Colima利用）とLinuxの端末で`mise install --locked`と`mise current shellcheck`を実行し、版と`shellcheck --version`の一致、アーキテクチャを記録する。未実施のまま完了としない。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0101、NFR-R0102、NFR-R0103 | なし | 両環境で版が`mise.toml`と一致し、結果が記録に残る。 | 利用者 | — |
| T-R0153 | 初回CIの前に、`jdx/mise-action`のコミットSHA`b44d12e7d0d8ee7461bb893e1b1993500433185b`のソースで、`install_args: --locked shellcheck`が受理されること（`--locked`が重複して足されないこと）を確かめる。確認したファイルと該当箇所を記録する。受理されない場合は、T-R0133の書き方を改めて利用者に諮る。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0115、NFR-R0110 | なし | `install_args`の扱いが記録され、T-R0141（初回CI）より前に完了している。 | メイン | — |
| T-R0139 | フェーズ4の品質ゲートを実行し、結果、識別情報検査、未実行層、残した一時物を記録する。 | `specs/R01-shellcheck/verification/phase-4-results.md` | FR-R0103〜FR-R0106、FR-R0112、FR-R0114、NFR-R0104、NFR-R0106、NFR-R0108 | なし | `sh scripts/quality-gate.sh`と`git diff --check`が終了コード0で、結果ファイルが保存される。 | メイン | — |
| T-R0140 | フェーズ4の差分と結果を確認した後、利用者の指示を待ってコミット4を作る。pushは行わない。 | 変更対象全体 | NFR-R0104 | なし | `git diff --check`が終了コード0で、利用者がフェーズ4だけを含むコミットを作成する。 | 利用者 | — |
| T-R0141 | 利用者の端末でfeatureブランチをpushし、PRを作成する。T-R0153の完了後に、初回CIで`shellcheck`stepが`unit`の前に実行され、job名`e2e`が変わらないことを確かめる。`shellcheck`stepの所要時間とjob全体の所要時間を、メインへ渡す。 | CI | FR-R0114、FR-R0115、NFR-R0103、NFR-R0105、NFR-R0110 | なし | required checksが成功し、stepごとの所要時間が記録される。 | 利用者 | — |

## フェーズ5 文書と上限の見直し（コミット5）

対象範囲は`plan.md` 2節の文書、9章、10章である。`docs/ローカル実行とCI.md`には、導入、版の固定、
`mise.lock`の更新手順、設定の自動信頼の限界、実行時間の実測を書く。
文書は日本語で書き、識別情報と利用者の絶対パスを含めない。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0142 | 品質ゲートの表の`sh -n`をshellcheckに改め、導入手順（`mise install --locked`）と未導入時の失敗を書く。shellcheckは変更範囲に関わらず毎回実行するため、文書だけの変更でもmiseが要ることを表と本文に書く。 | `AGENTS.md` | FR-R0113、NFR-R0107 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、表の内容がゲートの実装と一致する。 | 実装サブエージェント | E |
| T-R0143 | shellcheckの導入、版の固定、CIのstep、`mise.lock`の再生成手順（`plan.md` 9節）、設定の自動信頼の限界（5.4節）、修正と除外の件数（基準は設定なしの156件と最終設定の155件の別。`plan.md` 4.6節）、CIがubuntu-24.04（x86_64）だけを前提とし、`sha256`がlinux-x64の値であること（5.2節）を書く。実行時間の欄は実測の反映（T-R0145）まで空けて印を付ける。 | `docs/ローカル実行とCI.md` | FR-R0113、NFR-R0105、NFR-R0107、NFR-R0109、NFR-R0110 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント | E |
| T-R0144 | Prerequisitesにmiseとshellcheckを足す。M07、M08、S14が固定している行は変えない。 | `README.md` | FR-R0113、NFR-R0107 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、`sh tests/m09-execution-and-ci.sh unit`が通る。 | 実装サブエージェント | E |
| T-R0145 | T-R0141の初回CIの実測とローカルの約74秒を文書へ反映し、`shellcheck`stepの上限3分とmise-actionのstepの上限（現在は無し）を見直す。変更する場合は`.github/workflows/e2e-test.yml`と、タイムアウトを固定するM09 unitの期待を同時に更新する。job名とstep名は変えない。 | `docs/ローカル実行とCI.md`、`.github/workflows/e2e-test.yml`、`tests/m09-execution-and-ci.sh` | NFR-R0105、NFR-R0107 | 上限を変える場合: `t_wf_step_timeouts_are_shellcheck3_unit3_test_ci10_smoke8_contract5`（名前も更新） | 実測値と根拠が記録され、`sh tests/m09-execution-and-ci.sh unit`と`npm run -s lint:md`が終了コード0になる。 | メイン | — |
| T-R0146 | 5コミット全体の差分に`evidence-code-review`と`security-review`を適用し、Critical・High・Mediumを0件にする。要件適合、AWS・CIへの影響、品質ゲートの不足も確認する。 | 変更対象と関連実装 | FR-R0101〜FR-R0115、NFR-R0101〜NFR-R0110 | なし | 未対応のCritical・High・Mediumがなく、確認範囲が作業記録に残る。 | メイン | — |
| T-R0155 | 最終の差分で、M02〜M09のunitとsmoke（Dockerを使う）を直列で実行し、結果と所要時間を記録する。品質ゲートの実行時間の増加も記録する（AC-R0109）。 | `specs/R01-shellcheck/verification/phase-5-results.md` | NFR-R0104、NFR-R0105 | なし | M02〜M09のunitとsmokeが終了コード0で、実行時間が記録される。 | メイン | — |
| T-R0147 | 最終の品質ゲートを1回実行し、識別情報検査、結果を記録する。一時ファイル、一時データ置き場、worktreeを削除し、削除したものと残したものを記録する。 | `specs/R01-shellcheck/verification/phase-5-results.md` | FR-R0113、NFR-R0104、NFR-R0106、NFR-R0107、NFR-R0108 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外のファイルがない。 | メイン | — |
| T-R0148 | フェーズ5の差分と結果を確認した後、利用者の指示を待ってコミット5を作る。pushは行わない。 | 変更対象全体 | NFR-R0104 | なし | `git diff --check`が終了コード0で、利用者がフェーズ5だけを含むコミットを作成する。 | 利用者 | — |
| T-R0149 | 5コミットの内容を確認した後、利用者の端末でfeatureブランチをpushし、既存PRを更新する。更新後のCIで`shellcheck`stepと`e2e`のrequired checksが成功することを確かめる。 | Git履歴、PR | FR-R0114、FR-R0115、NFR-R0103 | なし | pushが成功し、更新後のPRでrequired checksが成功する。 | 利用者 | — |

## FR/NFRカバレッジ

| 要件 | 対応タスク |
| --- | --- |
| FR-R0101 | T-R0101〜T-R0104、T-R0138 |
| FR-R0102 | T-R0104、T-R0132、T-R0134、T-R0150 |
| FR-R0103 | T-R0131、T-R0132、T-R0135、T-R0139、T-R0154 |
| FR-R0104 | T-R0132、T-R0135、T-R0139 |
| FR-R0105 | T-R0132、T-R0134、T-R0139 |
| FR-R0106 | T-R0131、T-R0132、T-R0135、T-R0139、T-R0154 |
| FR-R0107 | T-R0108〜T-R0113、T-R0117、T-R0118、T-R0120〜T-R0124、T-R0127〜T-R0129、T-R0151、T-R0152 |
| FR-R0108 | T-R0101、T-R0105、T-R0117、T-R0128、T-R0131 |
| FR-R0109 | T-R0108、T-R0112、T-R0113、T-R0120 |
| FR-R0110 | T-R0101、T-R0132 |
| FR-R0111 | T-R0108〜T-R0118、T-R0120〜T-R0129、T-R0151、T-R0152 |
| FR-R0112 | T-R0134、T-R0139 |
| FR-R0113 | T-R0142〜T-R0144、T-R0147 |
| FR-R0114 | T-R0131、T-R0133、T-R0136、T-R0139、T-R0141、T-R0149 |
| FR-R0115 | T-R0102、T-R0105、T-R0133、T-R0136、T-R0141、T-R0149、T-R0153 |
| NFR-R0101 | T-R0131〜T-R0133 |
| NFR-R0102 | T-R0102〜T-R0104、T-R0106、T-R0138 |
| NFR-R0103 | T-R0104、T-R0138、T-R0141、T-R0149 |
| NFR-R0104 | T-R0107、T-R0116、T-R0118、T-R0119、T-R0127、T-R0129、T-R0130、T-R0135、T-R0139、T-R0140、T-R0147、T-R0148、T-R0155 |
| NFR-R0105 | T-R0135、T-R0137、T-R0141、T-R0143、T-R0145、T-R0155 |
| NFR-R0106 | T-R0106、T-R0118、T-R0129、T-R0139、T-R0147 |
| NFR-R0107 | T-R0142〜T-R0145、T-R0147 |
| NFR-R0108 | T-R0104、T-R0106、T-R0118、T-R0129、T-R0134、T-R0139、T-R0147、T-R0154 |
| NFR-R0109 | T-R0101、T-R0105、T-R0131、T-R0136、T-R0143 |
| NFR-R0110 | T-R0102、T-R0103、T-R0105、T-R0133、T-R0136、T-R0141、T-R0143、T-R0153 |

## ACカバレッジ

| AC | 対応タスク |
| --- | --- |
| AC-R0101 | T-R0104、T-R0138 |
| AC-R0102 | T-R0134、T-R0150 |
| AC-R0103 | T-R0133、T-R0141 |
| AC-R0104 | T-R0132、T-R0134、T-R0154 |
| AC-R0105 | T-R0134 |
| AC-R0106 | T-R0127、T-R0129、T-R0139 |
| AC-R0107 | T-R0117、T-R0128 |
| AC-R0108 | T-R0116、T-R0117、T-R0128 |
| AC-R0109 | T-R0116、T-R0127、T-R0135、T-R0141、T-R0145、T-R0155 |
| AC-R0110 | T-R0142〜T-R0144、T-R0147 |

## tasks.md索引

| フェーズ | tasks.mdの開始行 | tasks.mdの終了行 |
| --- | ---: | ---: |
| フェーズ1 | 31 | 46 |
| フェーズ2 | 48 | 68 |
| フェーズ3 | 70 | 90 |
| フェーズ4 | 92 | 111 |
| フェーズ5 | 113 | 129 |
| FR/NFRカバレッジ | 131 | 159 |
| ACカバレッジ | 161 | 174 |
| 索引 | 176 | 187 |
