# R02〜R05 clarify

調査対象は`spec.md`、現行のコード、`scripts/quality-gate.sh`、`.github/workflows/e2e-test.yml`、`mise.toml`、`mise.lock`である。
Docker、テスト、ツールの導入は実行していない。ツールの版は`gh api repos/<owner>/<repo>/releases/latest`で確かめた（2026-11-08）。

| ツール | 版 | 公開日 | 備考 |
| --- | --- | --- | --- |
| actionlint | v1.7.12 | 2026-03-30 | spec.mdの値と一致 |
| gitleaks | v8.30.1 | 2026-03-21 | spec.mdの値と一致 |
| bats-core | v1.14.0 | 2026-07-21 | spec.mdの値と一致 |
| jq | jq-1.8.2 | 2026-06-20 | spec.mdの値と一致 |
| yq（mikefarah/yq） | v4.54.2 | 2026-11-06 | 新規に確認。Q-R0202で採用 |

導入時に最新を確かめ直し、より新しい安定版があればplanで更新する。
`mise registry`で、5つのツールがすべてaquaのbackend（`aqua:rhysd/actionlint`、`aqua:gitleaks/gitleaks`、`aqua:bats-core/bats-core`、`aqua:jqlang/jq`、`aqua:mikefarah/yq`）で引けることを確かめた。

## 1. 解消した未決事項

利用者の決定はQ-R0201の(b)である。Q-R0202〜Q-R0209は推奨案、または次の表に理由を書いた案で決めた。

| ID | 質問 | 決定 | 理由 | 影響する要件 |
| --- | --- | --- | --- | --- |
| Q-R0201 | R04の範囲 | (b)。大きいファイル（`tests/m08`、`tests/m09`）も、bats-coreへ移す。一つのPRの中で段階を分け、各段階の後に検査の数と判定の一致を確かめる（2章） | 利用者の決定 | FR-R0216、FR-R0219、NFR-R0205、NFR-R0211 |
| Q-R0202 | YAMLの読み取りツール | `yq`（mikefarah/yq v4.54.2）。JSONは`jq`。3章 | `jq`はYAMLを読めず、PyYAMLを残すとFR-R0204に反する。`yq`はYAML 1.2の`on`キーを真偽値に変えないため、PyYAMLにあった`on`と`True`の分岐も要らない | FR-R0203、FR-R0204、FR-R0205、FR-R0206 |
| Q-R0203 | 導入方式 | A。5つとも`mise.toml`の`[tools]`で完全な版を固定し、`mise.lock`で4環境のURLとSHA256を固定する。4章 | R01で確立済みの方式である。`mise registry`で5つともaquaのbackendで引ける。自前の取得用シェルを作らずに済む（NFR-R0201） | FR-R0228、FR-R0229、NFR-R0202、NFR-R0209 |
| Q-R0204 | INT/TERMの実機検査と`exit`の扱い | 信号の実機検査は、中身を書き直さない。`exit`を使う検査は、`run`でサブシェルに隔離する。6章 | Issueの対象外に従う。`run`は呼び出しをサブシェルで実行するため、`exit`が`@test`全体を止めない | FR-R0219、FR-R0222 |
| Q-R0205 | CIのstepの順序と上限 | 5章。`shellcheck`、`actionlint`、`gitleaks`、`unit`の順。上限は`actionlint`が2分、`gitleaks`が2分 | 軽く、Dockerを使わない検査を先に置き、失敗したらDockerを動かさない。上限は、R01と同じく実測が1分未満の見込みに対して余裕を持たせる。実測で見直す（planで確定） | FR-R0201、FR-R0207、FR-R0208、NFR-R0205 |
| Q-R0206 | gitleaksの規則 | 既定の規則は使わない（`[extend] useDefault`を書かない）。独自の規則だけを置く。7章 | 既定の規則は、置き換え前に無かった検査で、誤検知の除外が増える。検査の強さは置き換え前と同じにする | FR-R0209、FR-R0210、FR-R0211 |
| Q-R0207 | gitleaksの検査対象 | 追跡対象のファイル全体を対象にする。ただし規則を2段にする。置き換え前の11ファイルには、置き換え前と同じ文字列の規則を使う。それ以外には、値の形に絞った規則を使う。7章 | 追跡対象の全ファイルへ文字列だけの規則を使うと、`specs/`の文書が`arn:aws`の語を説明として含み、恒常的に検出される。2段にすれば、既存の範囲を弱めずに、範囲を広げられる | FR-R0210、FR-R0211、NFR-R0206 |
| Q-R0208 | `tests/m06`と`tests/m07`の扱い | R04の対象に含める（大きいファイルの一部） | Q-R0201の(b)で、大きいファイルを移す。`tests/m06`（595行）と`tests/m07`（690行）は中間の規模で、段階の2に置く | FR-R0216 |
| Q-R0209 | 作業の単位 | 一つのPR。フェーズごとにcommitする。8章 | 利用者の提案。PR本文は`Closes #34 #35 #36 #37` | NFR-R0211 |

