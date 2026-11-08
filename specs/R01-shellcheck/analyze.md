# R01 analyze

## 1. 検査範囲

`spec.md`、`clarify.md`、`plan.md`、`tasks.md`を全文確認した。実装の現状は、`scripts/quality-gate.sh`、
`.github/workflows/e2e-test.yml`、`tests/m09-execution-and-ci.sh`の`t_wf_*`・`t_gate_*`・`gate_*`、
`AGENTS.md`、`sc.txt`、`r01-plan-facts.md`、`r01-mise.toml.sample`、`r01-mise.lock.sample`と照合した。
Dockerとテストは実行していない。ソースは変更していない。

読み取りで実行したのは、shellcheck 0.11.0（`-s sh -S style`）だけである。
`.shellcheckrc`と同じ4設定を、リポジトリ外の一時ファイルで渡して実行し、実行後に削除した。

| 実行 | 結果 |
| --- | --- |
| m09以外の19ファイル | 43件、21.8秒 |
| `tests/m09-execution-and-ci.sh` | 112件、52.6秒 |

## 2. 指摘一覧

| ID | 重要度 | 場所 | 内容 | 根拠 | 対応 |
| --- | --- | --- | --- | --- | --- |
| H-01 | High | `spec.md` FR-R0102、`clarify.md` Q-R0110、`plan.md` 1.1・3節 | 要件と決定が`mise exec -- shellcheck`で実行すると定め、planは`mise exec`を使わず`mise which`の実体を実行すると決めた。要件と実装が食い違う。tasksとplan 11章は、要件の文面を直すタスクを持たない。 | `spec.md` FR-R0102は`mise exec -- shellcheck`と`mise exec -- shellcheck --version`を明記する。`clarify.md` Q-R0110も同じである。`r01-plan-facts.md`は、未導入のとき`mise exec`がPATH上の別のshellcheckで成功し、FR-R0102の「別の経路は使わない」を守れないと記録している。 | implementの前に、`spec.md` FR-R0102と`clarify.md` Q-R0110（結論欄を含む）を`mise which`の実体の実行へ改める。理由に`r01-plan-facts.md`の事実を書く。`plan.md` 11章のFR-R0102の行も合わせる。 |
| H-02 | High | `plan.md` 5.2節、`spec.md` FR-R0115、`r01-plan-facts.md`「jdx/mise-action」 | FR-R0115は、導入の`--locked`をActionの入力か`MISE_LOCKED=1`で明示し、既定の挙動に頼らないことを求める。planは`MISE_LOCKED=1`を`shellcheck`stepの`run:`の先頭に置く。導入はその前のmise-action stepが行うため、この指定は導入に効かない。結果として導入の`--locked`は、`mise.lock`があれば自動で足されるActionの既定に頼ることになる。 | `plan.md` 5.2節の「`--locked`は…既定の挙動に頼らず…`run:`の行の先頭に書く」。facts表は、Actionが`install_args`に`--locked`が無ければ足すと記録している。`with:`は`install_args: shellcheck`だけである。 | mise-action stepの`with:`を`install_args: --locked shellcheck`にして明示する。`${{`は使わない。`env:`は増やさない（`t_wf_dummy_credentials_are_workflow_env_only`が`env:`の行を1つに固定している。`install_args`はこの検査に掛からないことを確認済み）。`t_wf_each_step_runs_its_command`の更新に、`install_args`が`--locked`を持つ確認を加える（`tasks.md` T-R0131、T-R0133）。`plan.md` 5.2節と10節の記述を直す。実際に受理される形は、初回CIの前に`jdx/mise-action`のソースで確かめる。 |
| M-01 | Medium | `tasks.md` T-R0114〜T-R0116、T-R0125〜T-R0127 | 利用者が選んだ修正または除外を、コードへ反映するタスクがない。T-R0115とT-R0126は「選ぶ」「記録する」だけである。一覧が空でないと、19ファイルまたは20ファイルが0件にならず、T-R0118とT-R0127が満たせない。T-R0116のsmokeが決定の前に走るため、反映後に再実行が要る。 | `plan.md` 4.5節の手順は、決定が出るまでコミットを進めないと定めるが、反映の担当と順序を定めない。 | 決定の後に「決定の反映」のタスクを置く（実装サブエージェント、一覧の行だけを対象）。smokeとunitは反映の後に実行する順にする。一覧が0件なら省略できると書く。 |
| M-02 | Medium | `tasks.md`全体、`plan.md` 11章、`spec.md` 6章 | ACの対応表がplanにもtasksにもない（AC-R0107とAC-R0108が本文に出るだけ）。AC-R0104は、指摘を含む一時ファイルでshellcheckの失敗が終了コードへ反映されることの確認を求めるが、T-R0134は構文エラー3種と未導入・版違いだけを扱い、構文エラー以外の指摘（未クォートの変数など）を扱わない。AC-R0109は、M02〜M09のunitとsmoke、CIの全体を求めるが、最終フェーズの確認はゲートの条件に依存する。 | `spec.md` 6章のAC-R0104の確認方法。`plan.md` 8.1節は「構文エラー、または未クォートの変数のような指摘」と書くが、`tasks.md` T-R0134は前者だけである。 | `tasks.md`のカバレッジ表にACの列を足す（本書5章の表を使える）。T-R0134に、構文エラー以外の指摘を含む一時ファイルで品質ゲートが非0になる確認を足す。T-R0147に、M02〜M09のunitとsmokeが最終の差分で通った記録を足す。 |
| M-03 | Medium | `plan.md` 3節、`tasks.md` T-R0132、`scripts/quality-gate.sh` | ゲートは`set -eu`で動く。`mise current`や`mise which`の失敗を`var=$(...)`で受けると、`FAILED:`のメッセージと導入手順を出す前にスクリプトが止まる。planの表は「空、または失敗なら`status=1`」と書くが、`if !`やOR結合で失敗を受ける指定がない。静的検査`t_gate_runs_shellcheck_with_pinned_options`は文字列の有無しか見ず、この経路を保証しない。 | `scripts/quality-gate.sh`の`set -eu`。`plan.md` 3節の表の2〜4行目。`plan.md` 7章の新しい検査の内容。 | T-R0132に、各取得を`if !`などで受け、導入手順付きの`FAILED:`を出してから`status=1`にする指定を書く。T-R0134の「mise無し」「未導入」「版違い」で、導入手順の表示を確認項目にする（すでにある）。 |
| M-04 | Medium | `plan.md` 5.2節・10節、`spec.md` FR-R0114、`tasks.md` T-R0145 | CIの`shellcheck`stepの上限は2分、ローカルの実測は約76秒である。今回の実測は、m09だけで52.6秒、残り19ファイルで21.8秒、合計約74秒だった。mise本体と`shellcheck`の取得も加わるが、これは別のstepにある。余裕は約40%で、CIが遅いと初回で上限に当たる。上限の見直しはフェーズ5（T-R0145）だが、フェーズ4のPRのCIが赤になる。 | 本書1章の実測。`plan.md` 10節の初回CIで実測する方針。`tasks.md` T-R0141とT-R0145。 | implementの前に、(a) 上限2分のまま初回を実測し、赤なら見直すと決める、または (b) `spec.md` FR-R0114と`tasks.md` T-R0131・T-R0133の上限を最初から3分にする、のどちらかを利用者に確認する。どちらでも、`timeout-minutes`の期待を固定するM09 unitのケース名と値を一貫させる。 |
| L-01 | Low | `plan.md` 4.2節、`tasks.md` T-R0108・フェーズ2見出し、`spec.md` 1.1節 | 最終の設定（`.shellcheckrc`の`external-sources=true`と`source-path=SCRIPTDIR`）で実行すると、`test-client/entrypoint.sh`のSC1091は消える。`source=`を足さなくても解消する。このため、実際の件数は総数155件、m09以外43件になる。`sc.txt`の156件と44件は、設定なしの実測である。 | 本書1章の実行結果。m09以外の19ファイルは43件で、SC1091の行がない。 | 件数の記録（`plan.md` 4.6節）に、基準が設定なしの156件であることを書く。T-R0108のSC1091は、`source=retry-lib.sh`の宣言が`.shellcheckrc`と合わせて意図どおりかを確認する扱いにする（宣言は残してよい）。 |
| L-02 | Low | `plan.md` 7章、`tasks.md` T-R0131 | ファイル全体に効く`# shellcheck disable=`（先頭のコメント）は、機械的に検出されない。新しい検査`t_shellcheck_config_and_mise_toml_are_restricted`は`.shellcheckrc`と`mise.toml`だけを見る。AC-R0107は`git grep`とレビューで確かめる。 | `plan.md` 7章の新しい検査の内容。 | 現状の運用（レビューで1件ずつ確認）で足りる。自前のチェック用シェルは作らない方針に従い、機械的な検出を足すなら、`git grep`を使う既存のunitの形に限る。 |
| L-03 | Low | `plan.md` 8節の表 | smokeと品質ゲートの実行主体が「エージェント」とだけ書かれ、サブエージェントと読める。`AGENTS.md`はDockerを使うsmokeと品質ゲートをメインエージェントが実行すると定める。`tasks.md`はメインにしており、矛盾はない。 | `AGENTS.md`「実装バッチの依頼」の「実機の検証」と「実行ルール」1。 | 表の語を「メインエージェント」に改める。 |
| L-04 | Low | `plan.md` 5.2節 | CIの`run:`の行で、環境変数の接頭辞が`git ls-files`にも付く。`git`には効かず、読みにくい。`$(...)`の中の`mise which`にだけ必要である。 | `plan.md` 5.2節の1行。既存の`t_wf_run_lines_have_no_expression_or_block_scalar`は式の記法とブロックスカラーだけを禁じ、`$(`は禁じていない。 | 3つの環境変数を、先頭の`git ls-files`ではなく、`$(...)`の中の`mise which shellcheck`だけに付ける。 |
| L-05 | Low | `tasks.md` T-R0103、T-R0104 | 照合結果の元の`r01-plan-facts.md`は`$KIROCREW_SCRATCH`にある。スクラッチはセッションの終了で消えるため、T-R0103で検証記録へ写す前に消えない順序にする。T-R0104で作るリポジトリ外の複製と`MISE_DATA_DIR`の一時ディレクトリは、削除の担当がT-R0106の「残した一時物」の記録だけである。 | `tasks.md`の進め方「各フェーズの記録タスクで削除し」。 | T-R0104の完了の確認方法に、一時ディレクトリを絶対パスで削除したことを加える。 |
| L-06 | Low | `plan.md` 1.1節・5.2節 | `sha256`はlinux-x64の値だけである。runnerがarm64に変わると、取得の検証が失敗して止まる（安全側）。mise-actionのstepに`timeout-minutes`がなく、job全体の15分が上限になる。 | `plan.md` 1.1節、5.2節の表。 | 現状はubuntu-24.04（x86_64）だけが前提であり、`docs/ローカル実行とCI.md`にその前提を書く。stepの上限は、実測の後に必要なら足す。 |

