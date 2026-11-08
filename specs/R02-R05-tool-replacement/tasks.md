# R02〜R05 実装タスク

## 進め方

`spec.md`、`clarify.md`、`plan.md`の決定を実装する。実装は実装サブエージェント（Haiku）に依頼し、
1回の依頼は3〜4タスクまでとする。各依頼で触るファイルは数個に収め、同じ対象ファイルを持つタスクは
同時に実行せず、表のバッチ内の順序に従って直列で実行する。
各タスクには、対象ファイル、先に赤にする検査（unitのケース名）、完了の確認方法、実行主体、バッチを書く。
依頼には作業ディレクトリ、対象タスク番号、読む行範囲、5分以内に最初のファイル変更がなければ再試行せず、
止まったツールを報告して終了する条件を書く。
Dockerを使うsmoke、品質ゲート、レビュー、ツールの導入と実測は、メインが実行し、実装サブエージェントには実行させない。

フェーズは`plan.md` 14章の9コミット（commit 0〜8）に1対1で対応する。PRは1つとし、
コミットごとに品質ゲートを通してから次へ進む。コミット、push、PR作成は利用者の指示後に利用者の端末で行う。
AGENTS.mdの「コミット前の必須レビュー」に従い、各コミット前に`evidence-code-review`と`security-review`を差分へ適用する。
依存の順は、R01、R05、R04とする（`clarify.md` 8章の決定。`spec.md`のNFR-R0211の「R01、R04、R05」は読み替える）。
R05（commit 3）は、同じ検査を二度書き換えないため、R04（commit 4〜7）より先に行う。

先に赤にする検査は、新しい検査と、期待を更新した既存の検査である。
M09のunitは、R01と同じくDocker、AWS CLI、miseの実行を入れない静的な検査を基本とする。
ただしR02の構造比較はYAMLを読むため、`mise which yq`の実体を使う（`plan.md` 7.2節）。
M09がbatsへ移る前（commit 1〜6）の新しい検査は、M09の既存の形で書き、commit 7で`@test`へ移す（`plan.md` 11.3節）。
batsへ移した後の新しい検査は、bats-coreで書く（FR-R0221）。

各表の行の順が実行の順である。後から足したタスク（T-R0343以降）は、番号を末尾に続け、行は実行する位置に置く。

検査の件数（m09のunitの件数など）は、推測の数字を書かない。`plan.md`の未確認（U16、U17、U20、U21など）に従い、
各段階の開始時に旧の出力を数え、確かめてから決める。ずれは対応表（`plan.md` 6.3節）に残す。
実測で決める事項（U1〜U21）は、確かめた時期のコミットで`plan.md` 13章の状態を「確認済み」に改める。

検証記録は`specs/R02-R05-tool-replacement/verification/`に置く。コミットに含めるのは記録の本文だけとし、
旧の実行の生ログは含めない。識別情報と利用者の絶対パスは書かない。
導入の確認、壊した定義、壊した入力、旧の実行の記録に使う一時ファイル、miseのデータ置き場、worktreeは、
各フェーズの記録タスクで絶対パスを指定して削除し、`git status --short`で残っていないことを確かめる。
一時ファイルは`$KIROCREW_SCRATCH`配下に置く。追跡対象に入れる必要があるときだけ`git add -N`で入れ、
`git reset -- <パス>`で外す（`plan.md` 8.3節、12.2節）。

一般的なツール（actionlint、gitleaks、bats-core、jq、yq）を使い、自前のチェック用シェルは作らない（NFR-R0201）。
`tests/lib/run-bats.sh`は、旧の入口の維持（FR-R0232）のための起動部であり、検査ではない。
置き換えられない理由を`docs/ローカル実行とCI.md`に残す（`plan.md` 2章）。

smokeを含むDockerの検証は、実行できる環境（メイン、CI、利用者の端末）で行い、実行できなかったものは
「未確認」と書いて完了にしない。PRの本文は`Closes #34 #35 #36 #37`とする（FR-R0238）。

## フェーズ0 版の宣言（commit 0）

対象範囲は`plan.md` 3章、6章、14章のcommit 0である。この時点の品質ゲートはR01の状態のままとする。
`mise.lock`は4つの環境のURLとSHA256を公式の情報源と照合して記録する。U1〜U6の結果は`plan.md` 13章へ反映する。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0201 | 5つのツールの最新の安定版を`gh api repos/<owner>/<repo>/releases/latest`で確かめ直す。`plan.md` 1.2節の値（actionlint v1.7.12、gitleaks v8.30.1、bats-core v1.14.0、jq-1.8.2、yq v4.54.2）より新しい版があれば、版を更新して理由を記録する。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | FR-R0228、NFR-R0202 | なし | 5つの版と公開日が記録され、`plan.md`の値と一致する、または更新の理由が記録される。 | メイン | — |
| T-R0202 | 新しい静的検査`t_mise_toml_is_restricted`（`mise.toml`が`min_version`と`[tools]`の6ツールだけであること）を追加する。R01の`t_shellcheck_config_and_mise_toml_are_restricted`が`[tools]`を1ツールに固定していれば、6ツールを許す形に更新する。 | `tests/m09-execution-and-ci.sh` | FR-R0228、NFR-R0209、AC-R0217 | 追加: `t_mise_toml_is_restricted`。更新（必要なとき）: `t_shellcheck_config_and_mise_toml_are_restricted` | `sh tests/m09-execution-and-ci.sh unit`が、`mise.toml`が未変更のため上記ケースで失敗する（赤）。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | A |
| T-R0203 | `t_wf_each_step_runs_its_command`の、mise-actionのstepの`install_args`の期待を`--locked`だけに更新する（`--locked shellcheck`ではなくする）。 | `tests/m09-execution-and-ci.sh` | FR-R0228、FR-R0207 | 更新: `t_wf_each_step_runs_its_command` | `sh tests/m09-execution-and-ci.sh unit`が、ワークフローが未変更のため上記ケースで失敗する（赤）。 | 実装サブエージェント（Haiku） | A |
| T-R0204 | `mise.toml`の`[tools]`に`actionlint = "1.7.12"`、`bats = "1.14.0"`、`gitleaks = "8.30.1"`、`jq = "1.8.2"`、`yq = "4.54.2"`を足す。`shellcheck`と`min_version`は変えない。T-R0201で版が更新されていれば、その値を使う。`[tasks]`、`[hooks]`、`[env]`、`[plugins]`は書かない。 | `mise.toml` | FR-R0228、NFR-R0209、AC-R0217 | `t_mise_toml_is_restricted`が緑になる | `sh tests/m09-execution-and-ci.sh unit`の当該ケースが通り、`git diff --check`が終了コード0である。 | 実装サブエージェント（Haiku） | A |
| T-R0205 | mise-actionのstepの`install_args`を`--locked shellcheck`から`--locked`へ改める。`with:`のほかのキー（`version`、`sha256`、`cache`、`env`）は変えない。 | `.github/workflows/e2e-test.yml` | FR-R0228、FR-R0207、NFR-R0208 | `t_wf_each_step_runs_its_command`が緑になる | `sh tests/m09-execution-and-ci.sh unit`が終了コード0で、`run:`に式が入らず、`uses:`が増えていない。 | 実装サブエージェント（Haiku） | A |
| T-R0206 | `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`で`mise.lock`に5つの4環境のURLとSHA256を足す。`mise trust`は内容を確かめる前に実行しない。差分が5つの公式のGitHubリリースのURLとSHA256だけであり、shellcheckの記録が変わらないことを確かめる（U3）。あるツールが4環境の一つで失敗したら、止めて利用者に諮る（`plan.md` 3.2節の手順2）。 | `mise.lock` | FR-R0228、NFR-R0202、NFR-R0209、AC-R0206、AC-R0211、AC-R0217 | なし | `mise.lock`が5ツール×4環境のURLとSHA256を持ち、差分に公式以外のURLがない。 | メイン | — |
| T-R0207 | `mise.lock`の`checksum_source`が`mise-versions`の項目を、公式の資産のSHA256（APIの`digest`、またはリリースの`checksums`ファイル）と照合して記録する。batsの`github_archive`では、記録されたSHA256がソースのアーカイブの値であることを確かめて書く（U5、U1）。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | NFR-R0202、FR-R0228 | なし | 5ツールぶんのURL、SHA256、照合元が記録され、`mise.lock`の値と一致する。不一致があれば止める。 | メイン | — |
| T-R0208 | `mise install --locked`で5つを導入し、`mise current <ツール>`と各`--version`の出力を記録する。出力の形（actionlint、gitleaks、bats、jq、yq）から、`resolve_tool`が使う版の取り出し式と、jqの`1.8.2`と`jq-1.8.2`の表記の対応を決める（U2、U3、U4）。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | FR-R0228、FR-R0229、AC-R0211、AC-R0217 | なし | 5つの実体が導入され、出力の形と版の取り出し式が記録される。 | メイン | — |
| T-R0209 | `mise which bats`の実体で、`@test`を1つ持つ`$KIROCREW_SCRATCH`配下の一時の`.bats`を実行し、`bin/bats`が同梱の`libexec`を相対で見つけられることを確かめる（U1）。失敗したらbatsだけspec.md 5.2節のC案を検討し、利用者に諮る。一時ファイルは確認の後に絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | FR-R0215、AC-R0211 | なし | 一時の`@test`が通り、結果が記録され、一時ファイルが残らない。 | メイン | — |
| T-R0210 | `jdx/mise-action`のコミットSHAのソースで、`install_args: --locked`が受理され、`--locked`が重複して足されないことを確かめる（U6）。確認したファイルと該当箇所を記録する。受理されない場合は、T-R0205の書き方を改めて利用者に諮る。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | FR-R0228、NFR-R0208 | なし | `install_args`の扱いが記録され、初回CI（T-R0252）より前に完了している。 | メイン | — |
| T-R0211 | U1〜U6の結果を`plan.md` 13章の表へ反映し、状態を「確認済み」に改める。確かめられなかった項目は「未確認」のまま理由を書く。 | `specs/R02-R05-tool-replacement/plan.md` | FR-R0228、NFR-R0202 | なし | 13章のU1〜U6の状態と結果が、`phase-0-results.md`と一致し、`npm run -s lint:md`が終了コード0である。 | メイン | — |
| T-R0212 | 品質ゲートの表の前に、導入するツールが6つ（shellcheck、actionlint、gitleaks、bats、jq、yq）に増えたこと、導入手順（`mise install --locked`）、未導入時の失敗を書く。各ツールのゲートは、使い始めるcommitで表へ足す。 | `AGENTS.md` | FR-R0230、FR-R0229、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、記述が`mise.toml`の内容と一致する。 | 実装サブエージェント（Haiku） | B |
| T-R0213 | 導入、版の固定、`mise.lock`の更新手順、jqとyqを前提条件にすること、batsは`github_archive`でソースのアーカイブが固定されることを書く（`plan.md` 3.2節）。実行時間の欄は実測の反映（T-R0334）まで空けて印を付ける。 | `docs/ローカル実行とCI.md` | FR-R0230、FR-R0223、FR-R0228、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | B |
| T-R0214 | Prerequisitesに、導入するツール（actionlint、gitleaks、bats、jq、yq）と`mise install --locked`を足す。M07、M08、S14が固定している行は変えない。 | `README.md` | FR-R0230、FR-R0223、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、`sh tests/m09-execution-and-ci.sh unit`が通る。 | 実装サブエージェント（Haiku） | B |
| T-R0215 | commit 0の差分に`evidence-code-review`と`security-review`を適用する。`mise.toml`の内容制限、`mise.lock`の差分が公式のURLとSHA256だけであること、mise-actionのstepの変更が`install_args`だけであることを確かめる。 | 変更対象全体 | FR-R0228、NFR-R0202、NFR-R0208、NFR-R0209 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0216 | commit 0の品質ゲートを実行し、導入の実測、識別情報検査、未実行層、残した一時物を記録する。`$KIROCREW_SCRATCH`配下の確認用の一時ファイルとmiseの一時データ置き場を、絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-0-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0217 | commit 0の差分と結果を確認した後、利用者の指示を待ってcommit 0を作る。pushは行わない。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 0だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ1 R02 actionlintとYAMLの構造比較（commit 1）