## 2. R04の段階の分け方（Q-R0201）

大きいファイルも含めて、bats-coreへ移す。ただし、一つのPRの中で、小さいファイルから大きいファイルの順に段階を分ける。
各段階の後に、検査の数と判定が移行の前後で同じであることを確かめる。確かめてから次の段階へ進む。

| 段階 | 対象 | 行数 | 検査の数（現状の`check`系の呼び出し） | 確かめること |
| --- | --- | --- | --- | --- |
| 1 | `tests/s14-taskdef-contract.sh`、`tests/m02-routing-smoke.sh`、`tests/m03-wiremock-scenarios.sh`、`tests/m04-test-client.sh`、`tests/m05-proxy-integration.sh` | 168、67、138、98、82 | 5、0、8、0、0（m02、m04、m05は`check`関数を持たない直列のスクリプト。3〜5の確認が連続する） | 旧の検査名と新の`@test`名の対応表。件数の一致。成功の入力と、壊した入力の両方で、旧と新の判定が同じ |
| 2 | `tests/m06-client-resilience.sh`、`tests/m07-scenario-isolation.sh` | 595、690 | m06は`expect`、m07は19 | 段階1と同じ。加えて、`expect`の（検査名、期待出力、期待終了コード）の3つを、`@test`の中で全て保つ |
| 3 | `tests/m08-e2e-suite.sh` | 1118 | 30 | 段階1と同じ |
| 4 | `tests/m09-execution-and-ci.sh` | 3950 | 未確認（仮の数字。静的な行数の数え直しは227、本表の旧の記載は234。実機の旧の出力で、モード別の実行時の件数を確定する。plan.md 6.3節、tasks.mdのT-R0316） | 段階1と同じ。`unit`、`smoke`、`contract`の3つの入口で、それぞれの件数が一致する |

検査の数と判定を確かめる方法は、次のとおりとする。

| 項目 | 方法 |
| --- | --- |
| 移行前の記録 | 段階を始める前に、旧のファイルを実行し、検査名と判定（PASS/FAIL）の一覧、件数、終了コードを`$KIROCREW_SCRATCH`に保存する。コミットには含めない |
| 対応表 | 旧の検査名と新の`@test`名の対応表を、planに残す。旧の名前を`@test`の名前にそのまま使い、対応を機械的に確かめられるようにする |
| 件数の一致 | `bats --count`の値と、旧の件数が一致する。ずれたら次の段階へ進まない |
| 判定の一致 | 成功の入力で全て通る。壊した入力（契約を壊した定義、クォートを外した値など）で、旧と同じ検査が落ちる |
| 実行時間 | 段階ごとに、旧と新の実行時間を記録する（NFR-R0205） |
| Dockerを使う検査 | 段階1のm02〜m05と、m09の`smoke`はDockerを使う。実行できる環境（CI、利用者の端末）で確かめる。実行できない環境で確かめたことは「未確認」と書く |

追加する要件を次に置く（既存の番号は変えない）。

| ID | 要件 |
| --- | --- |
| FR-R0231 | R04は、2章の4段階で進める。各段階の最後に、検査の数と判定の一致を確かめ、結果を記録する。一致しない場合は、その段階を直してから次へ進む |
| FR-R0232 | 旧の入口（`sh tests/<ファイル> [unit\|smoke\|contract]`）は、段階の後も同じ名前、同じ引数、同じ終了コードで動く。入口は、batsを呼ぶ薄い入口とする。`sh`で呼ばれたときも、内部でbashとbatsを使う。モードの絞り込みはbats-coreのタグ（`# bats test_tags=unit`など）で行う |

## 3. YAMLの読み取り（Q-R0202）