## 3. 要件との対応の確認

### 3.1 FR/NFRとplan、tasks

| 範囲 | planの対応 | tasksの対応 | 判定 |
| --- | --- | --- | --- |
| FR-R0101〜FR-R0115 | 11章に全IDがある | カバレッジ表に全IDがある | 取りこぼし・重複なし。FR-R0102はH-01、FR-R0115はH-02で修正が要る |
| NFR-R0101〜NFR-R0110 | 11章に全IDがある | カバレッジ表に全IDがある | 取りこぼし・重複なし |

### 3.2 AC

| AC | planの対応 | tasksの対応 | 判定 |
| --- | --- | --- | --- |
| AC-R0101 | 1.1節、5.5節、8節 | T-R0104、T-R0138 | 対応あり。macOSとLinuxは利用者の端末で未確認（計画に明記） |
| AC-R0102 | 3節、8.1節 | T-R0134 | 対応あり。H-01で要件の文面を直す |
| AC-R0103 | 5.2節 | T-R0133、T-R0141 | 対応あり |
| AC-R0104 | 3節、5.1節、8.1節 | T-R0132、T-R0134 | 構文エラー以外の指摘の確認が不足（M-02） |
| AC-R0105 | 8.1節 | T-R0134 | 対応あり |
| AC-R0106 | 4節 | T-R0127、T-R0129、T-R0139 | 対応あり |
| AC-R0107 | 4.1節、4.5節、4.6節 | T-R0117、T-R0128 | 対応あり |
| AC-R0108 | 4.1節 | T-R0117、T-R0128 | 対応あり |
| AC-R0109 | 6章、8節 | T-R0116、T-R0127、T-R0135、T-R0141、T-R0145 | 最終の記録が不足（M-02） |
| AC-R0110 | 2節、コミット5 | T-R0142〜T-R0144、T-R0147 | 対応あり |

