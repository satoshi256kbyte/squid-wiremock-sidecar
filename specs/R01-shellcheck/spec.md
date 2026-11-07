# R01 シェルの静的解析への shellcheck 導入仕様

## 1. 目的

`scripts/quality-gate.sh`のシェルの検査は、現在`sh -n`（構文の確認）だけである。
未使用の変数、クォートの漏れ、`set -e`の落とし穴、読み込み先の不整合は検出できない。
一般的なツールのshellcheckを版を固定して導入し、`sh -n`のループを置き換える。

本SpecはIssue #33（R01）に対応する。

前提は次のとおりとする。

| 項目 | 前提 |
| --- | --- |
| 方針 | 一般的なツールがあるときは自前のチェック用シェルを作らない。導入するツールは版を固定する |
| 実行環境 | CI（ubuntu-24.04）、ローカルのmacOS（Colima利用）、ローカルのLinux |
| 方言 | `shellcheck -s sh`でPOSIX shellとして検査する |
| 判定の維持 | 既存の検査の判定と終了コードを弱めない。`sh -n`が検出していた構文エラーは、置き換え後も失敗として検出する |
| 現状の実測 | shellcheck v0.11.0を`-s sh -f gcc`で下表の20ファイルへ実行した。結果は156件（error 0、warning 43、note 113） |

### 1.1 現状の実測

対象は`git ls-files`で得た次の20ファイルである。

| 区分 | パターン |
| --- | --- |
| スクリプト | `scripts/*.sh` |
| 検査 | `tests/*.sh` |
| Client | `test-client/*.sh` |
| Squid | `ecs/squid/*.sh` |

指摘コード別の件数は次のとおりである。

| コード | 件数 | 内容 |
| --- | --- | --- |
| SC2016 | 42 | シングルクォート内で式が展開されない |
| SC1090 | 27 | 動的な`source`先をたどれない |
| SC2031 | 26 | サブシェル内で変更した変数を別の場所で参照している |
| SC2030 | 20 | サブシェル内で変数を変更している |
| SC2329 | 15 | 呼ばれない関数、または間接的にだけ呼ばれる関数 |
| SC2034 | 13 | 未使用の変数 |
| SC2012 | 4 | `ls`の出力を処理している |
| SC2086 | 3 | 変数のクォートの漏れ |
| SC2043 | 2 | 1要素だけのループ |
| SC2154、SC2015、SC1091、SC1003 | 各1 | 未定義変数の参照、`A && B \|\| C`、読み込み先の不明、クォートの誤り |

ファイル別では`tests/m09-execution-and-ci.sh`が112件、`tests/m08-e2e-suite.sh`が16件、
`tests/s14-taskdef-contract.sh`が8件、`scripts/e2e-lib.sh`が7件で、残りは各1〜4件である。
この件数は導入時の実測であり、検査の重さ（severity）の下限や`.shellcheckrc`の設定で変わる。

## 2. 対象範囲

| 区分 | 対象 |
| --- | --- |
| 対象ファイル | `git ls-files '*.sh'`で得る追跡対象の全`.sh`（現在20件。下記の4区分と一致する） |
| 品質ゲート | `scripts/quality-gate.sh`の`sh -n`のループ |
| CI | `.github/workflows/e2e-test.yml`の`e2e`jobに、`unit`の前の`shellcheck`stepを追加する（Q-R0104） |
| 文書 | `AGENTS.md`の品質ゲートの表と条件付き設定の記述、`docs/ローカル実行とCI.md` |
| 版の宣言と導入 | リポジトリ直下の`mise.toml`（shellcheckの完全な版）と`mise.lock`（4つの環境のURLとSHA256）。`package.json`は変更しない。自前の導入用シェルは作らない（Q-R0105、Q-R0109） |
| 設定 | `.shellcheckrc`（`shell=sh`、`severity=style`、`external-sources=true`、`source-path=SCRIPTDIR`だけ。Q-R0102） |