`yq`を採る。理由は2つある。`jq`は`.yml`を読めず、YAMLをJSONへ変換する別の手段が要る（その手段が`yq`自身になる）。PyYAMLを残すと、無いときにSKIPする分岐が残り、FR-R0204に反する。

| 項目 | 決定 |
| --- | --- |
| 版 | v4.54.2（mikefarah/yq、2026-11-06、確かめた日付は2026-11-08） |
| 導入 | `mise.toml`の`[tools]`に`yq = "4.54.2"`。`mise.lock`に4環境のURLとSHA256 |
| 実行 | 品質ゲートとbatsは、miseが入れた実体（`mise which yq`）で動かす。PATH上の別の`yq`は使わない（R01と同じ方針） |
| 使い分け | YAMLを読む箇所は`yq`、JSONを読む箇所は`jq`。同じファイルを2つのツールで読まない |

`jq`で足りる範囲と、`yq`が要る範囲は次のとおりとする。

| 読む対象 | ツール | 例 |
| --- | --- | --- |
| `.github/workflows/e2e-test.yml`（YAML） | `yq` | `yq -e '.permissions == {"contents": "read"}' <file>`、`yq '.jobs.e2e.steps[].name'`、`.on.push.branches`、`.jobs.e2e.steps[] \| select(.uses) \| .uses` |
| `wiremock-scenarios/mappings/*.json`と`__files/*.json`（JSON） | `jq` | `jq -e . <file>`（JSONとして読めるか）、`jq -e '.request.method and .request.urlPath and .response.status' <file>` |
| `ecs/task-definition.template.json`（JSON） | `jq` | キーの値の取り出し |
| `scripts/e2e-taskdef.py`と`scripts/scenario-lib.sh`の複雑な整合検査 | 変えない | python3のまま（FR-R0226） |

`yq -e`は、結果が`null`または`false`のときに終了コード1で終わる。したがって「式が真であること」を判定に使える。
空の結果を成功に数えないため、取り出しには`-e`を付ける（FR-R0227の「空の結果やnullの扱い」を、既定で失敗とする）。

追加する要件を次に置く。

| ID | 要件 |
| --- | --- |
| FR-R0233 | YAMLの読み取りは`yq`（v4.54.2）、JSONの読み取りは`jq`（1.8.2）とする。`yq`は`mise.toml`と`mise.lock`で固定し、`mise which yq`の実体で動かす。結果の判定には`-e`を付け、`null`と`false`を失敗にする |

## 4. 導入方式（Q-R0203）

R01の`mise.toml`と`mise.lock`を拡張する。`mise.toml`に置くのは`min_version`と`[tools]`だけとする（NFR-R0109、NFR-R0209）。

`mise.toml`の追加は次の形にする。版は完全な版だけを書き、範囲指定と`latest`は使わない。

| ツール | `mise.toml`の記述 | backend（`mise registry`で確認） |
| --- | --- | --- |
| actionlint | `actionlint = "1.7.12"` | `aqua:rhysd/actionlint` |
| gitleaks | `gitleaks = "8.30.1"` | `aqua:gitleaks/gitleaks` |
| bats | `bats = "1.14.0"` | `aqua:bats-core/bats-core` |
| jq | `jq = "1.8.2"` | `aqua:jqlang/jq` |
| yq | `yq = "4.54.2"` | `aqua:mikefarah/yq` |

`mise.lock`の扱いは次のとおりとする。

| 項目 | 決定 |
| --- | --- |
| 作成 | 5つを足した後、`mise lock`で更新する。linuxとmacOSの、x64とarm64の4環境のURLとSHA256を記録する |
| レビュー | 差分が、各ツールの公式のGitHubリリースのURLと、そのSHA256だけであることを確かめる。`checksum_source`が`mise-versions`のものは、公式リリースの`checksums`ファイルと照合する |
| 更新 | 版を上げるときだけ`mise lock`を実行し、差分をレビューする。`mise install`は`--locked`で動かす |
| 導入の確認 | planで実際に5つを導入し、4環境のlockに載ること、`bats`が実行できること（シェルスクリプトの配布物であること）、jqの版の表記（`jq-1.8.2`と`1.8.2`）が通ることを確かめる。載らないツールが出たときだけ、そのツールに限って別の導入（spec.md 5.2のC案）を採り、理由を記録する |
| CI | 既存の`jdx/mise-action`（コミットSHAで固定済み）の`install_args`を、`--locked shellcheck`から`--locked`（`mise.toml`の全ツール）に改める。mise本体の版とSHA256、`cache: false`、`env: false`はそのまま |
| 品質ゲート | 既存の`shellcheck_gate`と同じ形で、`actionlint`、`gitleaks`、`bats`、`jq`、`yq`の期待する版を`mise current`で得て、`mise which`の実体の`--version`と照合する。自動の導入を止める環境変数と`MISE_LOCKED=1`は、mise を呼ぶ各コマンドに付ける。重複を避けるため、版の照合は1つの関数にまとめる |