### 3.3 clarifyの決定とplan

Q-R0101〜Q-R0111は、すべてplanに反映されている。Q-R0110だけが、`mise exec`の記述のまま残り、planと食い違う（H-01）。
「planで確かめること」の7項目（miseの導入、`jdx/mise-action`、`mise.lock`の初回の作成、backend、自動導入の設定名、CIの権限、ローカルのmise本体）は、
`plan.md` 1.1節、5.3節〜5.5節、10節に反映されている。macOSでのHomebrewによる導入は、未確認として10節に残っている。

### 3.4 `r01-plan-facts.md`との整合

| 事実 | planの記述 | 判定 |
| --- | --- | --- |
| `mise exec`がPATH上の別のshellcheckで成功する | `mise which`を使う（1.1節、3節） | 整合。ただし要件側が未更新（H-01） |
| `mise which`は未導入で終了コード1 | 3節の表で失敗 | 整合 |
| `exec_auto_install`と`auto_install`の既定はtrue | 環境変数3つを明示（3節） | 整合 |
| backendは`aqua:koalaman/shellcheck` | 既定を使う（1.1節） | 整合。`r01-mise.lock.sample`のbackendと一致 |
| 4環境のURLとSHA256 | `mise lock --platform`で記録（1.1節） | 整合。見本に4環境が揃い、`lockfile_version = 4`、`checksum_source = "mise-versions"`。`mise.toml`の見本は`plan.md` 2.1節と同一 |
| mise-actionのコミットSHA、`version`、`sha256` | 5.2節で指定 | 整合。linux-x64のSHA256も一致 |
| mise-actionは設定を自動で信頼する | 5.4節で限界と守りを明記 | 整合 |
| `cache`と`env`の既定はtrue | どちらも`false`（5.2節） | 整合。`env: false`の行は`^ *env:$`に一致せず、`env:`の数を数える既存の検査を壊さない |
| `--locked`は自動で足される | `MISE_LOCKED=1`を`run:`に置く | 不整合（H-02） |