現在の`sh -n`のループは`tests/*.sh`、`test-client/*.sh`、`scripts/*.sh`だけを対象にし、`ecs/squid/*.sh`を含まない。
置き換え後は、追跡対象の全`.sh`（現在は上表の4区分と同じ20件）へそろえる。

## 3. 機能要件

| ID | 要件 |
| --- | --- |
| FR-R0101 | shellcheckを、一般的なツールのmiseで、版とSHA256を固定して導入する。版は`mise.toml`に、URLとSHA256は`mise.lock`に一か所で宣言し、品質ゲートとCIは同じ版を使う。CIとローカル（macOS、Linux）の両方で導入手順を用意する |
| FR-R0102 | 品質ゲートとCIは、shellcheckを`mise exec -- shellcheck`で実行し、`mise.toml`と`mise.lock`で固定した版を使う。期待する版はmiseの出力（`mise current shellcheck`）から得て、`mise.toml`を自前で解析しない。miseが無い、shellcheckが未導入、または`mise exec -- shellcheck --version`の版が期待と異なるときは、成功扱いにせず、導入手順（miseの導入と`mise install --locked`）を示して失敗させる。PATH上の別の経路で入れたshellcheckは使わない。品質ゲートの実行では、miseの自動の導入を止め、`MISE_LOCKED=1`を明示して、`--locked`を通らない導入を起こさない（設定の正しい名前はplanで確かめる） |
| FR-R0103 | `scripts/quality-gate.sh`が対象ファイルへ`shellcheck -s sh -S style`を明示して実行し、`sh -n`のループを置き換える |
| FR-R0104 | 対象ファイルの集合は、`git ls-files -z '*.sh'`で得る追跡対象とする。パターンの展開は使わず、新しい`.sh`の追加が検査から漏れない |
| FR-R0105 | shellcheckが未導入のときは、成功扱いにせず、導入手順を示して失敗させる。Markdownゲートの依存未導入時の扱いと同じ方針にする |
| FR-R0106 | shellcheckの終了コードを品質ゲートの終了コードへ反映する。`\|\| true`などで失敗を握りつぶさない |
| FR-R0107 | 既存の指摘は、コードを修正するか、理由を書いた上で`# shellcheck disable=`で個別に除外する。除外には対象のコードと理由をその場に書く |
| FR-R0108 | 一括の除外をしない。ファイル全体や全ファイルへ効くdisableと、`.shellcheckrc`でのコード単位の無効化は使わない。`.shellcheckrc`が持つのは`shell`、`severity`、`external-sources`、`source-path`だけである |
| FR-R0109 | 動的な`source`先の指摘（SC1090、SC1091）は、読み込み先が決まる行に`# shellcheck source=<リポジトリ内の相対パス>`を書いて解消する。複数の候補や一時ファイルを読む行は、`source=/dev/null`と理由を書く |
| FR-R0110 | 検査する指摘の重さは`style`（note以上の全件）とし、品質ゲートの呼び出しと`.shellcheckrc`の両方で明示する |
| FR-R0111 | 修正の範囲は、指摘を解消する最小の変更に限る。判定、終了コード、出力の契約を変えない。修正と個別除外の基準はclarify.mdのQ-R0107に従う。迷う行は、原則は理由付きの個別除外とする。安全に関わる指摘（SC2086、SC2046、SC2016、SC2012）で迷う行は、判定、終了コード、出力を変えない書き方に修正する。それができない行は、除外せずに利用者の判断に上げる。SC2016とSC2012の除外は、根拠（意図した展開か、検査が管理する入力か）をAC-R0107のレビューで1件ずつ確かめる。SC2086とSC2046を除外できるのは、値の出どころが固定の文字列か検査の中で作った値と示せ、空白とグロブの文字を含まないと確かめた場合だけとし、理由に出どころを書く |
| FR-R0112 | `sh -n`が検出していた構文エラーを、shellcheckが同等に検出することを確認する。意図的な構文エラーを持つ一時ファイルで失敗を確認する。一時ファイルは`git ls-files`の対象に入らないため、`git add -N`で一時的にindexへ入れてから品質ゲートを実行し、確認後に`git reset -- <一時ファイルのパス>`でその1つだけをindexから外し、ファイルを削除する（パスを指定しない`git reset`は、利用者がステージした変更まで外すため使わない） |
| FR-R0113 | `AGENTS.md`の品質ゲートの表と`docs/ローカル実行とCI.md`を、新しいゲートの内容、導入手順、版の固定方法と一致させる |
| FR-R0114 | `.github/workflows/e2e-test.yml`の`e2e`jobの`unit`の前に`shellcheck`stepを置く。品質ゲートと同じ対象一覧とオプションで実行し、`timeout-minutes: 2`を付ける。jobの名前（必須ステータスチェック名`e2e`）は変えない。jobの`permissions`は`contents: read`以下とし、checkoutは`persist-credentials: false`のままとする（変更しないことをplanで確かめる） |
| FR-R0115 | CIは`jdx/mise-action`をコミットのSHAで固定して使い、`mise.lock`に従って`--locked`で導入する。`--locked`は、Actionの入力か環境変数`MISE_LOCKED=1`で明示し、既定の挙動に頼らない。miseの版も固定する。`mise.lock`の差分は、shellcheckの公式リリースのURLとSHA256だけであることをレビューで確かめる |