## 5. CIのstepの順序と上限（Q-R0205）

actionlintとgitleaksは、ローカルの品質ゲートとCIの両方に入れる。

| 項目 | 決定 |
| --- | --- |
| CIの順序 | checkout、mise-action、`shellcheck`（3分）、`actionlint`（2分）、`gitleaks`（2分）、`unit`（3分）、`test-ci`（10分）、`smoke`（8分）、`contract`（5分）、`collect`、upload、`stop` |
| 理由 | Dockerを使わず軽い検査を先に置き、失敗したら以降を動かさない。`shellcheck`、`actionlint`、`gitleaks`の順は、R01のstepの後ろに足す形で、既存の順序を変えない |
| bats | 別のstepは作らない。`unit`、`smoke`、`contract`の既存のstepが、薄い入口（FR-R0232）を通してbatsを呼ぶ。step名とjob名`e2e`は変えない |
| 上限 | `actionlint`は2分、`gitleaks`は2分。どちらも1分未満で終わる見込みで、2倍以上の余裕を持たせる。実測値で見直す（planで確定）。jobの上限15分は変えない。stepの`timeout-minutes`は上限であり、合計はjobの15分を超え得る。通常の実測は約212秒で、追加分を含めても15分に収まるかをplanで確かめる |
| ローカルの品質ゲートの順序 | 共通ゲート（`git diff --check`）、`shellcheck`、`actionlint`、`gitleaks`、Markdownゲート、M02〜M08、S14、M09の順。`actionlint`と`gitleaks`は、変更範囲に関わらず毎回実行する（`shellcheck`と同じ） |
| 実行の仕組み | ローカルは`mise which`の実体で実行する。CIは`mise which`の実体を使うか、mise-actionが入れたPATHを使うかを、planで`shellcheck`のstepと同じ形にそろえる |
| workflowの変更範囲 | FR-R0207のとおり、追加するstepだけを変える。追加する`run:`は式を含めない。`uses:`は増やさない（NFR-R0208） |

## 6. INT/TERMの実機検査と`exit`（Q-R0204）

### 6.1 信号の実機検査

Issueの対象外に従い、smokeの信号ケース（実機のINT/TERM）は書き直さない。

| 項目 | 決定 |
| --- | --- |
| 対象の特定 | planで、`kill -INT`、`kill -TERM`、Pythonの`signal.SIGINT`/`signal.SIGTERM`を使う検査を一覧にする。現状の該当箇所は、`tests/m07`、`tests/m08`、`tests/m09`にある（Pythonで子プロセスへ信号を送る関数と、`lib_call`を介して`kill -INT $$`/`kill -TERM $$`を実行する検査） |
| 扱い | 該当する検査の本体（信号を送る処理と判定）は、字句のまま移し、書き直さない。呼び出しだけを`@test`にし、`run`で実行して終了コードを見る |
| 理由 | 信号の受け取りは、シェルの種類（`sh`とbash）と、背景起動での`SIGINT`の無視に左右される。書き直すと、判定の意味が変わる恐れがある |
| 先頭の検査 | `tests/m09`の冒頭にある「`SIGINT`が無視されたまま起動された場合に止める」処理（22〜29行）は、batsの`setup_file`に移し、同じ文言で失敗させる |
| 文書 | 信号の検査を字句のまま保つ理由と、実行の前提（前面のシェルで実行する）を`docs/ローカル実行とCI.md`に書く（FR-R0219、AC-R0214） |

### 6.2 `exit`を使う検査