## 4. 件数の確認

`sc.txt`の156件と実測（設定なし）が一致することを確認した。コード別・ファイル別の件数は、すべて`spec.md`、`plan.md`、`tasks.md`と合う。

| 確認項目 | 実測 | 記述 | 判定 |
| --- | --- | --- | --- |
| コード別（SC2016 42、SC1090 27、SC2031 26、SC2030 20、SC2329 15、SC2034 13、SC2012 4、SC2086 3、SC2043 2、ほか各1） | 一致 | `spec.md` 1.1節 | 一致 |
| m09の内訳（SC2016 39、SC1090 23、SC2031 20、SC2030 18、SC2329 9、SC2012 1、SC2015 1、SC2086 1 = 112） | 一致 | `plan.md` 4.4節、T-R0120〜T-R0124 | 一致。T-R0122の20件とT-R0123の19件で39件 |
| m09以外の内訳（合計44） | 一致 | `plan.md` 4.2節の表の合計44 | 一致 |
| ファイル別（m08 16、s14 8、e2e-lib 7、m06 4、m07 3、ほか各1） | 一致 | T-R0108〜T-R0113 | 一致。T-R0108は3件、T-R0109は3件、T-R0110は7件、T-R0111は8件、T-R0112は7件、T-R0113は16件で、合計44 |
| 最終設定での実測 | m09以外43件、m09 112件 | 44件と112件 | SC1091が1件減る（L-01） |
| `tasks.md`索引の行番号 | 見出しは27、43、64、85、104、121、151行 | 索引の開始行 | 一致 |