## 4. 非機能要件と検証方法

### 4.1 非機能要件

| ID | 要件 |
| --- | --- |
| NFR-R0101 | 自前のチェック用シェルや独自の解析を新しく作らない。shellcheck本体と、既存の品質ゲートへの呼び出しだけを追加する |
| NFR-R0102 | 導入する版はCI、ローカルのmacOS、ローカルのLinuxで同一にする。取得元の完全性は、`mise.lock`のSHA256の照合で確認する。`mise.lock`はlinuxとmacOSのx64、arm64の4つの環境を持つ |
| NFR-R0103 | CIのubuntu-24.04、ローカルのmacOS（Colima利用）、ローカルのLinuxで動作を確認する。アーキテクチャはx86_64とaarch64を想定する |
| NFR-R0104 | 既存のゲート（Markdown、`git diff --check`、M02〜M09のunitとsmoke）の判定と終了コードを弱めない |
| NFR-R0105 | shellcheckの追加で品質ゲートの実行時間が大きく増えない。実測値を文書に残す |
| NFR-R0106 | 除外のコメントと文書にAWSアカウント識別子、ARN、認証情報、利用者の絶対パスを書かない |
| NFR-R0107 | 文書は日本語で書き、AGENTS.mdの言語の規則とMarkdownゲートに従う |
| NFR-R0108 | 導入と検証で作った一時ファイルは、作業の終了前に削除する |
| NFR-R0109 | miseの設定ファイルは任意のコードを実行できるため、`mise.toml`に置くのは`min_version`と`[tools]`のshellcheck（完全な版）だけとする。`[tasks]`、`[hooks]`、`[env]`（`_.source`を含む）、`[plugins]`、テンプレートの関数（`exec()`など）を使わない。`mise.toml`以外のmiseの設定ファイル（`.mise.toml`、`mise.local.toml`、`.config/mise/`、`.tool-versions`）を追加しない。`mise.toml`の差分は`mise.lock`の差分と同じ重さでレビューする。信頼できない変更をローカルで確かめるときは、内容を確かめる前に`mise trust`を実行しない |
| NFR-R0110 | 取得物の完全性を、mise本体とshellcheckの両方で確かめる。`mise.lock`を最初に作るときは、4つの環境のURLがshellcheckの公式のGitHubリリースの資産で、SHA256が公式の配布物と一致することを、別の情報源と照合して記録する。mise本体の取得物の検証の方法（`jdx/mise-action`または公式の配布の、チェックサムや署名の検証の有無）をplanで確かめて記録する。`jdx/mise-action`のキャッシュは、無効にするか、キーに`mise.lock`のハッシュを含める |

### 4.2 検証方法