| 項目 | 決定 |
| --- | --- |
| `@test`の本体 | `exit`を呼ぶ関数は、`run <関数>`で呼ぶ。`run`は呼び出しをサブシェルで実行するため、`exit`は`@test`全体を止めない。終了コードは`$status`で判定する |
| スクリプトの`exit` | `exit`で終わる旧のスクリプト（`tests/m02`〜`m05`、`tests/s14`の冒頭の`trap`と末尾の`exit 0`/`exit 1`）は、`setup_file`と`teardown_file`（`trap cleanup EXIT`の置き換え）と、`@test`の失敗で表す |
| 後始末 | `trap cleanup EXIT`（`INT`と`TERM`を含む）の役割は、`teardown_file`で担う。ただし`INT`/`TERM`で`teardown_file`が走らない場合に備えて、後始末（コンテナの削除）は、品質ゲートの`managed_check`が残存を確かめる既存の仕組みで担保する |
| 終了コード | `bats`の終了コードは、1件でも失敗すれば1以上。入口が`bats`の終了コードをそのまま返す（FR-R0222） |

追加する要件を次に置く。

| ID | 要件 |
| --- | --- |
| FR-R0234 | 信号の実機検査（INT/TERM）の本体は、字句のまま移し、書き直さない。呼び出しだけを`@test`にする。対象の一覧をplanに残し、移行の前後で同じ検査が同じ判定になることを確かめる |
| FR-R0235 | `exit`を使う処理は、`run`でサブシェルに隔離する。`trap cleanup EXIT`は`teardown_file`に置き換える。後始末の漏れは、品質ゲートの`managed_check`で検出する |

## 7. gitleaksの規則（Q-R0206、Q-R0207）

### 7.1 規則

既定の規則は使わない。`.gitleaks.toml`に、独自の規則だけを置く。規則は2段にする。

| 段 | 対象のファイル（`path`） | 規則 | 目的 |
| --- | --- | --- | --- |
| 1（既存の範囲） | 置き換え前の11ファイル（FR-R0210に列挙）に限る | 12桁の数字（`[0-9]{12}`）、`arn:aws`、`AKIA`。置き換え前の`grep -E`と同じ文字列で、同じ強さ | 置き換え前より弱くしない |
| 2（広げた範囲） | 追跡対象のファイル全体（1段の11ファイルを含む。重複した検出は許す） | 値の形に絞った規則: ARNは`arn:aws`に続くパーティション、サービス、リージョン、12桁のアカウントの並び。アクセスキーは`AKIA`/`ASIA`に続く英大文字と数字の16文字。12桁の数字は、`account`や`aws`などの語が近くにある場合 | `specs/`の文書が`arn:aws`の語を説明として含んでも、恒常的に検出されないようにする |

正規表現の最終形は、planで書き、AC-R0208の壊した入力で確かめる。次の方針を守る。

- `.gitleaks.toml`のファイル自身が規則の文字列を含むため、1段の規則の`path`は11ファイルに限る。`.gitleaks.toml`は11ファイルに含まれない。
- 検査用の値は、実在しない値を実行時に組み立てる（NFR-R0206）。ファイルに固定の識別情報を書かない。
- 規則の`description`に、置き換え元（`t_doc_has_no_identity_values`、`unit_doc`）を書く。

### 7.2 検査の実行

| 項目 | 決定 |
| --- | --- |
| 対象 | 追跡対象のファイルの作業ツリー。gitleaksの履歴の走査（`git`サブコマンド）は使わない。置き換え前の検査が作業ツリーの現在の内容を見ていたため |
| 実行 | `gitleaks dir`に`--config .gitleaks.toml`、`--redact`、`--no-banner`、`--exit-code 1`を付ける。`gitleaks dir`が`.gitignore`を尊重しないときは、`node_modules/`と`e2e-logs/`（追跡対象でない生成物）だけを、planで規則の`allowlist`（パスと理由つき）に書く。この2つ以外のパスの除外は書かない |
| 出力 | `--redact`で、検出した値を出さない（FR-R0213） |
| 終了コード | 検出があれば1、なければ0。品質ゲートはこの終了コードを反映する。`\|\| true`で握りつぶさない |

`gitleaks dir`が`.gitignore`を尊重するかは、導入後に実機で確かめる（未確認）。

### 7.3 誤検知の除外