## 5. 順序、実行主体、バッチ

| 項目 | 判定 |
| --- | --- |
| 先に赤にする検査、実装、ゲート、コミットの順 | フェーズ4はT-R0131（赤）、T-R0132・T-R0133（緑）、T-R0134〜T-R0139（確認）、T-R0140（コミット）の順で適切。フェーズ1〜3は既存の検査が緑のまま保たれる設計で、赤にする検査はない（H-02で`--locked`の確認を足す） |
| 依存と直列化 | 同じファイルを触る実装タスクは、バッチ内で直列。B-1、B-2、C-1、C-2、D、Eの対象ファイルに重複はない |
| バッチの大きさ | 実装サブエージェントへの依頼は、Aが1件、B-1が3件、B-2が3件、C-1が3件、C-2が2件、Dが3件、Eが3件。3〜4タスクの規則に合う |
| 実行主体 | Dockerを使うsmoke、品質ゲート、レビューはメイン。実装サブエージェントはm09のunit（Dockerなし）までで、`AGENTS.md`に合う |
| 決定の反映 | 欠けている（M-01） |
| 最初の変更の期限 | `tasks.md`の進め方に5分と再試行しない条件がある |

## 6. 方針との照合

| 方針 | 判定 |
| --- | --- |
| 一般的なツールを優先し、自前のチェック用シェルを作らない | 合う。shellcheckとmiseを使い、導入用シェルを作らない（NFR-R0101）。新しいunitの検査は静的な確認で、Dockerとmiseを使わない |
| 版を固定する | 合う。shellcheckは`mise.toml`と`mise.lock`、mise本体は`version`と`sha256`、actionはコミットSHAで固定。`min_version`は下限で、CIの`version`が完全に固定する |
| 既存の検査を弱めない | 合う。壊れる4件は判定を保って更新し、2件は強化する（`plan.md` 7章）。`sh -n`の構文検査は、8.1節で同等性を確認する。`ecs/squid/*.sh`が新たに対象へ加わる |
| 後始末 | 概ね合う。一時ファイルの手順は8.1節と各フェーズの記録タスクにある。L-05の抜けがある |

## 7. 判定

| 重要度 | 件数 |
| --- | --- |
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 6 |

implementの前に解消すべき指摘は、H-01（要件と決定の文面を`mise which`へ改める）とH-02（CIの`--locked`を導入のstepで明示する）である。
M-01〜M-04は、`tasks.md`の修正で済むため、implementの前に反映することを勧める。M-04は利用者の判断が要る。
LowはCIの初回実測と文書の更新で扱える。

## 8. 利用者確認が必要な項目

- M-04: `shellcheck`stepの上限を、2分のまま初回を実測するか、最初から3分にするか。
- macOS（Colima）とLinuxでの`mise install --locked`の確認は、利用者の端末で行う（T-R0138）。
- 一時ファイルの扱い: 本書の作成で作った一時ファイル（リポジトリ外の設定と出力）は削除した。リポジトリには`analyze.md`だけを追加した。

## 9. 指摘への対応（2026-11-07）

`spec.md`、`clarify.md`、`plan.md`、`tasks.md`へ反映した。M-04の上限は、利用者の判断（2026-11-07）で最初から3分にした。
タスクはT-R0150〜T-R0155を追加し、合計55件になった。