| 検証 | 方法 |
| --- | --- |
| 導入 | CIとローカルの導入手順を実行し、固定した版が報告されることを確認する |
| 未導入、版の不一致 | shellcheckを使えない状態と版が異なる状態で品質ゲートが失敗し、導入手順が表示されることを確認する |
| 指摘 | 品質ゲートで対象全ファイルのshellcheckが0件で終わることを確認する。除外はコードと理由を持つ個別のものだけであることを`grep`で確認する |
| 構文エラー | 意図的な構文エラーを含む一時ファイルで品質ゲートが失敗することを確認する。一時ファイルは`git ls-files`の対象に入らないため、`git add -N`で一時的にindexへ入れてから品質ゲートを実行し、確認後に`git reset -- <一時ファイルのパス>`でその1つだけをindexから外し、ファイルを削除する（パスを指定しない`git reset`は、利用者がステージした変更まで外すため使わない） |
| 回帰 | M02〜M09のunitとsmoke、品質ゲート、CIが通ることを確認する。修正が判定と終了コードを変えていないことを差分で確認する |
| 文書 | AGENTS.mdの品質ゲートの表、docs、導入手順が実装と一致することを確認する。`npm run -s lint:md`が指摘0である |

## 5. 対象外

- shellcheckの指摘を理由にした処理の書き直し（判定や終了コードの変更）。必要なときはR02〜R05の範囲、または別のIssueにする
- 他のシェルの方言（bash、zsh）への切り替え
- shfmtなど、整形ツールの導入
- 追跡対象外のファイル、Markdown内のスクリプト片の検査
- `package.json`へのshellcheckの追加（npmのパッケージ、コンテナイメージによる導入）
- 動的ポートや検査の並列化など、指摘と無関係な改善
- 実ECS環境や実AWSへの接続

## 6. 完了条件

Issue #33の完了条件を、次の表で対応づける。各条件に受け入れ条件（AC）の番号と確認方法を付ける。

| 出典 | AC | 完了条件 | 対応要件 | 確認方法 |
| --- | --- | --- | --- | --- |
| #33-1 | AC-R0101 | 固定した版のshellcheckを、CI、ローカルのmacOS、ローカルのLinuxでmiseから導入でき、`shellcheck --version`が`mise.toml`の版と一致する | FR-R0101、FR-R0115、NFR-R0102、NFR-R0103 | 各環境で`mise install --locked`を実行し、版を記録する。`mise.lock`のSHA256が一致しないときは導入が失敗することを確かめる |
| #33-1 | AC-R0102 | 未導入、または版が異なるときに、品質ゲートが失敗し、導入手順を表示する | FR-R0102、FR-R0105 | PATHからshellcheckを外した状態と、版の異なる状態で品質ゲートを実行し、終了コードと表示を確かめる |
| #33-1 | AC-R0103 | CIの`e2e`jobに`shellcheck`stepがあり、`unit`の前で実行される。必須ステータスチェック名は`e2e`のままである | FR-R0114 | `e2e-test.yml`の差分とCIの実行結果を確かめる |
| #33-2 | AC-R0104 | 品質ゲートが`shellcheck -s sh -S style`を追跡対象の全`.sh`へ実行し、`sh -n`のループがない | FR-R0103、FR-R0104、FR-R0106、NFR-R0101 | `scripts/quality-gate.sh`の差分と、`sh -n`の不在を`grep`で確かめる。shellcheckの失敗が終了コードへ反映されることを、指摘を含む一時ファイルで確かめる。一時ファイルは`git ls-files`の対象に入らないため、`git add -N`で一時的にindexへ入れてから品質ゲートを実行し、確認後に`git reset -- <一時ファイルのパス>`でその1つだけをindexから外し、ファイルを削除する（パスを指定しない`git reset`は、利用者がステージした変更まで外すため使わない） |
| #33-2 | AC-R0105 | `sh -n`が検出していた構文エラーを、品質ゲートが失敗として検出する | FR-R0112 | 意図的な構文エラーを持つ一時ファイルで品質ゲートが失敗することを確かめる。一時ファイルは`git ls-files`の対象に入らないため、`git add -N`で一時的にindexへ入れてから品質ゲートを実行し、確認後に`git reset -- <一時ファイルのパス>`でその1つだけをindexから外し、ファイルを削除する（パスを指定しない`git reset`は、利用者がステージした変更まで外すため使わない） |
| #33-3 | AC-R0106 | 品質ゲートで、追跡対象の全`.sh`のshellcheckが0件で終わる | FR-R0107、FR-R0109、FR-R0110 | 品質ゲートの実行結果 |
| #33-3 | AC-R0107 | 除外はすべて個別で、コードと理由をその場に持つ。ファイル全体への除外と、`.shellcheckrc`でのコード単位の無効化がない。SC2086、SC2046、SC2016、SC2012の除外は、出どころの根拠を持つ | FR-R0107、FR-R0108、FR-R0111 | `git grep`で`shellcheck disable`を全件列挙し、理由の有無を確かめる。`.shellcheckrc`の内容を確かめる。SC2086、SC2046、SC2016、SC2012の除外は、件数と各行の妥当性をレビューで1件ずつ確かめる |
| #33-3 | AC-R0108 | 修正が判定、終了コード、出力を変えていない | FR-R0111 | 修正の差分を、Q-R0107の基準と照らして確かめる。M02〜M09の結果が変わらないことで裏づける |
| #33-4 | AC-R0109 | M02〜M09のunitとsmoke、品質ゲート、CIが通る。品質ゲートの実行時間の増加を記録する | NFR-R0104、NFR-R0105 | 各検査とCIの実行結果、実行時間の実測 |
| #33-5 | AC-R0110 | `AGENTS.md`の品質ゲートの表と`docs/ローカル実行とCI.md`が、新しいゲート、導入手順、版の固定方法と一致する。`npm run -s lint:md`が指摘0である | FR-R0113、NFR-R0107 | 文書の差分、`lint:md`の結果 |