| 項目 | 決定 |
| --- | --- |
| 書き方 | 各規則の`[[rules.allowlists]]`に、1件ずつ書く。`description`に理由を書く。除外は`paths`（ファイル）と`regexes`（該当の文字列）を`condition = "AND"`で絞る |
| 禁止 | ファイル全体を全規則から外す除外、全規則に効く`[allowlist]`（グローバル）、`stopwords`による一括の除外は使わない |
| 候補 | `tests/m07`、`tests/m08`、`tests/m09`、`scripts/e2e-lib.sh`は、検査の入力として、これらの文字列を含む可能性がある。段階2の規則では、これらは1段の11ファイルに含まれないため、検出されるかをplanで実測する。検出された行だけを、行の文字列で絞って除外する |
| 方針の優先順位 | 先に、実行時に値を組み立てる形（文字列を連結して組み立てる）に直せるかを確かめる。直せない行だけを、個別の除外にする。1段の11ファイルの検出は、原則として除外せず、ファイルの側を直す |
| 一覧 | 除外の全件（規則、パス、文字列、理由）を、planの表に列挙する（AC-R0209） |

`swsc_mask`と`swsc_collect_scrub`は変えない（FR-R0214）。

追加する要件を次に置く。

| ID | 要件 |
| --- | --- |
| FR-R0236 | `.gitleaks.toml`の規則は2段にする。1段は、置き換え前の11ファイルに`path`で限り、置き換え前と同じ文字列で検出する。2段は、追跡対象の全体（1段の11ファイルを含む）に、値の形に絞って検出する |
| FR-R0237 | gitleaksは`gitleaks dir`で作業ツリーを走査し、`--redact`を付ける。履歴の走査は行わない。`.gitignore`を尊重しないときだけ、追跡対象でない生成物のパス（`node_modules/`、`e2e-logs/`）を、理由つきで除外する |

## 8. 作業の単位（Q-R0209）

一つのPRで進める。PR本文は`Closes #34 #35 #36 #37`とする。commitはフェーズごとに分ける。順序はR02、R03、R05、R04とする。

| commit | 内容 | 順序の理由 |
| --- | --- | --- |
| 0 | `mise.toml`と`mise.lock`に5つのツールを足す。`.github/workflows/e2e-test.yml`の`install_args`を`--locked`にする | 版の宣言を先頭に置く（R01と同じ）。以降のcommitが、同じ版で動く |
| 1（R02） | actionlintの実行（品質ゲート、CI）。`t_wf_*`のYAML構造比較への置き換え。PyYAMLの分岐の削除 | 独立している |
| 2（R03） | `.gitleaks.toml`、gitleaksの実行（品質ゲート、CI）。`t_doc_has_no_identity_values`と`unit_doc`の識別情報の部分の置き換え | 独立している |
| 3（R05） | JSONの単純な取り出しをjqへ置き換え（`tests/m03`、`tests/m07`など） | batsへ移す前に置き換え、移行で同じ検査を二度書き換えない |
| 4〜7（R04） | 2章の段階1〜4を、1段階1commit | 小さいファイルから大きいファイルの順 |
| 8 | 文書の最終確認（`AGENTS.md`、`docs/ローカル実行とCI.md`、README） | 実装と文書を一致させる |

文書は、各commitの変更に合わせて、そのcommitで更新する（FR-R0230）。最後のcommitは、全体の整合の確認と、実測値の記録に使う。

spec.mdの依存は「R04はR01に依存する。R05はR01〜R04に依存する」とある。本clarifyは順序をR05、R04にする。spec.mdのNFR-R0211の「依存の順（R01、R04、R05）」は、本clarifyの決定により「R01、R05、R04」と読み替える。理由は1つで、batsへ移す前に取り出し方を直し、同じ検査を二度書き換えないためである。依存は、実行できる順序（R01の後）としては成り立つ。

追加する要件を次に置く。

| ID | 要件 |
| --- | --- |
| FR-R0238 | commitは、2章と8章の順序で分ける。各commitの時点で、品質ゲートが通る。PR本文は`Closes #34 #35 #36 #37`とする |

## 9. 追加する受け入れ条件

既存の番号は変えない。追加する受け入れ条件を次に置く。