| ID | 対応先 | 対応の内容 |
| --- | --- | --- |
| H-01 | `spec.md` FR-R0102・Q-R0110の行、`clarify.md` Q-R0110（結論欄と理由）・評価の記録、`plan.md` 11章FR-R0102、`tasks.md` T-R0150 | `mise exec`を使わず、`mise which shellcheck`の実体を実行し、期待する版は`mise current shellcheck`で得ると改めた。未導入の`mise exec`がPATH上の別のshellcheckで成功する理由を書いた。T-R0150で4つの文書の一致を確かめる |
| H-02 | `plan.md` 1.1節・5.2節・10節・11章FR-R0115、`spec.md` FR-R0115、`tasks.md` T-R0131・T-R0133・T-R0153 | mise-actionの`with:`に`install_args: --locked shellcheck`を書く形にした。`${{`と`env:`の追加はしない。`MISE_LOCKED=1`は品質ゲートに残した。`t_wf_each_step_runs_its_command`に`install_args`の確認を足した。初回CIの前にソースで確かめるT-R0153を足した |
| M-01 | `plan.md` 4.5節の手順5、`tasks.md` T-R0151（フェーズ2）・T-R0152（フェーズ3）・T-R0116・T-R0127 | 決定の後にコードへ反映するタスクを置き、smokeとunitは反映の後にした |
| M-02 | `plan.md` 12章、`tasks.md` ACカバレッジ表・T-R0154・T-R0155 | ACの対応表を反映した。構文エラー以外の指摘を含む一時ファイルの確認（T-R0154）と、最終の差分でのM02〜M09のunitとsmokeの記録（T-R0155）を足した |
| M-03 | `plan.md` 3節、`tasks.md` T-R0132・T-R0134 | `set -eu`で止まらないよう、`mise current`と`mise which`の取得を`if !`で受け、導入手順つきの`FAILED:`を出してから`status=1`にすると書いた。T-R0134で表示を確認する |
| M-04 | `spec.md` FR-R0114・Q-R0104の行、`clarify.md` Q-R0104、`plan.md` 5.2節・7節・10節・11章FR-R0114、`tasks.md` 進め方・T-R0131・T-R0133・T-R0145 | `timeout-minutes: 3`にした。根拠は実測約74秒（m09が52.6秒、残り19ファイルが21.8秒）、2分では余裕が小さいこと、利用者の判断である。M09 unitのケース名は`..._shellcheck3_unit3_...`にした |
| L-01 | `spec.md` 1節の現状の実測、`plan.md` 4.6節、`tasks.md` T-R0108・T-R0143 | 件数の基準（設定なし156件、最終設定155件、m09以外44件と43件）を注記した。SC1091は`source=`の宣言が意図どおりかの確認にした |
| L-02 | `spec.md` AC-R0107の確認方法、`plan.md` 8節の静的の行、`tasks.md` T-R0117 | ファイル全体の`disable=`は、`git grep`の列挙結果の各行が対象行の直前にあることをレビューで1件ずつ確かめる。自前の検査は作らない |
| L-03 | `plan.md` 8節の表 | 実行主体を「メインエージェント」に改めた |
| L-04 | `plan.md` 5.2節、`tasks.md` T-R0133 | 環境変数を`$(...)`の中の`mise which shellcheck`だけに付ける1行にした |
| L-05 | `tasks.md` 進め方のフェーズ1の説明・T-R0104 | 照合結果の転記（T-R0103）をスクラッチが消える前に行うと書いた。T-R0104に、一時ディレクトリを絶対パスで削除して記録する確認を足した |
| L-06 | `plan.md` 5.2節・10節、`tasks.md` T-R0133・T-R0143 | mise-actionのstepには`timeout-minutes`を付けず、実測の後に必要なら足すと決めた。`sha256`はlinux-x64だけで、ubuntu-24.04（x86_64）が前提であることを文書に書く |