## 7. 未決事項の解消

Q-R0101からQ-R0110は`clarify.md`で解消済みである。決定の根拠はclarify.mdの各節にある。
Q-R0105とQ-R0111は、利用者の判断（2026-11-07）で決めた。

| ID | 論点 | 決定 | 反映先 |
| --- | --- | --- | --- |
| Q-R0101 | 検査する重さの下限 | `-S style`（note以上の全件）を品質ゲートと`.shellcheckrc`の両方に明示する | FR-R0103、FR-R0110 |
| Q-R0102 | `.shellcheckrc`の要否 | 置く。`shell`、`severity`、`external-sources`、`source-path`だけを宣言し、コード単位の無効化は書かない | 2節、FR-R0108 |
| Q-R0103 | 読み込み先の宣言方式 | 各行の`# shellcheck source=`を主とし、source-pathは相対パスの基点だけを担う | FR-R0109 |
| Q-R0104 | CIでの実行 | `e2e`jobの`unit`の前に`shellcheck`stepを追加する | 2節、FR-R0114、AC-R0103 |
| Q-R0105 | 導入方法 | 一般的なツールのmiseで、版とSHA256を固定して導入する。自前の導入用シェルは作らない（利用者の判断） | FR-R0101、FR-R0115、NFR-R0102、AC-R0101 |
| Q-R0106 | 既存156件の解消の進め方 | このIssueで全件を修正または理由付きの個別除外にする。ゲートの置き換えより前に完了する | AC-R0106 |
| Q-R0107 | 修正と個別除外の判断基準 | 指摘コードごとの基準をclarify.mdに定めた。迷う行は理由付きの個別除外 | FR-R0111、AC-R0108 |
| Q-R0108 | 対象ファイルの集合 | `git ls-files -z '*.sh'`（現在20件） | 2節、FR-R0104 |
| Q-R0109 | 版の宣言場所 | `mise.toml`と`mise.lock`。`package.json`は変更しない | 2節、FR-R0101 |
| Q-R0110 | 版の不一致時の扱い | 失敗とし、導入手順を示す | FR-R0102、AC-R0102 |
| Q-R0111 | コミットの分割 | PRは1つ。版の宣言（`mise.toml`、`mise.lock`）と`.shellcheckrc`、m09以外の解消、m09の解消、ゲートの置き換えとCI、文書の5コミット（利用者の判断） | plan |