| AC | 完了条件 | 対応要件 | 確認方法 |
| --- | --- | --- | --- |
| AC-R0221 | R04の4段階の各段階で、検査の数と判定が移行の前後で一致する。結果が記録されている | FR-R0231、FR-R0216 | 段階ごとの対応表、件数、壊した入力での判定の一致 |
| AC-R0222 | 旧の入口（`sh tests/<ファイル> [unit\|smoke\|contract]`）が、同じ引数と同じ終了コードで動く | FR-R0232 | 各入口を実行し、終了コードを比べる |
| AC-R0223 | `yq`（v4.54.2）が`mise.toml`と`mise.lock`で固定され、YAMLの契約の検査に使われている。PyYAMLを使う箇所が無い | FR-R0233、FR-R0204 | `grep`で`import yaml`が無いこと。`mise which yq`の`--version` |
| AC-R0224 | 信号の実機検査が字句のまま移され、移行の前後で同じ判定になる。一覧がplanにある | FR-R0234 | 該当の検査の差分が、呼び出しの形の変更だけであること |
| AC-R0225 | `.gitleaks.toml`の規則が2段で、1段が11ファイルに限られている。グローバルな除外が無い | FR-R0236、FR-R0237、FR-R0211 | `.gitleaks.toml`の差分。除外の全件の一覧 |
| AC-R0226 | commitが2章と8章の順序で分かれている | FR-R0238 | `git log`の一覧 |

## 10. plan で決める事項

次の事項は、planで実測または実機の確認を経て決める。

| 項目 | 確かめる内容 |
| --- | --- |
| mise | 5つのツールの導入。`mise lock`が4環境を記録できるか。jqの版の表記（`1.8.2`と`jq-1.8.2`）が通るか。batsがaquaのbackendで入るか。ここで載らなければ、そのツールだけ個別の導入（spec.md 5.2のC案）を検討する |
| gitleaks | `gitleaks dir`が`.gitignore`を尊重するか。2段の規則の正規表現の最終形。除外が要る行の実測（`tests/m07`、`tests/m08`、`tests/m09`、`scripts/e2e-lib.sh`）。出力に値が出ないこと |
| actionlint | 現在のワークフローで指摘が出るか。出た場合の修正か、個別の除外か（`-ignore`の書き方）。`shellcheck`が入っていれば、`run:`の中のシェルも検査されるため、`.shellcheckrc`との関係を確かめる |
| bats | `.bats`ファイルをshellcheckの対象に含めるか（`-s bats`が使えるか）。含める場合の`git ls-files`の条件。bashの前提（`sh`の入口から呼ぶとき）をmacOSとubuntuで確かめる。タグ（`unit`、`smoke`、`contract`）の付け方 |
| 補助ライブラリ | `bats-support`と`bats-assert`は使わない。`run`と`[ ... ]`、`$status`、`$output`で足りるため。これらはGitの配布物で、mise（aqua）で固定しにくく、依存が増える。足りない箇所が出たら、planで版を固定して導入するかを決める（FR-R0218） |
| 実測 | actionlint、gitleaks、batsの実行時間、段階ごとの旧と新の実行時間、CIのjob全体が15分に収まるか（NFR-R0205） |
| 信号の検査 | 該当の検査の完全な一覧（2つの種類: `lib_call`経由の`kill`と、Pythonの`signal`） |
| Docker | 段階1のm02〜m05とm09の`smoke`の確認は、Dockerの使える環境（CI、利用者の端末）で行う |

利用者の判断が要る事項は、残っていない。

## 11. 結果

- Q-R0201〜Q-R0209の9件を、全て決めた。Q-R0201は利用者の決定(b)、残りは推奨案または理由を書いた案である。
- Q-R0207は、spec.mdの推奨（追跡対象の全ファイルを同じ規則で検査）を変え、規則を2段にした。理由は7.1に書いた。
- 追加した要件は、FR-R0231〜FR-R0238の8件と、AC-R0221〜AC-R0226の6件である。既存の番号と、spec.mdは変えていない。
- 実行していないこと: ツールの導入、Docker、テスト、`gitleaks dir`と`.gitignore`の関係の確認。planで確かめる。
- 決定の追記（analyze.mdの対応）: 2段の対象は、追跡対象の全体（1段の11ファイルを含む）とする。7.1節とFR-R0236の
  「11ファイルを除く」の記述を、plan.md 8.1節の設計に合わせて直した。重複して検出しても、検査は弱くならない。
- 決定の追記: spec.mdの「4つのツール」（FR-R0228、NFR-R0202など）は、yqを加えた5つのツールに読み替える。
- 決定の追記: m09の検査の数（227と234）は、どちらも仮の数字である。実機の旧の出力でモード別の実行時の件数を確定するまで、
  一方を正としない。