対象範囲は`plan.md` 4章、5章、7章、11.1節、11.2節、12.1節である。
`t_wf_*`の18関数を`yq -e`の構造比較へ置き換え、`wf_block`、`wf_has_line`、`wf_top_block`、`wf_step_timeout`と
PyYAMLの分岐を削除する。契約の内容は変えない。stepは11個（actionlintを足す）になる。
旧の`t_wf_*`は、置き換えの前に`git show`で複製して`$KIROCREW_SCRATCH`に保存し、同じ入力に旧と新を与えて比べる（`plan.md` 11.1節）。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0218 | 置き換えの前に、旧の`t_wf_*`18関数を含むM09を`$KIROCREW_SCRATCH`へ複製し、現在のワークフローと7.4節の各壊した定義に対する旧の判定を記録する。同時に、U11（actionlintの引数の渡し方、`shellcheck`との関係、既存の`run:`への指摘、`-ignore`の要否）を実測し、`plan.md` 13章へ反映する。 | `specs/R02-R05-tool-replacement/verification/phase-1-results.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0205、FR-R0206、FR-R0201、AC-R0203 | なし | 旧の判定の一覧とU11の結果が記録され、`run:`の形（引数の渡し方）が決まる。 | メイン | — |
| T-R0219 | step数を11個（actionlintを`shellcheck`の次に足す）へ更新し、`t_gate_runs_pinned_tools`（ゲートが`mise which`で実体を得て、`mise exec`と`\|\| true`を使わず、actionlintとyqを確認すること）を追加する。timeoutの検査にactionlintの2分を加える。 | `tests/m09-execution-and-ci.sh` | FR-R0201、FR-R0202、FR-R0207、AC-R0201 | 追加: `t_gate_runs_pinned_tools`。更新: `t_wf_steps_run_in_plan_order`、`t_ci_test_ci_scenarios`、`t_wf_step_timeouts_are_shellcheck3_actionlint2_unit3_test_ci10_smoke8_contract5`（名前も更新）、`t_wf_each_step_runs_its_command`、`t_wf_yaml_parses_with_expected_shape` | `sh tests/m09-execution-and-ci.sh unit`が、ゲートとワークフローが未変更のため上記ケースで失敗する（赤）。追加・更新した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | C |
| T-R0220 | 7.4節の壊した定義（permissions、timeout、`if: always()`、SHA固定、Secrets、stepの並び、trigger、`persist-credentials`、式、artifactの保持の10件）を、一時ファイルへの`sed`で作り、構造比較の検査が失敗することを確かめる新しい検査を追加する。リポジトリのワークフローは書き換えない。 | `tests/m09-execution-and-ci.sh` | FR-R0206、NFR-R0204、AC-R0204 | 追加: `t_wf_broken_definitions_fail`（10件の壊した定義を1件ずつ与える） | `sh tests/m09-execution-and-ci.sh unit`が、構造比較が未実装のため上記ケースで失敗する（赤）。壊した定義の一時ファイルがリポジトリに残らない。 | 実装サブエージェント（Haiku） | C |
| T-R0348 | actionlintが式の誤りを検出することを、永続するunitにする。`t_actionlint_rejects_expression_error`（`$KIROCREW_SCRATCH`配下の一時のワークフローに、存在しないコンテキストの式を書き、`mise which actionlint`の実体が非0で終わること。現在のワークフローでは0で終わること）を追加する。リポジトリのワークフローは書き換えない。 | `tests/m09-execution-and-ci.sh` | FR-R0201、NFR-R0204、AC-R0205 | 追加: `t_actionlint_rejects_expression_error` | ツールの性質を確かめる回帰検査で、commit 0で導入済みのため、追加の時点で緑になりうる。その場合は、常に0で終わる偽の実体で、このunitが失敗することを1度確かめて記録する。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | C |
| T-R0221 | 7.3節の表の前半（`t_wf_file_exists`、`t_wf_triggers_are_pull_request_and_main_push_only`、`t_wf_permissions_are_contents_read_only`、`t_wf_dummy_credentials_are_workflow_env_only`、`t_wf_concurrency_groups_pr_by_ref_and_pushes_by_sha`、`t_wf_step_timeouts_...`、`t_wf_collect_always_upload_on_failure_stop_always`）を、`yq -e`の構造比較へ置き換える。契約ごとに1つの式にし、`null`と`false`は失敗とする。`yq`の実体は`mise which yq`で得る。 | `tests/m09-execution-and-ci.sh` | FR-R0203、FR-R0204、FR-R0205、FR-R0233、AC-R0202、AC-R0203、AC-R0223 | 当該7ケースと`t_wf_broken_definitions_fail`が緑になる方向で進める | 当該7ケースのうち、`t_wf_step_timeouts_…`はactionlintのstepに依存するため、T-R0225（バッチD）まで赤のままでよい。ほかは通り、`on`キーが文字列のまま読めることが確かめられる。`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | C |
| T-R0222 | 7.3節の表の後半（uploadの`with`、Secretsの不使用、`run`の式と1行、式の出現箇所、`uses`のSHA固定、checkoutの`persist-credentials`、stepの並び、各stepの`run`、`docker compose`を呼ばないこと）を構造比較へ置き換える。`# v`のコメントの確認だけは`grep -Eq`のまま残し、理由をコメントで書く。 | `tests/m09-execution-and-ci.sh` | FR-R0203、FR-R0205、FR-R0206、FR-R0233、AC-R0202、AC-R0203 | 当該ケースと`t_wf_broken_definitions_fail`が緑になる方向で進める | 当該ケースのうち、`t_wf_steps_run_in_plan_order`と`t_wf_each_step_runs_its_command`はT-R0225（バッチD）まで赤のままでよい。ほかは通り、壊した定義で失敗する。`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | C |
| T-R0224 | `shellcheck_gate`の版の照合を、共通の関数`resolve_tool`として`scripts/lib/resolve-tool.sh`（新規。関数の定義だけで副作用なし）へ抜き出し、`scripts/quality-gate.sh`が`.`で読み込む（4.2節）。`actionlint`のゲートと、`yq`の先頭の確認を足す。`git ls-files -z`の結果を一時ファイルへ書き、0件は失敗とする。`\|\| true`を使わず、3つの環境変数をmiseを呼ぶ各コマンドに付け、失敗時は導入手順つきの`FAILED:`を出す。順序は共通、shellcheck、actionlint、Markdownとする。M09の実行条件に、`mise.toml`、`mise.lock`、`.gitleaks.toml`、`scripts/lib/`の変更を足す（これらを変えたときもM09 unitが走る）。 | `scripts/quality-gate.sh`、`scripts/lib/resolve-tool.sh` | FR-R0201、FR-R0202、FR-R0229、NFR-R0201、NFR-R0204、AC-R0201 | `t_gate_runs_pinned_tools`が緑になる | `sh scripts/quality-gate.sh`が終了コード0で、`mise exec`が残らず、`shellcheck_gate`の挙動が変わらない。 | 実装サブエージェント（Haiku） | D |
| T-R0225 | `shellcheck`の次、`unit`の前に、`timeout-minutes: 2`の`actionlint`stepを追加する。`run:`はT-R0218で決めた形にし、式（`${{`）を含めない。実体は`mise which actionlint`で得て、自動の導入を止める環境変数を付ける。`uses:`は増やさない。job名`e2e`、`permissions`、`persist-credentials: false`は変えない。 | `.github/workflows/e2e-test.yml` | FR-R0201、FR-R0207、NFR-R0208、AC-R0201 | T-R0219の更新ケースが緑になる | `sh tests/m09-execution-and-ci.sh unit`が終了コード0で、`run:`に式が入らず、`env:`の行が増えない。 | 実装サブエージェント（Haiku） | D |
| T-R0223 | `t_wf_yaml_parses_with_expected_shape`の内容を上の各契約へ吸収し、runner、job名、job全体のtimeout、step数11個を構造比較で確かめる。`wf_block`、`wf_has_line`、`wf_top_block`、`wf_step_timeout`、`import yaml`、SKIP表示を削除する。 | `tests/m09-execution-and-ci.sh` | FR-R0204、FR-R0205、NFR-R0201、AC-R0202 | `t_wf_yaml_parses_with_expected_shape`、`t_wf_broken_definitions_fail`が緑になる | `git grep -nE 'import yaml\|wf_block\|wf_has_line\|wf_top_block\|wf_step_timeout' -- tests`が0件である。M09 unitが終了コード0になる確認は、バッチDの最後（T-R0225の後）に行う。 | 実装サブエージェント（Haiku） | D |
| T-R0226 | 品質ゲートの表に`actionlint`の行（毎回実行、未導入と版違いで失敗）を足し、契約の検査がYAMLの構造比較（`yq`）になったことを書く。 | `AGENTS.md` | FR-R0230、FR-R0201、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、表がゲートの実装と一致する。 | 実装サブエージェント（Haiku） | E |
| T-R0227 | actionlintのstepと上限（2分）、yqによる構造比較、PyYAMLの分岐を無くしたこと、`actionlint`の`run:`の形（U11の結果）を書く。 | `docs/ローカル実行とCI.md` | FR-R0230、FR-R0201、FR-R0204、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | E |
| T-R0228 | 旧と新を同じ入力に与えて比べる。現在のワークフローで旧の18関数が全て通ること、7.4節の10件の壊した定義で旧と新が同じ契約で落ちること、旧の関数が固定していた行を新の式が読んでいること（取りこぼしの確認）を表にして記録する。 | `specs/R02-R05-tool-replacement/verification/phase-1-results.md` | FR-R0205、FR-R0206、NFR-R0204、AC-R0203、AC-R0204 | なし | 旧の関数と新の契約の対応表が保存され、判定が全て一致する。 | メイン | — |
| T-R0229 | 式の誤りを含む一時のワークフロー（`$KIROCREW_SCRATCH`配下）で、actionlintが失敗することを確かめる。次に、mise無し、actionlint未導入（空の一時データ置き場）、版違い（偽の実体）で、品質ゲートが導入手順つきの`FAILED:`を出して非0で終わり、PATH上の別の実行ファイルで通らないことを確かめる（`plan.md` 12.1節）。 | `specs/R02-R05-tool-replacement/verification/phase-1-results.md` | FR-R0201、FR-R0202、FR-R0229、AC-R0201、AC-R0205 | なし | 4つの状態で終了コードが非0になり、表示が記録される。一時ファイルと一時データ置き場を削除する。 | メイン | — |
| T-R0230 | M09 unit、`sh scripts/quality-gate.sh`を実行し、品質ゲートとunitの実行時間をcommit 0の前後で実測する（U18）。Dockerを使うsmokeはM09のsmokeを含めて実行し、結果が変わらないことを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-1-results.md` | NFR-R0204、NFR-R0205、AC-R0219 | なし | 各検査が終了コード0で、実行時間が記録される。 | メイン | — |
| T-R0231 | commit 1の差分に`evidence-code-review`と`security-review`を適用する。構造比較が旧の行の完全一致より弱くなっていないか、actionlintのstepの`run:`に式がないか、`-ignore`を使う場合に個別で理由があるかを確かめる。 | 変更対象全体 | FR-R0205、FR-R0206、FR-R0207、NFR-R0208 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0232 | commit 1の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。`$KIROCREW_SCRATCH`配下の旧のM09の複製と壊した定義を、絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-1-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0233 | commit 1の差分と結果を確認した後、利用者の指示を待ってcommit 1を作る。pushは行わない。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 1だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ2 R03 gitleaks（commit 2）

対象範囲は`plan.md` 4.3節、5章、8章、11.2節である。規則は独自の2段だけとし、`useDefault`、グローバルな`[allowlist]`、
`stopwords`は置かない。`swsc_mask`と`swsc_collect_scrub`、`scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh`は変えない。
識別情報の形の文字列は、実行時に組み立て、ファイルに固定の値を書かない（NFR-R0206）。stepは12個になる。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0234 | gitleaksのU7（`gitleaks dir`が`.gitignore`を尊重するか）、U8（追跡対象でない一時ファイルを検出するか）、U9（`[[rules.allowlists]]`の`condition = "AND"`と`paths`、`regexes`、規則の`path`の書き方）を、`$KIROCREW_SCRATCH`配下の一時の複製で実測し、`plan.md` 13章へ反映する。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0237、FR-R0211、FR-R0236 | なし | U7〜U9の結果が記録され、壊した入力の置き方（追跡対象に入れるか）が決まる。 | メイン | — |
| T-R0235 | step数を12個（gitleaksを`actionlint`の次に足す）へ更新し、timeoutにgitleaksの2分を加え、`t_gate_runs_pinned_tools`にgitleaksを加える。新しい静的検査`t_gitleaks_config_has_no_global_allowlist`（`.gitleaks.toml`に`useDefault`、トップレベルの`[allowlist]`、`stopwords`が無いこと）を追加する。 | `tests/m09-execution-and-ci.sh` | FR-R0208、FR-R0211、FR-R0236、AC-R0206、AC-R0225 | 追加: `t_gitleaks_config_has_no_global_allowlist`。更新: `t_gate_runs_pinned_tools`、`t_wf_steps_run_in_plan_order`、`t_ci_test_ci_scenarios`、`t_wf_step_timeouts_are_shellcheck3_actionlint2_gitleaks2_unit3_test_ci10_smoke8_contract5`（名前も更新）、`t_wf_each_step_runs_its_command`、`t_wf_yaml_parses_with_expected_shape` | `sh tests/m09-execution-and-ci.sh unit`が、ゲートと設定とワークフローが未変更のため上記ケースで失敗する（赤）。追加・更新した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | F |
| T-R0347 | 規則が検出することを、永続するunitにする。`t_gitleaks_rules_detect_runtime_built_values`（`$KIROCREW_SCRATCH`配下の一時ディレクトリに、実行時に組み立てた12桁、ARN、アクセスキーの値を持つファイルを作り、`mise which gitleaks`の実体の`gitleaks dir`が非0で終わり、出力に値が出ないこと。値の形に合わない語だけのファイルでは0で終わること）を追加する。段1の`path`が一時ディレクトリの相対パスに当たるかはT-R0234（U8、U9）で決める。当たらなければ、段2の3種類だけをunitにし、段1ぶんは手動確認（T-R0343、T-R0246）に残して、理由を`plan.md` 8.3節に書く。 | `tests/m09-execution-and-ci.sh` | FR-R0212、FR-R0213、NFR-R0204、NFR-R0206、AC-R0208 | 追加: `t_gitleaks_rules_detect_runtime_built_values` | `sh tests/m09-execution-and-ci.sh unit`が、`.gitleaks.toml`が未作成のため上記ケースで失敗する（赤）。T-R0236の後に緑になる。値をファイルに固定で書かない。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | F |
| T-R0236 | `.gitleaks.toml`を新規に作る。段1は、置き換え前の11ファイルに`path`で限り、`[0-9]{12}`、`arn:aws`、`AKIA`の3規則を置き換え前と同じ文字列で検出する。段2は、`path`を指定せず、値の形に絞ったARN、アクセスキー、アカウントIDの3規則とする。各規則の`description`に置き換え元（`t_doc_has_no_identity_values`、`unit_doc`）を書く。除外はまだ書かない。 | `.gitleaks.toml` | FR-R0209、FR-R0210、FR-R0236、NFR-R0206、AC-R0207、AC-R0225 | `t_gitleaks_config_has_no_global_allowlist`が緑になる | 11ファイルが段1の`path`に全て入り、`.gitleaks.toml`自身が段1の`path`に入らない。`git diff --check`が終了コード0である。 | 実装サブエージェント（Haiku） | F |
| T-R0237 | `gitleaks`のゲートを足す。`<実体> dir . --config .gitleaks.toml --redact --no-banner --exit-code 1`を実行し、終了コードを`status`へ反映する。`resolve_tool`を使い、`\|\| true`を使わない。順序は`actionlint`の次、Markdownの前とする。 | `scripts/quality-gate.sh` | FR-R0208、FR-R0213、FR-R0229、FR-R0237、NFR-R0201、AC-R0206 | `t_gate_runs_pinned_tools`が緑になる | `sh scripts/quality-gate.sh`の当該ゲートが動作し、`--redact`が付き、履歴の走査をしない。 | 実装サブエージェント（Haiku） | F |
| T-R0238 | `actionlint`の次、`unit`の前に、`timeout-minutes: 2`の`gitleaks`stepを追加する。`run:`は4.3節と同じ引数とし、式を含めない。実体は`mise which gitleaks`で得る。`uses:`は増やさない。job名`e2e`とほかのstep名は変えない。 | `.github/workflows/e2e-test.yml` | FR-R0208、FR-R0207、NFR-R0208、AC-R0206 | T-R0235の更新ケースが緑になる | `sh tests/m09-execution-and-ci.sh unit`が終了コード0で、`run:`に式が入らず、`env:`の行が増えない。 | 実装サブエージェント（Haiku） | F |
| T-R0239 | `gitleaks dir`を実行し、検出の一覧（ファイル、行、規則のid。`--redact`のまま）を取り、11ファイルの内と外に分ける。11ファイルの内の検出は原則として除外せずファイル側を直す。外の検出は、実行時に値を組み立てる形に直せるかを確かめ、直せない行だけを除外の候補にする（8.2節）。U10を`plan.md` 13章へ反映する。 | `specs/R02-R05-tool-replacement/verification/phase-2-decisions.md` | FR-R0210、FR-R0211、AC-R0207、AC-R0209 | なし | 検出の一覧と、修正か除外かの案が保存され、識別情報と利用者の絶対パスを含まない。検出が0件なら「0件」と記録する。 | メイン | — |
| T-R0240 | T-R0239の一覧の行だけを対象に、実行時に値を組み立てる形への修正、または規則ごとの`[[rules.allowlists]]`の個別除外（`paths`と`regexes`を`AND`で絞り、`description`に理由）を反映する。`gitleaks dir`が`.gitignore`を尊重しないときだけ、`node_modules/`と`e2e-logs/`を理由つきで除外する。一覧が0件なら省略し、省略したことを記録する。 | `.gitleaks.toml`、T-R0239の一覧で確定したファイル（一覧の確定後に、ファイル名を明記して依頼する） | FR-R0211、FR-R0237、NFR-R0206、AC-R0209、AC-R0225 | `t_gitleaks_config_has_no_global_allowlist`が緑のまま | `gitleaks dir`が終了コード0になり、除外が全件、規則、パス、文字列、理由を持つ。一括の除外がない。 | 実装サブエージェント（Haiku） | G |
| T-R0343 | 8.3節の壊した入力のうち、検出と非表示の確認を、旧の検査を削除する前に行う（旧の検査が弱い状態で残らないようにする）。実行時に組み立てた実在しない値（12桁、ARN、アクセスキー）を、11ファイルの各ファイルへ1つずつ入れた一時ファイルで、品質ゲートが失敗し、出力に値が出ないことを確かめる。旧の検査（`t_doc_has_no_identity_values`、`unit_doc`の2つの`grep`）が残っている状態で、同じ入力を旧と新に与え、旧が落とす入力を新も全て落とすことを表にする。規則に漏れがあれば、T-R0240へ戻って直す。追跡対象に入れた一時ファイルは`git reset -- <パス>`で外し、絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md` | FR-R0210、FR-R0212、FR-R0213、NFR-R0204、NFR-R0206、AC-R0207、AC-R0208 | なし | 3種類×11ファイルで新が失敗し、旧が落とす入力を新も全て落とし、出力に値がない。この確認が済むまで、T-R0241とT-R0242を依頼しない。 | メイン | — |
| T-R0241 | `t_doc_has_no_identity_values`を削除する。ほかの検査が削除した関数に依存していないことを`git grep`で確かめる。 | `tests/m09-execution-and-ci.sh` | FR-R0210、NFR-R0201、AC-R0207 | なし（前提: T-R0343の確認が済んでいること。実行順はT-R0240、T-R0343、T-R0241、T-R0242） | `git grep -n 't_doc_has_no_identity_values' -- tests`が0件で、M09 unitが終了コード0になる。 | 実装サブエージェント（Haiku） | G |
| T-R0242 | `unit_doc`の`[0-9]{12}`と`arn:aws`の2つの`grep`だけを削除する。シナリオ名と禁止の形の検査は残す。 | `tests/m08-e2e-suite.sh` | FR-R0210、NFR-R0201、AC-R0207 | なし（前提: T-R0343の確認が済んでいること。T-R0241の後に依頼する） | `sh tests/m08-e2e-suite.sh unit`が終了コード0で、`unit_doc`のシナリオ名の検査が残っている。 | 実装サブエージェント（Haiku） | G |
| T-R0243 | 品質ゲートの表に`gitleaks`の行（毎回実行、`--redact`、未導入と版違いで失敗）を足す。識別情報の検査がgitleaksへ移ったことを書く。 | `AGENTS.md` | FR-R0230、FR-R0208、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、表がゲートの実装と一致する。 | 実装サブエージェント（Haiku） | G |
| T-R0244 | gitleaksのstepと上限、`.gitleaks.toml`の2段の規則、除外の方針（個別、理由つき、一括なし）、`swsc_mask`と`swsc_collect_scrub`が置き換え対象でない理由（FR-918）、識別情報の形の文字列を実行時に組み立てる規約を書く。 | `docs/ローカル実行とCI.md` | FR-R0230、FR-R0214、FR-R0236、NFR-R0206、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | H |
| T-R0245 | 除外の全件の一覧（規則、パス、文字列、理由。0件のときは「0件」）を`plan.md` 8.2節の表へ反映し、U7〜U10の状態を改める。 | `specs/R02-R05-tool-replacement/plan.md` | FR-R0211、AC-R0209 | なし | 一覧が`.gitleaks.toml`の除外と一致する。`npm run -s lint:md`が終了コード0である。 | 実装サブエージェント（Haiku） | H |
| T-R0246 | 8.3節の壊した入力のうち、範囲外の確認を行う。あわせて、旧の検査の削除後の最終状態で、T-R0343の3種類×11ファイルの確認をもう一度行う（T-R0343は旧の検査が残っている状態での前倒しの確認）。範囲外（`specs/`の文書に`arn:aws`の語だけ）で失敗しないこと。追跡対象に入れた一時ファイルは`git reset -- <パス>`で外し、絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md` | FR-R0210、FR-R0212、FR-R0213、NFR-R0206、AC-R0207、AC-R0208 | なし | 3種類×11ファイルで失敗し、範囲外で失敗せず、出力に値がない。 | メイン | — |
| T-R0247 | `swsc_mask`、`swsc_collect_scrub`、`scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh`の差分が無いことを`git diff`で確かめ、M09のFR-918のunitが通ることを確かめる。gitleaks未導入、版違いで、導入手順つきの`FAILED:`が出ることを`plan.md` 12.1節の手順で確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md` | FR-R0214、FR-R0229、AC-R0206、AC-R0210 | なし | 4つのファイルの差分が0行で、未導入と版違いで終了コードが非0になる。 | メイン | — |
| T-R0248 | M08とM09のunit、`sh scripts/quality-gate.sh`を実行し、gitleaksの実行時間と品質ゲートの実行時間を実測する（U18）。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md` | NFR-R0204、NFR-R0205、AC-R0219 | なし | 各検査が終了コード0で、実行時間が記録される。 | メイン | — |
| T-R0249 | commit 2の差分に`evidence-code-review`と`security-review`を適用する。`.gitleaks.toml`に一括の除外がないこと、`--redact`、識別情報が差分と出力に出ていないことを確かめる。 | 変更対象全体 | FR-R0211、FR-R0213、NFR-R0206 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0250 | commit 2の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。一時ファイルと壊した入力を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-2-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0251 | commit 2の差分と結果を確認した後、利用者の指示を待ってcommit 2を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 2だけを含むコミットを作成する。 | 利用者 | — |
| T-R0252 | 利用者の端末でfeatureブランチをpushし、PRを作成する（本文は`Closes #34 #35 #36 #37`）。T-R0210の完了後に、初回CIで`actionlint`と`gitleaks`のstepが`shellcheck`の次、`unit`の前に実行され、job名`e2e`が変わらないことを確かめる。各stepの所要時間とjob全体の所要時間をメインへ渡す。 | CI | FR-R0201、FR-R0208、FR-R0207、FR-R0238、NFR-R0203、NFR-R0205、AC-R0226 | なし | required checksが成功し、stepごとの所要時間が記録される。 | 利用者 | — |

## フェーズ3 R05 jq（commit 3）

対象範囲は`plan.md` 9章である。JSONの単純な値の取り出しだけを`jq -e`へ置き換える。`key=value`の行の`sed`、Markdownの処理、
信号の検査のPython、壊した入力を作る`sed`は置き換えない。`scripts/e2e-taskdef.py`と`scripts/scenario-lib.sh`は変えない。
置き換えの対象の一覧は、作業の開始時に`grep`で数え直す（FR-R0227）。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0253 | JSONの取り出しの全体を`grep`で数え直し、`plan.md` 9.2節の表（ファイル、行、旧の取り出し、新の式、空・null・壊れたJSONの扱い）を更新する。置き換えない箇所と理由も更新する。旧の実装の判定（現在の正しい入力、壊れたJSON、キーの欠落、空の配列とnull）を、置き換えの前に`$KIROCREW_SCRATCH`へ記録する（9.3節）。 | `specs/R02-R05-tool-replacement/plan.md`、`specs/R02-R05-tool-replacement/verification/phase-3-results.md` | FR-R0224、FR-R0225、FR-R0227、AC-R0216 | なし | 一覧が`grep`の結果と一致し、旧の判定が4つの入力ぶん記録される。 | メイン | — |
| T-R0254 | 新しい静的検査`t_json_extraction_uses_jq`（置き換え対象のファイルに、JSONの取り出しの`python3 -c`と`json.load`が残っていないこと。置き換えない箇所は一覧のとおり除く）と、`t_gate_checks_jq_first`（ゲートの先頭の確認が`jq`の実体と版を確かめること）を追加する。 | `tests/m09-execution-and-ci.sh` | FR-R0224、FR-R0225、FR-R0223、NFR-R0201、AC-R0216、AC-R0217 | 追加: `t_json_extraction_uses_jq`、`t_gate_checks_jq_first` | `sh tests/m09-execution-and-ci.sh unit`が、置き換え前のため上記ケースで失敗する（赤）。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | I |
| T-R0255 | 品質ゲートの先頭の確認に`jq`の実体と版の確認を`resolve_tool`で足す。 | `scripts/quality-gate.sh` | FR-R0223、FR-R0229、NFR-R0201、AC-R0217 | `t_gate_checks_jq_first`が緑になる | `sh scripts/quality-gate.sh`が終了コード0で、jqが未導入のとき導入手順つきで失敗する。 | 実装サブエージェント（Haiku） | I |
| T-R0256 | `validate_json`と`validate_mapping`の判定を確かめる新しいケースを追加する（壊れたJSON、必須キーの欠落、正しい入力）。旧のpython3の実装で、壊れたJSONと欠落が失敗し、正しい入力が成功することも確かめる。 | `tests/m03-wiremock-scenarios.sh` | FR-R0224、FR-R0227、AC-R0216 | 追加: `unit_validate_json_rejects_broken_json`、`unit_validate_mapping_rejects_missing_key`（旧で通り、置き換え後も通る判定の固定） | `sh tests/m03-wiremock-scenarios.sh unit`が終了コード0で、新しい2ケースが旧の実装で通る。 | 実装サブエージェント（Haiku） | I |
| T-R0257 | `validate_json`を`jq -e .`へ、`validate_mapping`を`jq -e`の条件式へ置き換える。`jq`の実体はテストの冒頭で`mise which jq`から得る。失敗の表示が旧と同じ情報を持つようにする。 | `tests/m03-wiremock-scenarios.sh` | FR-R0224、FR-R0227、AC-R0216 | `unit_validate_json_rejects_broken_json`、`unit_validate_mapping_rejects_missing_key`が緑のまま | `sh tests/m03-wiremock-scenarios.sh unit`が終了コード0で、`python3`の埋め込みが残らない。 | 実装サブエージェント（Haiku） | I |
| T-R0258 | `error-500-then-200`の2つの定義の比較（約216行）と、`name`から`urlPath`を取る処理（約448行）の判定を確かめる新しいケースを追加する（見つからないときの扱いは旧と同じにする）。 | `tests/m07-scenario-isolation.sh` | FR-R0224、FR-R0227、AC-R0216 | 追加: `unit_error_500_then_200_definitions_match`、`unit_mapping_urlpath_lookup_missing_name` | `sh tests/m07-scenario-isolation.sh unit`が終了コード0で、新しい2ケースが旧の実装で通る。 | 実装サブエージェント（Haiku） | J |
| T-R0259 | 上の2か所を`jq -e`と`jq -r --arg`へ置き換える。見つからないときの扱い（空を返すか失敗か）を旧と同じにし、`-e`の使い分けを箇所ごとに決める。Markdownの処理（約284行）と`key=value`の`sed`（約425、486行）は変えない。 | `tests/m07-scenario-isolation.sh` | FR-R0224、FR-R0225、FR-R0227、AC-R0216 | T-R0258の2ケースが緑のまま | `sh tests/m07-scenario-isolation.sh unit`が終了コード0で、置き換え対象の`python3`が残らない。 | 実装サブエージェント（Haiku） | J |
| T-R0260 | `"count"`を`sed`で取る処理（約617行）の判定（空とnullは失敗）を確かめる新しいケースを追加する。 | `tests/m08-e2e-suite.sh` | FR-R0225、FR-R0227、AC-R0216 | 追加: `unit_count_extraction_rejects_empty_and_null` | `sh tests/m08-e2e-suite.sh unit`が終了コード0で、新しいケースが旧の実装で通る。 | 実装サブエージェント（Haiku） | J |
| T-R0261 | `"count"`の取り出しを`jq -e '.count'`へ置き換える。`key=value`の`sed`（約526〜537行）は変えない。 | `tests/m08-e2e-suite.sh` | FR-R0225、FR-R0227、AC-R0216 | `unit_count_extraction_rejects_empty_and_null`が緑のまま | `sh tests/m08-e2e-suite.sh unit`が終了コード0になる。 | 実装サブエージェント（Haiku） | J |
| T-R0262 | `python3 -c`でJSONを読む箇所の前半（作業の開始時の一覧で行番号の小さい順の半分）を`jq -e`へ置き換える。`e2e-taskdef.py`を呼ぶ箇所、信号の検査の`python3`、壊したテンプレートを作る`sed`は変えない。箇所ごとの空・null・壊れたJSONの扱いを旧と同じにする。 | `tests/m09-execution-and-ci.sh` | FR-R0224、FR-R0227、FR-R0226、AC-R0216、AC-R0218 | `t_json_extraction_uses_jq`が緑になる方向で進める | `sh tests/m09-execution-and-ci.sh unit`が終了コード0で、対象行の`python3`が残らない。 | 実装サブエージェント（Haiku） | K |
| T-R0263 | 同じ置き換えを後半に行う。完了後に、`t_json_extraction_uses_jq`の対象に残りがないことを確かめる。 | `tests/m09-execution-and-ci.sh` | FR-R0224、FR-R0227、FR-R0226、AC-R0216、AC-R0218 | `t_json_extraction_uses_jq`が緑になる | `sh tests/m09-execution-and-ci.sh unit`が終了コード0で、`t_json_extraction_uses_jq`が通る。 | 実装サブエージェント（Haiku） | K |
| T-R0264 | jqを前提条件にすること、品質ゲートの先頭の確認にjqが入ったことを書く。 | `AGENTS.md` | FR-R0223、FR-R0230、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、記述がゲートの実装と一致する。 | 実装サブエージェント（Haiku） | K |
| T-R0265 | jqの前提条件、JSONの取り出しの方針（`jq -e`、null・false・空は失敗）、置き換えない箇所とその理由（`e2e-taskdef.py`、`scenario-lib.sh`、`key=value`の`sed`）を書く。 | `docs/ローカル実行とCI.md` | FR-R0223、FR-R0225、FR-R0226、FR-R0230、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | K |
| T-R0266 | 置き換えごとに、4つの入力（現在の正しい入力、壊れたJSON、キーの欠落、空の配列とnull）で旧と新の終了コードを比べる。T-R0253の旧の記録と新の結果を、置き換えの一覧の表へ追記する。 | `specs/R02-R05-tool-replacement/verification/phase-3-results.md` | FR-R0224、FR-R0227、AC-R0216 | なし | 全ての置き換えで判定が一致する。旧が成功する箇所は旧の判定を保つ。 | メイン | — |
| T-R0267 | `scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh`、`swsc_mask`、`swsc_collect_scrub`の差分が無いことを確かめる。jq未導入と版違いで、導入手順つきの失敗になることを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-3-results.md` | FR-R0226、FR-R0229、AC-R0217、AC-R0218 | なし | 差分が0行で、未導入と版違いで終了コードが非0になる。 | メイン | — |
| T-R0268 | M03〜M09のunitと、変更したファイルに対応するM03、M07、M08、M09のsmoke（Docker使用）を直列で実行し、結果が変わらないことを確かめる。品質ゲートの実行時間を記録する。 | `specs/R02-R05-tool-replacement/verification/phase-3-results.md` | NFR-R0204、NFR-R0205、AC-R0219 | なし | 各検査が終了コード0で、実行時間が記録される。 | メイン | — |
| T-R0269 | commit 3の差分に`evidence-code-review`と`security-review`を適用する。判定が弱まっていないこと、`jq`の式がnullとfalseを失敗にしていることを確かめる。 | 変更対象全体 | FR-R0224、FR-R0227、NFR-R0204 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0270 | commit 3の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。旧の判定の記録を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-3-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0271 | commit 3の差分と結果を確認した後、利用者の指示を待ってcommit 3を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 3だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ4 R04 段階1 s14、m02〜m05（commit 4）

対象範囲は`plan.md` 6章、10章、11.3節である。bats-coreの基盤（`tests/lib/run-bats.sh`、`tests/bats/helpers/`）を作り、
`s14`、`m02`〜`m05`を移す。旧の入口（`sh tests/<ファイル> [mode]`）は同じ名前、引数、終了コードで残す。
旧の検査名を`@test`の名前にそのまま使い、対応表を`specs/R02-R05-tool-replacement/verification/phase-4-mapping.md`に置く。
`m02`、`m04`、`m05`は`check`関数を持たない直列のスクリプトであり、`@test`の区切り（U16）は旧の出力の単位で決める。
`bats-support`と`bats-assert`は使わない。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0272 | 段階を始める前に、旧の`s14`、`m02`〜`m05`を実行し、検査名と判定の一覧、件数、終了コード、実行時間を`$KIROCREW_SCRATCH`に保存する。旧の出力の形式から、`m02`、`m04`、`m05`の`@test`の区切りの単位（U16）を決める。信号の検査の一覧（`grep -n 'kill -INT\|kill -TERM\|signal\.SIG'`）を数える（U20）。あわせて、(a)他のテストの本文を読む検査の一覧（`plan.md` 11.4節）と、(b)旧のファイルの引数なしのときの既定のモード（`plan.md` 10.1節）を記録する。Dockerを使う旧のsmokeは、メインが実行する。 | `specs/R02-R05-tool-replacement/verification/phase-4-mapping.md` | FR-R0216、FR-R0231、FR-R0234、AC-R0212、AC-R0221 | なし | 旧の記録と区切りの単位が決まり、件数が確かめられる。 | メイン | — |
| T-R0273 | U12（`shellcheck -s bats`が0.11.0で使えるか）、U13（`bats --filter-tags`と`test_tags`）、U14（Linuxのbashでの`sh`の入口からの呼び出し）、U15（`BATS_TEST_TMPDIR`、`setup_file`、信号を受けたときの`teardown_file`）を実測し、`plan.md` 13章へ反映する。 | `specs/R02-R05-tool-replacement/plan.md`、`specs/R02-R05-tool-replacement/verification/phase-4-results.md` | FR-R0215、FR-R0232、FR-R0235、NFR-R0203 | なし | U12〜U15の結果が記録され、`.bats`をshellcheckの対象にするかが決まる。 | メイン | — |
| T-R0274 | 新しい静的検査を追加する。`t_bats_helpers_define_fakes_once`（`make_base_bin`、`make_fake`、`make_shims`、`no_calls`の定義が`tests/bats/helpers/fakes.bash`の1か所だけであること）、`t_run_bats_entry_keeps_interface`（旧の入口が引数の数とモードを検査し、不正なら終了コード2であること）、`t_gate_checks_bats_first`（ゲートの先頭の確認がbatsの実体と版を確かめること）、`t_gate_triggers_cover_bats_paths`（M02〜M09の実行条件が、`tests/bats/`、`tests/bats/helpers/`、`tests/lib/run-bats.sh`の変更でも対応するテストを走らせること）。 | `tests/m09-execution-and-ci.sh` | FR-R0217、FR-R0232、FR-R0215、AC-R0213、AC-R0222 | 追加: `t_bats_helpers_define_fakes_once`、`t_run_bats_entry_keeps_interface`、`t_gate_checks_bats_first`、`t_gate_triggers_cover_bats_paths` | `sh tests/m09-execution-and-ci.sh unit`が、基盤が未作成のため上記ケースで失敗する（赤）。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | L |
| T-R0275 | 品質ゲートの先頭の確認に`bats`の実体と版の確認を足す。U12の結果が`.bats`を対象にできるときは、`git ls-files -z '*.bats'`を別の呼び出しとしてshellcheckの対象へ足し、できないときは`.bash`の補助だけを`-s bash`で検査する。M02〜M09の実行条件に、対応する`tests/bats/<名前>.bats`を足し、`tests/bats/helpers/`と`tests/lib/run-bats.sh`の変更では全てのbatsのテストを走らせる。条件の文字列を固定する`t_gate_*`も、このタスクで更新する。 | `scripts/quality-gate.sh` | FR-R0215、FR-R0229、NFR-R0201、AC-R0211 | `t_gate_checks_bats_first`、`t_gate_triggers_cover_bats_paths`が緑になる | `sh scripts/quality-gate.sh`が終了コード0で、batsが未導入のとき導入手順つきで失敗する。 | 実装サブエージェント（Haiku） | L |
| T-R0276 | `tests/lib/run-bats.sh`を新規に作る。引数の数とモードの値の検査（不正なら終了コード2、旧と同じ文言）、`scripts/lib/resolve-tool.sh`の`resolve_tool`を`.`で読み込んで`bats`の実体と版を得る処理（3つの環境変数は関数の中。複製しない）、`--filter-tags <mode>`、batsの終了コードをそのまま返す処理だけを持たせる。 | `tests/lib/run-bats.sh` | FR-R0215、FR-R0222、FR-R0232、NFR-R0201、AC-R0222 | `t_run_bats_entry_keeps_interface`が緑になる方向で進める | `shellcheck -s sh -S style`が0件で、未導入と版違いで導入手順つきの失敗になる。 | 実装サブエージェント（Haiku） | L |
| T-R0277 | `tests/bats/helpers/common.bash`を新規に作る。旧の冒頭の前面のシェルの検査（22〜29行）を`setup_file`に移して同じ文言で失敗させ、一時ディレクトリ（`setup`で作り`teardown`で削除）、`trap cleanup EXIT`の代わりの`teardown_file`を置く。U15の結果に従う。 | `tests/bats/helpers/common.bash` | FR-R0217、FR-R0235、NFR-R0201、AC-R0213 | なし（`t_bats_helpers_define_fakes_once`の一部） | `bash -n`が成功し、`shellcheck -s bash`が0件である。 | 実装サブエージェント（Haiku） | M |
| T-R0278 | `tests/bats/helpers/fakes.bash`を新規に作る。旧の9ファイルの偽のdockerとawsの用意（`make_base_bin`、`make_fake`、`make_shims`、`no_calls`）を、定義が重複しないよう1か所にまとめる。本文は旧の定義から変えない。 | `tests/bats/helpers/fakes.bash` | FR-R0217、NFR-R0201、AC-R0213 | `t_bats_helpers_define_fakes_once`が緑になる | `bash -n`が成功し、`shellcheck -s bash`が0件で、4つの関数の定義がこのファイルだけにある。 | 実装サブエージェント（Haiku） | M |
| T-R0279 | `s14-taskdef-contract.sh`の`check` 5件を`tests/bats/s14-taskdef-contract.bats`の`@test`へ移す。旧の名前をそのまま使い、`# bats test_tags=unit`を付ける。`tests/s14-taskdef-contract.sh`は`run-bats.sh`を呼ぶ薄い入口にする。重複した`check`系の定義を残さない。 | `tests/s14-taskdef-contract.sh`、`tests/bats/s14-taskdef-contract.bats` | FR-R0216、FR-R0218、FR-R0222、FR-R0232、NFR-R0201、AC-R0212、AC-R0222 | 旧の5件と同名の`@test`が緑になる | `sh tests/s14-taskdef-contract.sh unit`の終了コードが旧と同じで、`bats --count`が5である。 | 実装サブエージェント（Haiku） | M |
| T-R0280 | `m03-wiremock-scenarios.sh`の`check_body`、`check_delay`を含む検査を`tests/bats/m03-wiremock-scenarios.bats`へ移す。T-R0256で追加したケース名も保つ。`tests/m03-wiremock-scenarios.sh`は薄い入口にする。 | `tests/m03-wiremock-scenarios.sh`、`tests/bats/m03-wiremock-scenarios.bats` | FR-R0216、FR-R0218、FR-R0222、FR-R0232、AC-R0212、AC-R0222 | 旧の検査名と同名の`@test`が緑になる | 入口の終了コードが旧と同じで、`bats --count`がT-R0272で数えた旧の件数と一致する。 | 実装サブエージェント（Haiku） | N |
| T-R0281 | `m02-routing-smoke.sh`をT-R0272で決めた単位で`tests/bats/m02-routing-smoke.bats`の`@test`へ移す。`# bats test_tags=smoke`を付ける。`tests/m02-routing-smoke.sh`は薄い入口にし、Colimaなどの前提を変えない。 | `tests/m02-routing-smoke.sh`、`tests/bats/m02-routing-smoke.bats` | FR-R0216、FR-R0222、FR-R0232、AC-R0212、AC-R0222 | 旧の出力の単位と同名の`@test`が緑になる（smokeはメインが実行） | `bats --count`が決めた件数と一致し、`bash -n`が成功する。 | 実装サブエージェント（Haiku） | N |
| T-R0282 | `m04-test-client.sh`を同じ方法で`tests/bats/m04-test-client.bats`へ移し、薄い入口にする。 | `tests/m04-test-client.sh`、`tests/bats/m04-test-client.bats` | FR-R0216、FR-R0222、FR-R0232、AC-R0212、AC-R0222 | 旧の出力の単位と同名の`@test`が緑になる（smokeはメインが実行） | `bats --count`が決めた件数と一致し、`bash -n`が成功する。 | 実装サブエージェント（Haiku） | N |
| T-R0283 | `m05-proxy-integration.sh`を同じ方法で`tests/bats/m05-proxy-integration.bats`へ移し、薄い入口にする。 | `tests/m05-proxy-integration.sh`、`tests/bats/m05-proxy-integration.bats` | FR-R0216、FR-R0222、FR-R0232、AC-R0212、AC-R0222 | 旧の出力の単位と同名の`@test`が緑になる（smokeはメインが実行） | `bats --count`が決めた件数と一致し、`bash -n`が成功する。 | 実装サブエージェント（Haiku） | O |
| T-R0284 | 新しく書くテストをbats-coreで書く方針と、`tests/lib/run-bats.sh`が検査ではなく起動部であり置き換えられない理由、`bats-support`と`bats-assert`を使わない理由、前面のシェルで実行する前提を書く。品質ゲートの表のM02〜M05、S14の行は入口が変わらないことを書く。 | `AGENTS.md` | FR-R0220、FR-R0221、FR-R0230、NFR-R0207、AC-R0215 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、記述が実装と一致する。 | 実装サブエージェント（Haiku） | O |
| T-R0285 | 実行の入口が変わらないこと、`tests/lib/run-bats.sh`の役割と理由、信号の検査と`exit`の扱いの方針（字句のまま移す、`run`で隔離する、前面のシェルで実行する）、`.bats`のshellcheckの扱い（U12）、bashの前提（U14）を書く。 | `docs/ローカル実行とCI.md` | FR-R0219、FR-R0220、FR-R0230、NFR-R0201、NFR-R0207、AC-R0214 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | O |
| T-R0286 | Prerequisitesにbatsを加え、移したテストの実行方法（入口は変わらないこと）を書く。M07、M08、S14が固定している行は変えない。 | `README.md` | FR-R0220、FR-R0230、NFR-R0207 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、`sh tests/m09-execution-and-ci.sh unit`が通る。 | 実装サブエージェント（Haiku） | P |
| T-R0287 | 旧の検査名と新の`@test`名の対応表を`phase-4-mapping.md`に作る（列は旧のファイルと行、旧の名前、新のファイルと`@test`名、判定の一致）。`bats --count`と`grep -c '^@test'`の一致、旧の名前一覧と新の名前一覧の`diff`を取り、差があれば理由を書く。 | `specs/R02-R05-tool-replacement/verification/phase-4-mapping.md` | FR-R0216、FR-R0231、AC-R0212、AC-R0221 | なし | 件数が旧と一致し、名前の差が表に説明される。 | メイン | — |
| T-R0288 | 壊した入力（偽のdockerを失敗させる、期待出力を変える、契約を壊すなど）を旧と新に与え、同じ検査が落ちることを確かめる。入口（`sh tests/<ファイル> [mode]`）の終了コードを旧と比べ、不正な引数が終了コード2であることを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-4-results.md` | FR-R0216、FR-R0222、FR-R0232、AC-R0212、AC-R0221、AC-R0222 | なし | 旧と新が同じ検査で落ち、入口の終了コードが一致する。 | メイン | — |
| T-R0289 | Dockerを使うM02〜M05のsmokeを直列で実行し、旧と新の実行時間を記録する。実行できなかったものは「未確認」と書く。`managed_check`で後始末の漏れが無いことを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-4-results.md` | FR-R0222、FR-R0235、NFR-R0204、NFR-R0205、AC-R0219 | なし | 各smokeが終了コード0で、実行時間が記録され、`swsc-`の残存がない。 | メイン | — |
| T-R0290 | commit 4の差分に`evidence-code-review`と`security-review`を適用する。`.bats`が旧の判定を弱めていないこと、`make_fake`などの定義が1か所であること、`run-bats.sh`が検査を持っていないことを確かめる。 | 変更対象全体 | FR-R0216、FR-R0217、NFR-R0201、NFR-R0204 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0291 | commit 4の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。旧の実行の記録を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-4-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0292 | commit 4の差分と結果を確認した後、利用者の指示を待ってcommit 4を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 4だけを含むコミットを作成する。 | 利用者 | — |
| T-R0293 | 利用者のmacOS（Colima、arm64）の端末で`mise install --locked`と、`sh tests/<ファイル>`の入口（s14、m02〜m05）を実行し、batsがbash 3.2で動くか（U14）を確かめる。版、アーキテクチャ、結果を記録する。未実施のまま完了としない。 | `specs/R02-R05-tool-replacement/verification/phase-4-results.md` | FR-R0215、NFR-R0202、NFR-R0203、AC-R0211 | なし | 両環境で版が`mise.toml`と一致し、入口が動き、結果が記録に残る。 | 利用者 | — |

## フェーズ5 R04 段階2 m06、m07（commit 5）

対象範囲は`plan.md` 6章、10.2節、10.3節である。`m06`の`expect`は、検査名、期待出力、期待終了コードの3つを`@test`の中で全て保つ。
`m07`の信号の検査（`unit_signal_exit_codes`とPythonの`signal`）は、本体を字句のまま移し、呼び出しだけを`@test`にする。
段階1と同じ確認（件数、名前、壊した入力、入口、実行時間）を行ってから次へ進む。
先に赤にする検査はT-R0344（バッチQ0）で足す。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0294 | 段階2を始める前に、旧の`m06`、`m07`を実行し、検査名と判定の一覧、件数、終了コード、実行時間を保存する。信号の検査を`grep`で全件数え、`plan.md` 10.3節の一覧を更新する（U20）。`m06`の`expect`の件数を数える。あわせて、(a)他のテストの本文を読む検査の一覧（`plan.md` 11.4節）と、(b)旧のファイルの引数なしのときの既定のモード（`plan.md` 10.1節）を記録する。開始の前提として、T-R0293（macOSでのbashの確認）の結果が記録されていること。未実施なら、利用者に諮ってから進める。 | `specs/R02-R05-tool-replacement/verification/phase-5-mapping.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0216、FR-R0231、FR-R0234、AC-R0212、AC-R0221、AC-R0224 | なし | 旧の記録と信号の一覧が保存され、件数が確かめられる。 | メイン | — |
| T-R0344 | 新しい静的検査`t_bats_stage2_m06_m07_are_migrated`（`tests/bats/m06-client-resilience.bats`と`tests/bats/m07-scenario-isolation.bats`が存在し、`tests/m06-client-resilience.sh`と`tests/m07-scenario-isolation.sh`に`check`、`must`、`expect`、`expect_rc`、`expect_out`、`expect_err`の定義が残らず、入口が`tests/lib/run-bats.sh`を呼ぶこと）を追加する。 | `tests/m09-execution-and-ci.sh` | FR-R0216、FR-R0217、FR-R0222、FR-R0232、NFR-R0201、AC-R0212、AC-R0213、AC-R0222 | 追加: `t_bats_stage2_m06_m07_are_migrated` | `sh tests/m09-execution-and-ci.sh unit`が、移行前のため上記ケースで失敗する（赤）。T-R0295〜T-R0298の後に緑になる。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | Q0 |
| T-R0295 | `m06-client-resilience.sh`の`expect`を`tests/bats/m06-client-resilience.bats`へ移す。1つの`expect`を1つの`@test`とし、`run`、`[ "$output" = … ]`、`[ "$status" -eq N ]`で検査名、期待出力、期待終了コードの3つを保つ。`tests/m06-client-resilience.sh`は薄い入口にする。 | `tests/m06-client-resilience.sh`、`tests/bats/m06-client-resilience.bats` | FR-R0216、FR-R0218、FR-R0222、FR-R0232、AC-R0212、AC-R0222 | 旧の`expect`の名前と同名の`@test`が緑になる | `bats --count`が旧の件数と一致し、入口の終了コードが旧と同じである。 | 実装サブエージェント（Haiku） | Q |
| T-R0296 | `m07-scenario-isolation.sh`の`check` 19件（`expect_rc`、`expect_out`、`expect_err`を含む）と、T-R0258で追加したケースを、信号の検査を除いて`tests/bats/m07-scenario-isolation.bats`へ移す。`exit`を使う関数は`run`で隔離する。 | `tests/bats/m07-scenario-isolation.bats` | FR-R0216、FR-R0218、FR-R0235、AC-R0212 | 旧の検査名と同名の`@test`が緑になる | `bats --count`が旧の件数から信号の検査を除いた値と一致する。 | 実装サブエージェント（Haiku） | Q |
| T-R0297 | `m07`の信号の検査（`unit_signal_exit_codes`の`kill`と、Pythonの`signal`）を、本体を字句のまま`.bats`へ移す。呼び出しだけを`@test`にして`run`で実行し、終了コードを見る。差分が呼び出しの形だけであることを確かめる。 | `tests/bats/m07-scenario-isolation.bats` | FR-R0219、FR-R0234、FR-R0235、AC-R0214、AC-R0224 | 旧の信号の検査名と同名の`@test`が緑になる | 本体の差分が呼び出しの形だけで、`bats --count`が旧の信号の検査の件数と一致する。 | 実装サブエージェント（Haiku） | Q |
| T-R0298 | `tests/m07-scenario-isolation.sh`を薄い入口にする（引数の検査は旧のまま残す）。移した後に重複する定義が残っていないことを確かめる。 | `tests/m07-scenario-isolation.sh` | FR-R0222、FR-R0232、NFR-R0201、AC-R0213、AC-R0222 | `t_run_bats_entry_keeps_interface`が緑のまま | `sh tests/m07-scenario-isolation.sh unit`の終了コードが旧と同じである。 | 実装サブエージェント（Haiku） | Q |
| T-R0299 | 信号の検査の一覧（`m07`ぶん）を実装に合わせて更新し、字句のまま移した理由と前面のシェルで実行する前提を書く。 | `docs/ローカル実行とCI.md` | FR-R0219、FR-R0230、NFR-R0207、AC-R0214 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | R |
| T-R0300 | 対応表を`phase-5-mapping.md`に作り、`bats --count`と`grep -c '^@test'`の一致、名前の`diff`を確かめる。`expect`の3つの保持（名前、出力、終了コード）を壊した入力で確かめる。入口の終了コードを旧と比べる。 | `specs/R02-R05-tool-replacement/verification/phase-5-mapping.md` | FR-R0216、FR-R0231、AC-R0212、AC-R0221、AC-R0222 | なし | 件数が旧と一致し、旧と新が同じ検査で落ち、入口の終了コードが一致する。 | メイン | — |
| T-R0301 | M06、M07のunitとsmoke（Docker使用）を直列で実行し、旧と新の実行時間を記録する。信号の検査が旧と同じ判定になることを確かめる。実行できなかったものは「未確認」と書く。 | `specs/R02-R05-tool-replacement/verification/phase-5-results.md` | FR-R0234、NFR-R0204、NFR-R0205、AC-R0219、AC-R0224 | なし | 各検査が終了コード0で、実行時間が記録され、`swsc-`の残存がない。 | メイン | — |
| T-R0302 | commit 5の差分に`evidence-code-review`と`security-review`を適用する。信号の検査の差分が呼び出しの形だけであること、`expect`の3つが保たれていることを確かめる。 | 変更対象全体 | FR-R0216、FR-R0234、NFR-R0204 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0303 | commit 5の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。旧の実行の記録を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-5-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0304 | commit 5の差分と結果を確認した後、利用者の指示を待ってcommit 5を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 5だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ6 R04 段階3 m08（commit 6）

対象範囲は`plan.md` 6章、10.3節である。`m08`は1118行、`check` 30件で、Pythonの`signal`（約932〜950行）を含む。
識別情報の部分（commit 2）とJSONの取り出し（commit 3）は移行の前に済んでいる。段階1と同じ確認を行ってから次へ進む。
先に赤にする検査はT-R0345（バッチS0）で足す。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0305 | 段階3を始める前に、旧の`m08`を実行し、検査名と判定の一覧、件数、終了コード、実行時間を保存する。信号の検査を`grep`で数え、`plan.md` 10.3節の一覧を更新する（U20）。あわせて、(a)他のテストの本文を読む検査の一覧（`plan.md` 11.4節）と、(b)旧のファイルの引数なしのときの既定のモード（`plan.md` 10.1節）を記録する。 | `specs/R02-R05-tool-replacement/verification/phase-6-mapping.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0216、FR-R0231、FR-R0234、AC-R0212、AC-R0221、AC-R0224 | なし | 旧の記録と信号の一覧が保存され、件数が確かめられる。 | メイン | — |
| T-R0345 | 新しい静的検査`t_bats_stage3_m08_is_migrated`（`tests/bats/m08-e2e-suite.bats`が存在し、`tests/m08-e2e-suite.sh`に`check`と`make_fake`などの定義が残らず、入口が`tests/lib/run-bats.sh`を呼ぶこと）を追加する。 | `tests/m09-execution-and-ci.sh` | FR-R0216、FR-R0217、FR-R0222、FR-R0232、NFR-R0201、AC-R0212、AC-R0213、AC-R0222 | 追加: `t_bats_stage3_m08_is_migrated` | `sh tests/m09-execution-and-ci.sh unit`が、移行前のため上記ケースで失敗する（赤）。T-R0306〜T-R0309の後に緑になる。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | S0 |
| T-R0306 | `m08-e2e-suite.sh`の`check`のうち信号の検査を除く部分の前半（旧の出力の順で半分）を`tests/bats/m08-e2e-suite.bats`へ移す。旧の名前をそのまま使い、`exit`を使う関数は`run`で隔離する。偽のdockerとawsの用意は`helpers/fakes.bash`を`load`し、重複して持たない。 | `tests/bats/m08-e2e-suite.bats` | FR-R0216、FR-R0217、FR-R0218、FR-R0235、AC-R0212、AC-R0213 | 旧の検査名と同名の`@test`が緑になる | `bats --count`が対応する旧の件数と一致する。 | 実装サブエージェント（Haiku） | S |
| T-R0307 | 後半を同じ方法で移す。 | `tests/bats/m08-e2e-suite.bats` | FR-R0216、FR-R0217、FR-R0218、FR-R0235、AC-R0212、AC-R0213 | 旧の検査名と同名の`@test`が緑になる | `bats --count`が旧の信号の検査を除く件数と一致する。 | 実装サブエージェント（Haiku） | S |
| T-R0308 | Pythonの`signal`の検査を、本体を字句のまま`.bats`へ移し、呼び出しだけを`@test`にする。差分が呼び出しの形だけであることを確かめる。 | `tests/bats/m08-e2e-suite.bats` | FR-R0219、FR-R0234、FR-R0235、AC-R0214、AC-R0224 | 旧の信号の検査名と同名の`@test`が緑になる | 本体の差分が呼び出しの形だけで、`bats --count`が旧の信号の検査の件数と一致する。 | 実装サブエージェント（Haiku） | S |
| T-R0309 | `tests/m08-e2e-suite.sh`を薄い入口にし、引数の検査は旧のまま残す。重複した`check`系と`make_fake`などの定義が残っていないことを確かめる。 | `tests/m08-e2e-suite.sh` | FR-R0217、FR-R0222、FR-R0232、NFR-R0201、AC-R0213、AC-R0222 | `t_bats_helpers_define_fakes_once`が緑のまま | `sh tests/m08-e2e-suite.sh unit`の終了コードが旧と同じである。 | 実装サブエージェント（Haiku） | T |
| T-R0310 | 信号の検査の一覧（`m08`ぶん）を実装に合わせて更新する。 | `docs/ローカル実行とCI.md` | FR-R0219、FR-R0230、NFR-R0207、AC-R0214 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | T |
| T-R0311 | 対応表を`phase-6-mapping.md`に作り、`bats --count`と`grep -c '^@test'`の一致、名前の`diff`を確かめる。壊した入力で旧と新が同じ検査で落ちることと、入口の終了コードを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-6-mapping.md` | FR-R0216、FR-R0231、AC-R0212、AC-R0221、AC-R0222 | なし | 件数が旧と一致し、旧と新が同じ検査で落ち、入口の終了コードが一致する。 | メイン | — |
| T-R0312 | M08のunitとsmoke（Docker使用）を直列で実行し、旧と新の実行時間を記録する。信号の検査が旧と同じ判定になることを確かめる。実行できなかったものは「未確認」と書く。 | `specs/R02-R05-tool-replacement/verification/phase-6-results.md` | FR-R0234、NFR-R0204、NFR-R0205、AC-R0219、AC-R0224 | なし | 各検査が終了コード0で、実行時間が記録され、`swsc-`の残存がない。 | メイン | — |
| T-R0313 | commit 6の差分に`evidence-code-review`と`security-review`を適用する。 | 変更対象全体 | FR-R0216、FR-R0234、NFR-R0204 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0314 | commit 6の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。旧の実行の記録を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-6-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0315 | commit 6の差分と結果を確認した後、利用者の指示を待ってcommit 6を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 6だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ7 R04 段階4 m09（commit 7）

対象範囲は`plan.md` 6章、10.3節、11.3節である。`m09`は3950行で、`unit`、`smoke`、`contract`の3つの入口を持つ。先に赤にする検査はT-R0346（バッチU0）で足す。
他のテストの本文を読む検査（自己参照）の書き換えはT-R0349で行う（`plan.md` 11.4節）。
検査の件数は、227（`plan.md`。静的な行数）と234（`clarify.md`）のどちらも仮の数字であり、一方を正としない。
モード別の実行時の件数を、開始時のT-R0316で旧の出力から数えて確定し（U17）、確定した件数を移行の基準にする。
移す単位は、開始時に作る分割表（関数の接頭辞ごと）の群とする。群の数は分割表で確定し、足りない行は
番号を既存のタスクの後ろから振って追加する（実行の順序は表の行の順とする）。
commit 1〜3で追加した静的検査（`t_wf_*`、`t_gate_*`、`t_mise_toml_is_restricted`、`t_gitleaks_config_has_no_global_allowlist`、
`t_json_extraction_uses_jq`、`t_bats_*`、`t_run_bats_entry_keeps_interface`）も`@test`へ移す。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0316 | 段階4を始める前に、旧の`m09`の`unit`、`smoke`、`contract`を実行し、検査名と判定の一覧、モードごとの件数、終了コード、実行時間を保存する。U17（227と234は、どちらも実機の旧の出力で確定するまでの仮の数字）について、モード別の実行時の件数を旧の出力で数えて確定し、234の出所も記録して、`plan.md` 6.3節と13章へ反映する。推測で一方を正としない。信号の検査（約27、190、749、1806〜3628、2171行付近）を`grep`で数えて一覧を更新する（U20）。関数の接頭辞ごとの分割表（群）を作る。分割表には、`plan.md` 11.4節の自己参照の検査の一覧も含める。あわせて、(a)他のテストの本文を読む検査の一覧（`plan.md` 11.4節）と、(b)旧のファイルの引数なしのときの既定のモード（`plan.md` 10.1節）を記録する。 | `specs/R02-R05-tool-replacement/verification/phase-7-mapping.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0216、FR-R0231、FR-R0234、AC-R0212、AC-R0221、AC-R0224 | なし | 旧の記録、件数、信号の一覧、分割表が保存され、件数のずれの出所が説明される。 | メイン | — |
| T-R0317 | m09のワークフローを読む検査のうち、`t_wf_*`以外のもの（`plan.md` 7.3節の末尾の行）を`grep`で一覧にし、構造比較か`grep -Eq`のどちらで保つかを割り当てる。 | `specs/R02-R05-tool-replacement/verification/phase-7-mapping.md` | FR-R0205、FR-R0216、AC-R0203、AC-R0212 | なし | 一覧が保存され、移行の前に割り当てが決まる。 | メイン | — |
| T-R0346 | 新しい検査`t_bats_stage4_m09_is_migrated`（`tests/bats/m09-execution-and-ci.bats`が存在し、`tests/m09-execution-and-ci.sh`に`check`、`must`、`rc_is`、`expect`、`make_fake`の定義が残らず、入口が`tests/lib/run-bats.sh`を呼ぶこと。`mise which bats`の実体の`--count --filter-tags`が、モードごとにT-R0316で確定した件数と一致すること）を追加する。件数は、T-R0316の記録から取って書く。仮の数字を先に書かない。 | `tests/m09-execution-and-ci.sh` | FR-R0216、FR-R0217、FR-R0222、FR-R0231、FR-R0232、NFR-R0201、AC-R0212、AC-R0213、AC-R0221、AC-R0222 | 追加: `t_bats_stage4_m09_is_migrated`（名前が`t_bats_*`で始まるため、群1と同じく`@test`へ移す） | `sh tests/m09-execution-and-ci.sh unit`が、移行前のため上記ケースで失敗する（赤）。T-R0318〜T-R0323の後に緑になる。追加した行の`shellcheck -s sh -S style`が0件である。 | 実装サブエージェント（Haiku） | U0 |
| T-R0318 | 分割表の群1（静的な検査: `t_wf_*`、`t_gate_*`、`t_mise_*`、`t_gitleaks_*`、`t_json_*`、`t_bats_*`、`t_run_bats_*`）を`tests/bats/m09-execution-and-ci.bats`へ移す。旧の名前を`@test`の名前にそのまま使い、`# bats test_tags=unit`を付ける。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0216、FR-R0218、FR-R0221、AC-R0212、AC-R0215 | 旧の名前と同名の`@test`が緑になる | `bats --count`が群1の旧の件数と一致する。 | 実装サブエージェント（Haiku） | U |
| T-R0319 | 分割表の群2（`t_ci_*`、`t_doc_*`など文書とCIの検査）を同じ方法で移す。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0216、FR-R0218、AC-R0212 | 旧の名前と同名の`@test`が緑になる | `bats --count`が群2の旧の件数と一致する。 | 実装サブエージェント（Haiku） | U |
| T-R0320 | 分割表の群3（残りのunitの実行系の検査で、信号を除くもの）を同じ方法で移す。`exit`を使う関数は`run`で隔離する。偽のdockerとawsの用意は`helpers/fakes.bash`を`load`する。群が多い場合は、分割表の群ごとに行を足す。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0216、FR-R0217、FR-R0218、FR-R0235、AC-R0212、AC-R0213 | 旧の名前と同名の`@test`が緑になる | `bats --count`が群3の旧の件数と一致する。 | 実装サブエージェント（Haiku） | U |
| T-R0321 | 分割表の群4（`smoke`と`contract`の検査）を同じ方法で移す。`# bats test_tags=smoke`、`# bats test_tags=contract`を付ける。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0216、FR-R0218、FR-R0222、AC-R0212 | 旧の名前と同名の`@test`が緑になる（smokeはメインが実行） | `bats --count`が群4の旧の件数と一致し、モードごとの件数が旧と一致する。 | 実装サブエージェント（Haiku） | V |
| T-R0322 | 信号の検査（冒頭の`SIGINT`無視の検査、`kill -TERM`、偽のawsの`kill -INT`と`kill -TERM`、`lib_call`経由の`kill`、Pythonの`signal`）を、本体を字句のまま`.bats`へ移す。呼び出しだけを`@test`にして`run`で実行する。差分が呼び出しの形だけであることを確かめる。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0219、FR-R0234、FR-R0235、AC-R0214、AC-R0224 | 旧の信号の検査名と同名の`@test`が緑になる | 本体の差分が呼び出しの形だけで、`bats --count`が旧の信号の検査の件数と一致する。 | 実装サブエージェント（Haiku） | V |
| T-R0349 | `plan.md` 11.4節に従い、T-R0316の一覧にある自己参照の検査（`t_smoke_registers_items_1_to_11_in_order`、`t_contract_registers_c1_to_c6_in_order`、`t_smoke_runs_unit_before_docker`など）を、割り当てた読む先と式で書き換える。登録順は`tests/bats/m09-execution-and-ci.bats`の`@test`の並びを読む式にし、契約（11項目、6項目の順序）は変えない。T-R0323（本体の削除）より前に行う。 | `tests/bats/m09-execution-and-ci.bats` | FR-R0216、FR-R0218、NFR-R0204、AC-R0212、AC-R0222 | 書き換えた各検査が、順序を入れ替えた一時コピーで失敗する | 書き換えた各検査が、現在の入力で通り、壊した入力（順序の入れ替え、項目の欠落）で旧と同じ判定になる。T-R0325の表に結果を追記する。 | 実装サブエージェント（Haiku） | V |
| T-R0323 | `tests/m09-execution-and-ci.sh`を、モード（`unit`、`smoke`、`contract`）の検査と`run-bats.sh`の呼び出しだけの薄い入口にする。`for test in`の行、ブロックの先頭、引数の検査は旧のまま残す。旧の`check`、`must`、`rc_is`、`expect`、`make_fake`などの定義と、移した検査の本体を削除する。 | `tests/m09-execution-and-ci.sh` | FR-R0217、FR-R0222、FR-R0232、NFR-R0201、AC-R0213、AC-R0222 | `t_bats_helpers_define_fakes_once`、`t_run_bats_entry_keeps_interface`が緑のまま | `sh tests/m09-execution-and-ci.sh unit`の終了コードが旧と同じで、`git grep -nE '^(check\|must\|rc_is\|expect\|make_fake)\(\)' -- tests`が0件である。 | 実装サブエージェント（Haiku） | V |
| T-R0324 | 文書の検査（M09の文書の検査）が、薄い入口になったM09を読んでも通ること、モードごとの実行方法と信号の検査の一覧（`m09`ぶん）を書く。 | `docs/ローカル実行とCI.md` | FR-R0219、FR-R0220、FR-R0230、NFR-R0207、AC-R0214 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、`bats`を通したM09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | W |
| T-R0325 | 対応表を`phase-7-mapping.md`に作り、モードごとに`bats --count`と`grep -c '^@test'`の一致、名前の`diff`を確かめる。壊した入力で旧と新が同じ検査で落ちることを確かめ、入口の終了コードを旧と比べる。T-R0349で書き換えた自己参照の検査の結果も表に追記する。 | `specs/R02-R05-tool-replacement/verification/phase-7-mapping.md` | FR-R0216、FR-R0231、AC-R0212、AC-R0221、AC-R0222 | なし | 3つの入口の件数と終了コードが旧と一致し、旧と新が同じ検査で落ちる。 | メイン | — |
| T-R0326 | M09の`unit`、`smoke`、`contract`（Docker使用）を直列で実行し、旧と新の実行時間を記録する。CIのjobの上限（15分）に収まる見込みを、実測から確かめる。実行できなかったものは「未確認」と書く。 | `specs/R02-R05-tool-replacement/verification/phase-7-results.md` | FR-R0234、NFR-R0204、NFR-R0205、AC-R0219、AC-R0224 | なし | 各検査が終了コード0で、実行時間が記録され、`swsc-`の残存がない。 | メイン | — |
| T-R0327 | commit 7の差分に`evidence-code-review`と`security-review`を適用する。移行で判定が弱まっていないこと、信号の検査の本体が字句のままであること、`@test`の名前が旧と同じであることを確かめる。 | 変更対象全体 | FR-R0216、FR-R0234、NFR-R0204 | なし | Critical・High・Mediumの未対応指摘がなく、確認範囲が記録される。 | メイン | — |
| T-R0328 | commit 7の品質ゲートを実行し、識別情報検査、未実行層、残した一時物を記録する。旧の実行の記録を絶対パスで削除する。 | `specs/R02-R05-tool-replacement/verification/phase-7-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外の生成物がない。 | メイン | — |
| T-R0329 | commit 7の差分と結果を確認した後、利用者の指示を待ってcommit 7を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 7だけを含むコミットを作成する。 | 利用者 | — |

## フェーズ8 文書の最終確認（commit 8）

対象範囲は`plan.md` 14章のcommit 8、15章である。文書を実装と一致させ、実測値を記録し、全ACの確認方法を実行して記録する。
`docs/ローカル実行とCI.md`の記述が実装と一致するか（U21）をここで確かめる。
この段階は文書と記録だけで、検査の振る舞いを変えないため、先に赤にする検査は置かない。

| タスクID | 内容 | 対象ファイル | 対応するFR/NFR/AC | 先に赤にする検査（unitのケース名） | 完了の確認方法 | 実行主体 | バッチ |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-R0330 | `AGENTS.md`の品質ゲートの表、ツールの一覧、導入手順、前提条件を、実装（ゲートの順序、入口、`bats`、`jq`、`yq`）と突き合わせて直す。 | `AGENTS.md` | FR-R0230、NFR-R0207、AC-R0220 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、表がゲートの実装と一致する。 | 実装サブエージェント（Haiku） | X |
| T-R0331 | 導入、版の固定、`mise.lock`の更新手順、CIのstepの順序と上限、信号の検査の方針、bashの前提、各ツールの前提条件を、実装と突き合わせて直す（U21）。実測値の欄は、T-R0334の結果で埋める。 | `docs/ローカル実行とCI.md` | FR-R0230、FR-R0219、NFR-R0205、NFR-R0207、AC-R0220 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、M09 unitの文書の検査が通る。 | 実装サブエージェント（Haiku） | X |
| T-R0332 | Prerequisitesと実行方法を、実装と突き合わせて直す。M07、M08、S14が固定している行は変えない。 | `README.md` | FR-R0230、NFR-R0207、AC-R0220 | なし | `npm run -s lint:md`と`git diff --check`が終了コード0で、`sh tests/m09-execution-and-ci.sh unit`が通る。 | 実装サブエージェント（Haiku） | X |
| T-R0333 | `make_fake`、`make_shims`、`make_base_bin`、`no_calls`の定義が1か所であること、`import yaml`、`wf_block`、`wf_has_line`、`wf_top_block`、`wf_step_timeout`、JSON取り出しの`python3`、重複した`check`系の定義が残っていないことを`git grep`で確かめる。`.gitleaks.toml`の除外の全件を列挙する。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md` | FR-R0217、FR-R0204、FR-R0211、NFR-R0201、AC-R0202、AC-R0209、AC-R0213、AC-R0225 | なし | 各`git grep`の結果が期待どおりで、除外が全件、理由を持つ。 | メイン | — |
| T-R0334 | 置き換えの前後の実測値（品質ゲート、actionlint、gitleaks、各段階のbats、CIのjob全体）を集計して記録し、`docs/ローカル実行とCI.md`の実行時間の欄へ反映する。CIのjob全体が15分に収まることを確かめる。U18を確認済みにする。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md`、`docs/ローカル実行とCI.md` | NFR-R0205、AC-R0219 | なし | 実測値と根拠が記録され、15分に収まる。 | メイン | — |
| T-R0335 | 全ACの確認方法（AC-R0201〜AC-R0226）を実行し、結果を記録する。壊した入力（AC-R0204、AC-R0208、AC-R0212、AC-R0216）で検査が失敗することを再確認する。`plan.md` 13章のU1〜U21の状態を改め、確かめられなかった項目は「未確認」のまま理由を書く。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md`、`specs/R02-R05-tool-replacement/plan.md` | FR-R0230、FR-R0231、FR-R0238、AC-R0201〜AC-R0226 | なし | 全ACの確認結果が表になり、13章の状態が結果と一致する。 | メイン | — |
| T-R0336 | `scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh`、`swsc_mask`、`swsc_collect_scrub`の差分が、PR全体で無いことを`git diff`で確かめる。`git log`のcommitが0〜8の順序であることを確かめる。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md` | FR-R0214、FR-R0226、FR-R0238、NFR-R0211、AC-R0210、AC-R0218、AC-R0226 | なし | 4つのファイルの差分が0行で、commitの順序が`plan.md` 14章と一致する。 | メイン | — |
| T-R0337 | M02〜M09のunit、smoke、contract（Docker使用）を、最終の差分で直列に実行し、結果と所要時間を記録する。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md` | NFR-R0204、NFR-R0205、AC-R0219 | なし | 各検査が終了コード0で、実行時間が記録される。 | メイン | — |
| T-R0338 | 全commitの差分に`evidence-code-review`と`security-review`を適用し、Critical・High・Mediumを0件にする。要件適合、AWS・CIへの影響、品質ゲートの不足も確認する。CI定義を変えたため、任意の`aws-well-architected-review-lite`を実行するかの判断を記録する。 | 変更対象と関連実装 | FR-R0201〜FR-R0238、NFR-R0201〜NFR-R0211 | なし | 未対応のCritical・High・Mediumがなく、確認範囲と判断が作業記録に残る。 | メイン | — |
| T-R0339 | 最終の品質ゲートを1回実行し、識別情報検査、結果を記録する。一時ファイル、一時データ置き場、worktreeを削除し、削除したものと残したものを記録する。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md` | NFR-R0204、NFR-R0206、NFR-R0210、AC-R0219、AC-R0220 | なし | `sh scripts/quality-gate.sh`、`npm run -s lint:md`、`git diff --check`が終了コード0で、`git status --short`に想定外のファイルがない。 | メイン | — |
| T-R0340 | commit 8の差分と結果を確認した後、利用者の指示を待ってcommit 8を作る。 | 変更対象全体 | FR-R0238、NFR-R0211、AC-R0226 | なし | `git diff --check`が終了コード0で、利用者がcommit 8だけを含むコミットを作成する。 | 利用者 | — |
| T-R0341 | 利用者のmacOS（Colima、arm64）とLinuxの端末で`mise install --locked`と品質ゲートを実行し、5つのツールの版とアーキテクチャを記録する。U19を確認済みにする。未実施のまま完了としない。 | `specs/R02-R05-tool-replacement/verification/phase-8-results.md` | FR-R0228、NFR-R0202、NFR-R0203、AC-R0206、AC-R0211、AC-R0217 | なし | 両環境で版が`mise.toml`と一致し、品質ゲートが通り、結果が記録に残る。 | 利用者 | — |
| T-R0342 | 9つのcommitを確認した後、利用者の端末でfeatureブランチをpushし、既存のPRを更新する。更新後のCIで、`actionlint`、`gitleaks`、`unit`、`smoke`、`contract`の各stepと、必須ステータスチェック`e2e`が成功することを確かめる。 | Git履歴、PR | FR-R0201、FR-R0208、FR-R0215、FR-R0238、NFR-R0203、NFR-R0205、AC-R0219、AC-R0226 | なし | pushが成功し、更新後のPRでrequired checksが成功する。 | 利用者 | — |

## FR/NFRカバレッジ

| 要件 | 対応タスク |
| --- | --- |
| FR-R0201 | T-R0218、T-R0219、T-R0224〜T-R0227、T-R0229、T-R0252、T-R0338、T-R0342、T-R0348 |
| FR-R0202 | T-R0219、T-R0224、T-R0229、T-R0338 |
| FR-R0203 | T-R0221、T-R0222、T-R0338 |
| FR-R0204 | T-R0221、T-R0223、T-R0227、T-R0333、T-R0338 |
| FR-R0205 | T-R0218、T-R0221〜T-R0223、T-R0228、T-R0231、T-R0317、T-R0338 |
| FR-R0206 | T-R0218、T-R0220、T-R0222、T-R0228、T-R0231、T-R0338 |
| FR-R0207 | T-R0203、T-R0205、T-R0219、T-R0225、T-R0231、T-R0238、T-R0252、T-R0338 |
| FR-R0208 | T-R0235、T-R0237、T-R0238、T-R0243、T-R0252、T-R0338、T-R0342 |
| FR-R0209 | T-R0236、T-R0338 |
| FR-R0210 | T-R0236、T-R0239、T-R0241、T-R0242、T-R0246、T-R0338、T-R0343 |
| FR-R0211 | T-R0234、T-R0235、T-R0239、T-R0240、T-R0245、T-R0249、T-R0333、T-R0338 |
| FR-R0212 | T-R0246、T-R0338、T-R0343、T-R0347 |
| FR-R0213 | T-R0237、T-R0246、T-R0249、T-R0338、T-R0343、T-R0347 |
| FR-R0214 | T-R0244、T-R0247、T-R0336、T-R0338 |
| FR-R0215 | T-R0209、T-R0273〜T-R0276、T-R0293、T-R0338、T-R0342 |
| FR-R0216 | T-R0272、T-R0279〜T-R0283、T-R0287、T-R0288、T-R0290、T-R0294〜T-R0296、T-R0300、T-R0302、T-R0305〜T-R0307、T-R0311、T-R0313、T-R0316〜T-R0321、T-R0325、T-R0327、T-R0338、T-R0344、T-R0345、T-R0346、T-R0349 |
| FR-R0217 | T-R0274、T-R0277、T-R0278、T-R0290、T-R0306、T-R0307、T-R0309、T-R0320、T-R0323、T-R0333、T-R0338、T-R0344、T-R0345、T-R0346 |
| FR-R0218 | T-R0279、T-R0280、T-R0295、T-R0296、T-R0306、T-R0307、T-R0318〜T-R0321、T-R0338、T-R0349 |
| FR-R0219 | T-R0285、T-R0297、T-R0299、T-R0308、T-R0310、T-R0322、T-R0324、T-R0331、T-R0338 |
| FR-R0220 | T-R0284〜T-R0286、T-R0324、T-R0338 |
| FR-R0221 | T-R0284、T-R0318、T-R0338 |
| FR-R0222 | T-R0276、T-R0279〜T-R0283、T-R0288、T-R0289、T-R0295、T-R0298、T-R0309、T-R0321、T-R0323、T-R0338、T-R0344、T-R0345、T-R0346 |
| FR-R0223 | T-R0213、T-R0214、T-R0254、T-R0255、T-R0264、T-R0265、T-R0338 |
| FR-R0224 | T-R0253、T-R0254、T-R0256〜T-R0259、T-R0262、T-R0263、T-R0266、T-R0269、T-R0338 |
| FR-R0225 | T-R0253、T-R0254、T-R0259〜T-R0261、T-R0265、T-R0338 |
| FR-R0226 | T-R0262、T-R0263、T-R0265、T-R0267、T-R0336、T-R0338 |
| FR-R0227 | T-R0253、T-R0256〜T-R0263、T-R0266、T-R0269、T-R0338 |
| FR-R0228 | T-R0201〜T-R0208、T-R0210、T-R0211、T-R0213、T-R0215、T-R0338、T-R0341 |
| FR-R0229 | T-R0208、T-R0212、T-R0224、T-R0229、T-R0237、T-R0247、T-R0255、T-R0267、T-R0275、T-R0338 |
| FR-R0230 | T-R0212〜T-R0214、T-R0226、T-R0227、T-R0243、T-R0244、T-R0264、T-R0265、T-R0284〜T-R0286、T-R0299、T-R0310、T-R0324、T-R0330〜T-R0332、T-R0335、T-R0338 |
| FR-R0231 | T-R0272、T-R0287、T-R0294、T-R0300、T-R0305、T-R0311、T-R0316、T-R0325、T-R0335、T-R0338、T-R0346 |
| FR-R0232 | T-R0273、T-R0274、T-R0276、T-R0279〜T-R0283、T-R0288、T-R0295、T-R0298、T-R0309、T-R0323、T-R0338、T-R0344、T-R0345、T-R0346 |
| FR-R0233 | T-R0221、T-R0222、T-R0338 |
| FR-R0234 | T-R0272、T-R0294、T-R0297、T-R0301、T-R0302、T-R0305、T-R0308、T-R0312、T-R0313、T-R0316、T-R0322、T-R0326、T-R0327、T-R0338 |
| FR-R0235 | T-R0273、T-R0277、T-R0289、T-R0296、T-R0297、T-R0306〜T-R0308、T-R0320、T-R0322、T-R0338 |
| FR-R0236 | T-R0234〜T-R0236、T-R0244、T-R0338 |
| FR-R0237 | T-R0234、T-R0237、T-R0240、T-R0338 |
| FR-R0238 | T-R0217、T-R0233、T-R0251、T-R0252、T-R0271、T-R0292、T-R0304、T-R0315、T-R0329、T-R0335、T-R0336、T-R0338、T-R0340、T-R0342 |
| NFR-R0201 | T-R0223、T-R0224、T-R0237、T-R0241、T-R0242、T-R0254、T-R0255、T-R0275〜T-R0279、T-R0285、T-R0290、T-R0298、T-R0309、T-R0323、T-R0333、T-R0338、T-R0344、T-R0345、T-R0346 |
| NFR-R0202 | T-R0201、T-R0206、T-R0207、T-R0211、T-R0215、T-R0293、T-R0338、T-R0341 |
| NFR-R0203 | T-R0252、T-R0273、T-R0293、T-R0338、T-R0341、T-R0342 |
| NFR-R0204 | T-R0216、T-R0220、T-R0224、T-R0228、T-R0230、T-R0232、T-R0248、T-R0250、T-R0268〜T-R0270、T-R0289〜T-R0291、T-R0301〜T-R0303、T-R0312〜T-R0314、T-R0326〜T-R0328、T-R0337〜T-R0339、T-R0343、T-R0347、T-R0348、T-R0349 |
| NFR-R0205 | T-R0230、T-R0248、T-R0252、T-R0268、T-R0289、T-R0301、T-R0312、T-R0326、T-R0331、T-R0334、T-R0337、T-R0338、T-R0342 |
| NFR-R0206 | T-R0216、T-R0232、T-R0236、T-R0240、T-R0244、T-R0246、T-R0249、T-R0250、T-R0270、T-R0291、T-R0303、T-R0314、T-R0328、T-R0338、T-R0339、T-R0343、T-R0347 |
| NFR-R0207 | T-R0212〜T-R0214、T-R0226、T-R0227、T-R0243、T-R0244、T-R0264、T-R0265、T-R0284〜T-R0286、T-R0299、T-R0310、T-R0324、T-R0330〜T-R0332、T-R0338 |
| NFR-R0208 | T-R0205、T-R0210、T-R0215、T-R0225、T-R0231、T-R0238、T-R0338 |
| NFR-R0209 | T-R0202、T-R0204、T-R0206、T-R0215、T-R0338 |
| NFR-R0210 | T-R0216、T-R0232、T-R0250、T-R0270、T-R0291、T-R0303、T-R0314、T-R0328、T-R0338、T-R0339 |
| NFR-R0211 | T-R0217、T-R0233、T-R0251、T-R0271、T-R0292、T-R0304、T-R0315、T-R0329、T-R0336、T-R0338、T-R0340 |

## ACカバレッジ

| AC | 対応タスク |
| --- | --- |
| AC-R0201 | T-R0219、T-R0224、T-R0225、T-R0229、T-R0335 |
| AC-R0202 | T-R0221〜T-R0223、T-R0333、T-R0335 |
| AC-R0203 | T-R0218、T-R0221、T-R0222、T-R0228、T-R0317、T-R0335 |
| AC-R0204 | T-R0220、T-R0228、T-R0335 |
| AC-R0205 | T-R0229、T-R0335、T-R0348 |
| AC-R0206 | T-R0206、T-R0235、T-R0237、T-R0238、T-R0247、T-R0335、T-R0341 |
| AC-R0207 | T-R0236、T-R0239、T-R0241、T-R0242、T-R0246、T-R0335、T-R0343 |
| AC-R0208 | T-R0246、T-R0335、T-R0343、T-R0347 |
| AC-R0209 | T-R0239、T-R0240、T-R0245、T-R0333、T-R0335 |
| AC-R0210 | T-R0247、T-R0335、T-R0336 |
| AC-R0211 | T-R0206、T-R0208、T-R0209、T-R0275、T-R0293、T-R0335、T-R0341 |
| AC-R0212 | T-R0272、T-R0279〜T-R0283、T-R0287、T-R0288、T-R0294〜T-R0296、T-R0300、T-R0305〜T-R0307、T-R0311、T-R0316〜T-R0321、T-R0325、T-R0335、T-R0344、T-R0345、T-R0346、T-R0349 |
| AC-R0213 | T-R0274、T-R0277、T-R0278、T-R0298、T-R0306、T-R0307、T-R0309、T-R0320、T-R0323、T-R0333、T-R0335、T-R0344、T-R0345、T-R0346 |
| AC-R0214 | T-R0285、T-R0297、T-R0299、T-R0308、T-R0310、T-R0322、T-R0324、T-R0335 |
| AC-R0215 | T-R0284、T-R0318、T-R0335 |
| AC-R0216 | T-R0253、T-R0254、T-R0256〜T-R0263、T-R0266、T-R0335 |
| AC-R0217 | T-R0202、T-R0204、T-R0206、T-R0208、T-R0254、T-R0255、T-R0267、T-R0335、T-R0341 |
| AC-R0218 | T-R0262、T-R0263、T-R0267、T-R0335、T-R0336 |
| AC-R0219 | T-R0216、T-R0230、T-R0232、T-R0248、T-R0250、T-R0268、T-R0270、T-R0289、T-R0291、T-R0301、T-R0303、T-R0312、T-R0314、T-R0326、T-R0328、T-R0334、T-R0335、T-R0337、T-R0339、T-R0342 |
| AC-R0220 | T-R0330〜T-R0332、T-R0335、T-R0339 |
| AC-R0221 | T-R0272、T-R0287、T-R0288、T-R0294、T-R0300、T-R0305、T-R0311、T-R0316、T-R0325、T-R0335、T-R0346 |
| AC-R0222 | T-R0274、T-R0276、T-R0279〜T-R0283、T-R0288、T-R0295、T-R0298、T-R0300、T-R0309、T-R0311、T-R0323、T-R0325、T-R0335、T-R0344、T-R0345、T-R0346、T-R0349 |
| AC-R0223 | T-R0221、T-R0335 |
| AC-R0224 | T-R0294、T-R0297、T-R0301、T-R0305、T-R0308、T-R0312、T-R0316、T-R0322、T-R0326、T-R0335 |
| AC-R0225 | T-R0235、T-R0236、T-R0240、T-R0333、T-R0335 |
| AC-R0226 | T-R0217、T-R0233、T-R0251、T-R0252、T-R0271、T-R0292、T-R0304、T-R0315、T-R0329、T-R0335、T-R0336、T-R0340、T-R0342 |

## tasks.md索引

| 見出し | 開始行 | 終了行 |
| --- | ---: | ---: |
| フェーズ0 版の宣言（commit 0） | 45 | 68 |
| フェーズ1 R02 actionlintとYAMLの構造比較（commit 1） | 70 | 95 |
| フェーズ2 R03 gitleaks（commit 2） | 97 | 125 |
| フェーズ3 R05 jq（commit 3） | 127 | 153 |
| フェーズ4 R04 段階1 s14、m02〜m05（commit 4） | 155 | 186 |
| フェーズ5 R04 段階2 m06、m07（commit 5） | 188 | 208 |
| フェーズ6 R04 段階3 m08（commit 6） | 210 | 229 |
| フェーズ7 R04 段階4 m09（commit 7） | 231 | 259 |
| フェーズ8 文書の最終確認（commit 8） | 261 | 281 |
| FR/NFRカバレッジ | 283 | 335 |
| ACカバレッジ | 337 | 366 |
| tasks.md索引 | 368 | 383 |
