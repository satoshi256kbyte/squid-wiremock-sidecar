# R01 実装計画

## 1. 設計の要点と方針

`scripts/quality-gate.sh`の`sh -n`のループを、shellcheck（`-s sh -S style`）に置き換える。
shellcheckは一般的なツールのmiseで、版とSHA256を`mise.toml`と`mise.lock`に固定して導入する。
自前の導入用シェルや独自の検査は作らない（NFR-R0101）。
`spec.md`のQ-R0101〜Q-R0111と、`clarify.md`の決定を確定方針として扱う。

| 方針 | 対応する要件 |
| --- | --- |
| 版は`mise.toml`、URLとSHA256は`mise.lock`の一か所に宣言し、品質ゲートとCIが同じものを使う | FR-R0101、NFR-R0102 |
| 実行は`mise exec`ではなく、`mise which shellcheck`で得たmise管理の実体のパスで行う | FR-R0102 |
| 期待する版は`mise current shellcheck`で得て、`mise.toml`を自前で解析しない | FR-R0102 |
| 対象は`git ls-files -z '*.sh'`で得る。パターンの展開は使わない | FR-R0104 |
| 既存の156件は、最小の修正か、コードと理由を持つ個別除外で解消する。一括の除外はしない | FR-R0107、FR-R0108、FR-R0111 |
| 読み込み先は行ごとの`# shellcheck source=`で宣言し、`.shellcheckrc`は基点だけを持つ | FR-R0109、FR-R0110 |
| CIは`e2e`jobの`unit`の前に`shellcheck`stepを置き、job名`e2e`を変えない | FR-R0114、FR-R0115 |
| miseの設定の権限と、取得物の完全性を守りの中心にする | NFR-R0109、NFR-R0110 |

### 1.1 実機の事実から決まったこと

実機で確かめた事実（mise 2026.11.3、shellcheck 0.11.0）から、次を決めた。

| 確かめた事実 | 決めたこと |
| --- | --- |
| 未導入のとき、`mise exec -- shellcheck`はPATH上の別のshellcheckで成功する。FR-R0102の「PATH上の別の経路は使わない」を守れない | `mise exec`を使わない。`mise which shellcheck`はmiseが入れた実体のパスを返し、未導入なら`shellcheck is not a mise bin`で失敗する（終了コード1）。そのパスを実行する |
| `mise current shellcheck`は`mise.toml`の版（`0.11.0`）を返す | 期待する版にこれを使う。実体の`--version`の出力と比べる |
| 自動の導入を止める設定は`exec_auto_install`（`MISE_EXEC_AUTO_INSTALL`）と`auto_install`（`MISE_AUTO_INSTALL`）で、既定はどちらもtrue | `MISE_EXEC_AUTO_INSTALL=false`、`MISE_AUTO_INSTALL=false`、`MISE_LOCKED=1`を品質ゲートで明示する |
| `mise install --locked`は、lockに無い版では`is not in the lockfile`、チェックサムの不一致では`Checksum mismatch`で失敗する（どちらも終了コード1） | 導入手順は`mise install --locked`とする。AC-R0101の失敗側の確認にこの2つを使う |
| `mise.toml`の`shellcheck = "0.11.0"`のbackendは`aqua:koalaman/shellcheck`になる | backendは指定せずに、この既定を使う。`mise.lock`の4つの環境のURLが公式のGitHubリリースの資産であることを確かめる |
| `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`で、4つの環境のURLとSHA256が記録される。`lockfile_version = 4`、`checksum_source = "mise-versions"` | 4つの環境を指定して作る。SHA256は、GitHub APIのリリース資産の`digest`と照合した結果が一致した |
| `jdx/mise-action` v5.2.7はコミットSHA`b44d12e7d0d8ee7461bb893e1b1993500433185b`。`version`でmise本体の版を、`sha256`でmise本体のSHA256を固定できる。mise本体の署名はactionのソースがminisignで確かめている | SHAで固定し、`version`と`sha256`（linux-x64）を指定する。`--locked`は既定の自動に頼らず、`install_args: --locked shellcheck`で明示する（5.2節） |
| actionは`mise.lock`があると`mise install --locked`を自動で実行する。作業ディレクトリを`MISE_TRUSTED_CONFIG_PATHS`に入れて、リポジトリのmiseの設定を自動で信頼する | PRの`mise.toml`がCIでそのまま動く。守りの中心は、`mise.toml`の内容の制限（NFR-R0109）とjobの権限（`contents: read`）になる。5.4節に明記する |
| `cache`と`env`の既定はtrue | どちらも`false`にする。キャッシュ経由の取得物と、後続のstepへの環境変数の読み込みを避ける |

mise本体の公式のSHA256（`SHASUMS256.txt`）は、linux-x64が
`c2f7e814cb39f60b7f67a0ff36cb805e94128bf2dff09d175309d0f095b8cc3b`である。
CIのubuntu-24.04（x86_64）はこの値を`sha256`に指定する。
linux-arm64、macos-x64、macos-arm64の値は、ローカルでの導入手順の確認に使う（8節）。

## 2. 変更するファイル

| ファイル | 区分 | 変更内容 | コミット |
| --- | --- | --- | --- |
| `mise.toml` | 新規 | `min_version = "2026.11.3"`と、`[tools]`の`shellcheck = "0.11.0"`だけを書く。`[tasks]`、`[hooks]`、`[env]`、`[plugins]`、テンプレート関数は書かない（NFR-R0109） | 1 |
| `mise.lock` | 新規 | `mise lock`で4つの環境のURLとSHA256を記録する。差分はshellcheckの公式URLとSHA256だけであることを確かめる | 1 |
| `.shellcheckrc` | 新規 | `shell=sh`、`severity=style`、`external-sources=true`、`source-path=SCRIPTDIR`だけ。`disable=`は書かない（FR-R0108） | 1 |
| 20件の`.sh`のうちm09以外の19件 | 変更 | 指摘の修正、または`# shellcheck disable=SCxxxx # 理由`と`# shellcheck source=`の追加（4.1〜4.3節） | 2 |
| `tests/m09-execution-and-ci.sh` | 変更 | 112件の解消（4.4節）。この時点ではワークフローとゲートの検査を変えない | 3 |
| `scripts/quality-gate.sh` | 変更 | `sh -n`のループをshellcheckの実行に置き換える（5節） | 4 |
| `.github/workflows/e2e-test.yml` | 変更 | mise-actionのstepと`shellcheck`stepを`unit`の前に追加する（6節） | 4 |
| `tests/m09-execution-and-ci.sh`の検査 | 変更 | 壊れるワークフローの検査4件を直し、ゲートとワークフローの新しい検査を足す（7節） | 4 |
| `AGENTS.md` | 変更 | 品質ゲートの表の`sh -n`をshellcheckに改め、導入手順と未導入時の失敗を書く | 5 |
| `docs/ローカル実行とCI.md` | 変更 | shellcheckの導入、版の固定、CIのstep、実行時間の実測、`mise.lock`の更新手順を書く | 5 |
| `README.md` | 変更 | Prerequisitesにmiseとshellcheckを足す。M07、M08、S14が固定している行は変えない | 5 |

`package.json`、`.gitignore`は変更しない。mise.tomlの導入で追加の生成物は出ない
（`mise install`の導入先はユーザーのデータ領域で、リポジトリの外である）。
確認は、各コミットの前に`git status --short`で行う。

### 2.1 `mise.toml`と`.shellcheckrc`の内容

`mise.toml`の内容は、実機で試した見本と同じである。

```toml
min_version = "2026.11.3"

[tools]
shellcheck = "0.11.0"
```

`.shellcheckrc`の内容は次のとおりとする。

```text
shell=sh
severity=style
external-sources=true
source-path=SCRIPTDIR
```

`min_version`は下限であり、`mise.lock`のlockfile_version 4を扱える版を求める。
CIでは`jdx/mise-action`の`version`で本体の版を完全に固定する。

## 3. 品質ゲートの中での順序

shellcheckは、共通ゲートの`git diff --check`の3行の直後、Markdownゲートの前に置く。
変更範囲に関わらず毎回実行する（`sh -n`のループと同じ位置で、条件を付けない）。
`tests/m09-execution-and-ci.sh`のゲートの検査は、M09のブロックを`^if has_match '.*scripts/e2e`の行で探す。
新しいブロックはこの行より前にあり、`has_match`の`if`ではないため、影響しない。

処理の流れは次のとおりとする。

| 順序 | 処理 | 失敗時 |
| --- | --- | --- |
| 1 | `command -v mise`で、miseの有無を確かめる | `FAILED: miseが未導入。...`で`status=1` |
| 2 | `MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1`を付けて、`mise current shellcheck`で期待する版を得る | 空、または失敗なら`status=1` |
| 3 | 同じ環境変数で`mise which shellcheck`を実行し、実体のパスを得る | 未導入なら`status=1` |
| 4 | 実体の`--version`の出力から版を取り出し、期待する版と比べる | 異なれば`status=1` |
| 5 | `git ls-files -z '*.sh'`を一時ファイルへ書き、空でないことを確かめる | 失敗または空なら`status=1` |
| 6 | `xargs -0 <実体のパス> -s sh -S style < <一時ファイル>`を実行し、終了コードを`status`へ反映する | 非0なら`status=1` |
| 7 | 一時ファイルを`trap`で削除する | なし |

`git ls-files`はパイプにせず、一時ファイルへ書いて終了コードを見る。
パイプにすると、gitの失敗が後段の終了コードに隠れて検査が空のまま通るためである（既存のゲートの方針と同じ）。
空の一覧は成功扱いにしない。

失敗のメッセージには、導入手順を必ず含める。メッセージは次のとおりとする。

| 状態 | メッセージの要点 |
| --- | --- |
| miseが無い | `FAILED: miseが未導入。miseを導入し、mise install --lockedを実行する（docs/ローカル実行とCI.md）` |
| shellcheckが未導入 | `FAILED: shellcheckが未導入。mise install --lockedを実行する` |
| 版が違う | `FAILED: shellcheckの版が期待と異なる（期待 X、実際 Y）。mise install --lockedを実行する` |

品質ゲートは`set -eu`で動く。`var=$(mise current shellcheck)`のように代入で受けると、失敗した時点でスクリプトが止まり、
`FAILED:`のメッセージと導入手順を出す前に終わってしまう。このため、`mise current`と`mise which`の取得は
`if ! var=$(...); then`のように`if !`で受け、導入手順つきの`FAILED:`を出してから`status=1`にする。
空の出力も同じ分岐で失敗にする。

PATH上の別の経路のshellcheckは使わない。実体のパスで実行するため、PATHにあるshellcheckの版は結果に影響しない。
`MISE_LOCKED=1`は`--locked`を通らない導入を起こさないための明示であり、既定の挙動に頼らない。
ゲートはshellcheckを導入しない。導入はMarkdownゲートの`npm ci`と同じく、利用者が事前に行う。

実行時間は、実装時に品質ゲートの前後で実測し、`docs/ローカル実行とCI.md`の所要時間の表へ書く（NFR-R0105）。
`clarify.md`のとおり、`-S info`と`-S style`の実行は120秒で止まった。
このため、20ファイル全体での実行時間は未確認である。コミット4で最初に実測する。
遅い場合の対応は、10節のリスクにまとめる。

## 4. 156件の解消の進め方

基準は`clarify.md`のQ-R0107に従う。指摘の一覧は、実機で取った`shellcheck -s sh -f gcc`の出力を使う。
作業は1ファイルずつ行い、各ファイルの修正の後に、そのファイルだけを再実行して0件を確かめる。

### 4.1 進め方の共通の手順

1. 先に`source=`の宣言（SC1090、SC1091）を入れる。読み込み先の中身が解析されると、
   SC2034（未使用の変数）や SC2154（未定義の変数）が変わるため、宣言の後で指摘を取り直す。
2. 取り直した指摘をコード別に直す。修正は最小にし、判定、終了コード、出力を変えない。
3. 除外は、対象の直前の行に`# shellcheck disable=SCxxxx # 理由`を書く。理由は「何が意図か」を1行で書く。
4. 迷う行は、原則は理由付きの個別除外にする。ただし、SC2086、SC2046、SC2016、SC2012は、
   迷う行を判定、終了コード、出力を変えない書き方に修正する。それができない行は、除外せず、
   利用者の判断に上げる（4.5節）。
5. 各ファイルの前後で、そのファイルの検査（M02〜M09の該当）を実行し、結果が変わらないことを確かめる。
6. 最後に、`git grep -n 'shellcheck disable'`で除外を全件列挙し、コードと理由の有無を確かめる。

### 4.2 m09以外の44件（コミット2）

| コード | 件数 | 対象 | 見込み |
| --- | --- | --- | --- |
| SC2034 | 13 | `scripts/e2e-lib.sh`の5件、`scripts/e2e.sh`の1件、`tests/m02`〜`m08`の`SWSC_ROOT`の7件 | 別のファイルが参照する変数は、参照元を理由に書いて除外する。`source=`を入れた後に残った分だけを対象にする。参照が0件のものは削除する。`export`への変更はしない |
| SC2329 | 6 | `tests/s14-taskdef-contract.sh`の6関数 | `git grep`で関数名の参照を確かめる。文字列で組み立てて呼ばれる関数は、理由付きで除外する。参照が0件で、文字列としても組み立てられていない関数だけを削除する |
| SC2012 | 3 | `scripts/e2e-lib.sh:425`、`tests/m07-scenario-isolation.sh:660`、`tests/m08-e2e-suite.sh:992` | 名前を検査が管理している入力は、出どころを理由に書いて除外する。管理の根拠が示せない行は、出力が変わらない`find`へ修正する。それもできなければ利用者の判断に上げる |
| SC2031 | 6 | `tests/m08-e2e-suite.sh`のサブシェル後の参照 | サブシェルによる隔離が意図であれば除外する |
| SC2030 | 2 | `tests/m08-e2e-suite.sh:258`、`:276` | 同上。サブシェルを外す修正はしない |
| SC1090 | 4 | `tests/m06-client-resilience.sh:420`、`tests/m08-e2e-suite.sh:396`、`:404`、`:412` | 読み込み先が1つに決まる行は`# shellcheck source=<相対パス>`。複数の候補や一時ファイルは`source=/dev/null`と理由 |
| SC2016 | 3 | `tests/m06-client-resilience.sh:101`、`tests/m08-e2e-suite.sh:393`、`tests/s14-taskdef-contract.sh:109` | 展開させない意図（子のshell、生成物の本文、入力値）を確かめ、理由を書いて除外する |
| SC2086 | 2 | `tests/m06-client-resilience.sh:164`、`tests/m08-e2e-suite.sh:665` | 値が1語と分かれば引用符を付ける。分割が意図なら、値の出どころを理由に書いて除外する。出どころが示せなければ利用者の判断に上げる |
| SC2043 | 2 | `tests/m07-scenario-isolation.sh:263`、`tests/m08-e2e-suite.sh:68` | 本体が`break`と`continue`を使わなければ、直接の記述へ修正する。そうでなければ除外 |
| SC1091 | 1 | `test-client/entrypoint.sh:14` | `.shellcheckrc`の`external-sources=true`と`# shellcheck source=retry-lib.sh`で解消する。`test-client/`はイメージ内で`./retry-lib.sh`を読むため、リポジトリ内のパスで宣言する |
| SC2154 | 1 | `scripts/e2e-lib.sh:276` | trapの文字列内で代入する変数の誤検出。理由を書いて除外する |
| SC1003 | 1 | `tests/s14-taskdef-contract.sh:109` | 末尾の`\`を含む固定文字列の誤検出。理由を書いて除外する |

`SC1091`の`test-client/entrypoint.sh`は、Dockerfileの`COPY`の配置で`./retry-lib.sh`がカレントにある。
`source=`は`.shellcheckrc`の`source-path=SCRIPTDIR`の基点から解決される相対パスで書く。
イメージの動作は変えない。

### 4.3 コミット2の完了条件

m09以外の19ファイルについて、`shellcheck -s sh -S style`が0件で終わる。
m09だけが112件のまま残る。この時点で品質ゲートはまだ`sh -n`である。
M02〜M08のsmokeのうち、変更したファイルに対応するものを実行し、結果が変わらないことを確かめる。

### 4.4 m09の112件（コミット3）

`tests/m09-execution-and-ci.sh`は、検査の本体で3,700行を超える。件数が多く、レビューが重いため別コミットにする。

| コード | 件数 | 見込み |
| --- | --- | --- |
| SC2016 | 39 | 偽のコマンド本文、子のshellの文字列、入力値が大半と見込む。1件ずつ意図を確かめて理由を書き、除外する。迷う行は修正に回し、できなければ利用者の判断に上げる |
| SC1090 | 23 | `. "$LIB"`の形。読み込み先が決まる行は`source=`、一時ファイルを読む行は`source=/dev/null`と理由 |
| SC2031 | 20 | サブシェルの隔離が意図の行は除外する |
| SC2030 | 18 | 同上 |
| SC2329 | 9 | `git grep`と、文字列としての参照を確かめる。参照があれば除外、0件なら削除 |
| SC2012 | 1 | `tests/m09-execution-and-ci.sh:700`の`ls "$TMP/ctx" \| wc -l`は件数の確認。検査が管理する入力のため、除外する。管理の根拠が示せなければ利用者の判断に上げる |
| SC2015 | 1 | `grep -q A && grep -q B \|\| {...}`は意図どおり。除外する |
| SC2086 | 1 | `tests/m09-execution-and-ci.sh:289`の`$_list`。値の出どころを確かめ、1語なら引用符、分割が意図なら除外する |

m09は検査対象のゲートとワークフローの行を、`grep`や`awk`で固定している。
コメントの追加で行番号は変わっても、検査は行の内容で探すため影響しない。
ただし、ゲートとワークフローの行を引用した文字列を含む行は、変更しない。
コミット3では、`# shellcheck`のコメントの追加と最小の修正だけを行う。

### 4.5 利用者の判断に上げる手順

次の行は、除外も修正もせずに止まり、利用者に確認する。

- SC2086、SC2046、SC2016、SC2012のうち、判定、終了コード、出力を変えない書き方に修正できず、
  値の出どころ（固定の文字列か、検査の中で作った値）も示せない行
- 修正すると出力が変わる行

手順は次のとおりとする。

1. 該当の行に印を付けず、ファイルは変更しないで、一覧にする。
   一覧には、ファイルと行番号、指摘のコード、周辺の数行の要約、修正案と除外案、それぞれの影響を書く。
2. 利用者が修正か除外かを選ぶ。除外を選んだ場合は、理由を利用者の言葉で書く。
3. 決定をコミットのメッセージではなく、`specs/R01-shellcheck/`の記録に残す（識別情報を含めない）。
4. 決定が出るまで、そのコミットを進めない。他のファイルの作業は続けてよい。
5. 決定を、一覧の行だけを対象に実装サブエージェントがコードへ反映する（修正または理由付きの除外）。
   一覧が0件なら省略する。反映の後に、対象ファイルのshellcheckを0件にし、M02〜M09のsmokeとunitを実行する。
   smokeとunitは、反映より前に実行しない（反映後に再実行が要るため）。

SC2086とSC2046の除外は、値の出どころが固定の文字列か検査の中で作った値と示せ、空白とグロブの文字を含まないと
確かめられた場合だけとする。理由に出どころを書く（FR-R0111）。

### 4.6 件数の記録

件数の基準を記録に書く。156件（m09以外44件）は`.shellcheckrc`なしの実測である。最終の設定
（`external-sources=true`、`source-path=SCRIPTDIR`）では`test-client/entrypoint.sh`のSC1091が消え、
合計155件（m09以外43件、m09 112件）になる。4.2節のSC1091の行は、`source=retry-lib.sh`の宣言が
`.shellcheckrc`と合わせて意図どおりかを確認する扱いにする（宣言は残してよい）。

解消後に、修正の件数と除外の件数を、コード別に`docs/ローカル実行とCI.md`の記録または検証記録へ残す。
SC2086、SC2046、SC2016、SC2012の除外は、件数と各行の妥当性をレビューで1件ずつ確かめる（AC-R0107）。

## 5. 品質ゲートとCIの実装

### 5.1 `scripts/quality-gate.sh`

変更は、`sh -n`のループ（6行）を、3節の処理に置き換えることだけである。
関数は新しく作らず、既存の`run`と`status`を使う。コメントには`Why:`と`Why not:`の形で理由を書く。

| 項目 | 内容 |
| --- | --- |
| 追加するコマンド | `command -v`、`mise current`、`mise which`、`git ls-files -z`、`mktemp`、`xargs -0`。いずれも標準の道具とmiseである |
| 環境変数 | `MISE_EXEC_AUTO_INSTALL=false`、`MISE_AUTO_INSTALL=false`、`MISE_LOCKED=1`を、miseを呼ぶ各コマンドへ付ける。`export`はしない |
| 失敗の握りつぶし | `\|\| true`を使わない。shellcheckの終了コードを`status`へ反映する |
| 一時ファイル | `mktemp`で作り、`trap`で削除する。`trap`は既存のゲートに無いため、このブロックの中で閉じる |
| `sh -n` | 削除する。構文エラーはshellcheckがSC1xxxのerrorとして検出する（8節で確かめる） |
| 対象の拡大 | `ecs/squid/*.sh`が加わる。20件すべてが0件であることが、コミット4の前提 |

### 5.2 `.github/workflows/e2e-test.yml`

`checkout`の直後、`unit`の前に、2つのstepを置く。

| 順序 | step | 内容 |
| --- | --- | --- |
| 1 | 名前なしの`uses` | `jdx/mise-action@b44d12e7d0d8ee7461bb893e1b1993500433185b # v5.2.7`。`with`で`version`、`sha256`、`cache: false`、`env: false`、`install_args: --locked shellcheck`を指定する。`timeout-minutes`は付けない（下記） |
| 2 | `shellcheck` | `run:`は1行。`timeout-minutes: 3` |

`version`はmise本体の版（2026.11.3）、`sha256`はlinux-x64の値（1.1節）を指定する。
`--locked`は、actionが`mise.lock`を見て自動で足す既定に頼らず、`with:`の`install_args`に
`--locked shellcheck`と書いて明示する。`${{`は使わず、`env:`のキーは増やさない。
既存の検査`t_wf_dummy_credentials_are_workflow_env_only`が`env:`の行を1つに固定しているが、
`install_args`はこの検査に掛からないことを確認済みである。
`MISE_LOCKED=1`は、品質ゲート（ローカル）の側で明示する（3節）。CIの`run:`には付けない。

初回のCIの前に、`jdx/mise-action`のソース（コミットSHA`b44d12e...`）で、`install_args`が`--locked shellcheck`の形で受理されること
（`--locked`が重複して足されないこと）を確かめる。確かめた結果は`verification/phase-4-results.md`に記録する。

`shellcheck`stepの上限は`timeout-minutes: 3`とする。実測は約74秒（m09が52.6秒、残り19ファイルが21.8秒）で、
2分では余裕が小さく、初回のCIが上限に当たるおそれがあるため、利用者の判断（2026-11-07）で最初から3分にした。
mise-actionのstepには`timeout-minutes`を付けず、job全体の15分の上限に任せる。実測の後に必要なら足す。
`sha256`はlinux-x64の値だけであり、CIはubuntu-24.04（x86_64）だけを前提とする。runnerがarm64に変わると、
取得の検証が失敗して止まる（安全側）。この前提を`docs/ローカル実行とCI.md`に書く。

`shellcheck`stepの`run:`は次の1行とする。自動の導入を止める2つの環境変数は、`git ls-files`には効かないため、`$(...)`の中の`mise which shellcheck`にだけ付ける。`MISE_LOCKED=1`は導入のstepの`install_args`が担うため付けない。

```text
git ls-files -z '*.sh' | xargs -0 "$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false mise which shellcheck)" -s sh -S style
```

実装時に、同じ内容で短くできる書き方があれば比べる（10節の未確認）。
`git ls-files`が失敗すると一覧が空になり、`xargs`がファイル無しでshellcheckを呼んで失敗する（GNUのxargs）。
ubuntu-24.04ではこの挙動で検査が空のまま通ることはない。
CIの`run:`は式（`${{`）を含めない（既存の検査が禁じている）。

CIでは版の比較をしない。`mise which`の結果は、`mise.lock`に従って`--locked`で入れた実体であり、
版は`mise.toml`が決める。比較は品質ゲート（ローカル）の防御であり、CIではactionの`--locked`が担う。
この差は10節のリスクに書く。

### 5.3 jobの権限

`permissions`はワークフロー全体で`contents: read`のまま、`checkout`は`persist-credentials: false`のままにする（FR-R0114）。
`mise-action`は書き込み権限を要らない。コミット4の差分で、この2点が変わっていないことを確かめる。
既存の検査（`t_wf_permissions_are_contents_read_only`、`t_wf_checkout_does_not_persist_credentials`）が裏づける。

### 5.4 miseの設定の信頼

`jdx/mise-action`は作業ディレクトリのmiseの設定を自動で信頼する。
PRの作成者が`mise.toml`を書き換えると、CIはその内容をそのまま実行できる。
`mise.toml`は`[tasks]`、`[hooks]`、`[env]`、テンプレート関数で任意のコードを実行できるためである。
守りの中心は、次の3点になる。

| 守り | 内容 |
| --- | --- |
| `mise.toml`の内容の制限 | `min_version`と`[tools]`のshellcheckだけにする（NFR-R0109）。`mise.toml`以外の設定ファイルを足さない |
| レビュー | `mise.toml`の差分を`mise.lock`の差分と同じ重さでレビューする。`mise.lock`の差分はshellcheckの公式URLとSHA256だけであることを確かめる |
| CIの権限 | `contents: read`だけで、Secretsを読まない。ダミーの認証情報だけをworkflowのenvに置く。`persist-credentials: false` |

`env: false`と`cache: false`は、取得物と環境変数の経路を減らすための設定であり、設定の信頼の問題は解消しない。
この点を`docs/ローカル実行とCI.md`にも書く。
`pull_request`で動くため、フォークからのPRも同じ経路を通る。Secretsを使わず、読み取りだけの権限であることが前提である。

### 5.5 mise本体の取得物の検証

| 経路 | 検証 |
| --- | --- |
| CI | actionの`sha256`でmise本体のSHA256を照合する。actionのソースはminisignの署名も確かめる |
| ローカル（Linux） | 公式のバイナリをダウンロードし、`SHASUMS256.txt`と`sha256sum -c`で照合してから置く。パイプでシェルへつなぐ導入は、手順に載せない |
| ローカル（macOS） | Homebrewの`brew install mise`が候補。Homebrewのbottleのチェックサム検証に依存する。実機で未確認（10節） |

shellcheck本体は、`mise.lock`のSHA256をmiseが照合する。`mise lock`で初めて作るときは、
4つの環境のURLが公式のGitHubリリースの資産であることと、SHA256がAPIの`digest`と一致することを記録する。
実機では4つとも一致した。linux-arm64は公式のバイナリを直接計った値とも一致した。

## 6. コミットの分割

PRは1つとし、次の5コミットに分ける（Q-R0111）。
各コミットの完了時に、通すゲートを次の表に示す。

| コミット | 内容 | 完了時に通すゲート |
| --- | --- | --- |
| 1 | 版の宣言（`mise.toml`、`mise.lock`）と`.shellcheckrc` | `npm run -s lint:md`（変更に`.md`が無ければ省略可）。`git diff --check`。`mise install --locked`と`mise current shellcheck`が`0.11.0`。`mise.lock`のSHA256の照合記録。この時点の品質ゲートは`sh -n`のまま通る |
| 2 | m09以外の19ファイルの解消 | m09以外の19ファイルの`shellcheck -s sh -S style`が0件。品質ゲート（`sh -n`）。変更したファイルに対応するM02〜M08のsmoke。M09 unit |
| 3 | m09の112件の解消 | 20ファイルすべての`shellcheck`が0件。M09 unit。品質ゲート（`sh -n`）。M09 smoke |
| 4 | 品質ゲートの置き換えとCIのstep、壊れる検査の更新 | 品質ゲート（shellcheck版）。M09 unit（ワークフローとゲートの検査を含む）。未導入と版違いの確認（8節）。CIの実行 |
| 5 | 文書（`AGENTS.md`、`docs/ローカル実行とCI.md`、`README.md`） | `npm run -s lint:md`が指摘0。`git diff --check`。M09 unit（文書の検査）。品質ゲート |

どのコミットでも、品質ゲートが通る状態を保つ。コミット1〜3は、まだ`sh -n`のゲートであるため、shellcheckの結果は別に確かめる。
コミット4でゲートを置き換える時点で全件が0件になっているため、置き換えが失敗の原因にならない。
コミット、push、PR作成は、品質ゲートが通ってからである（`AGENTS.md`）。このplanでは行わない。

## 7. 壊れる既存の検査と直し方

`tests/m09-execution-and-ci.sh`の検査のうち、ワークフローまたはゲートの行を固定しているものを洗い出した。
コミット4で`mise-action`のstepと`shellcheck`stepを足すと、次の4件が壊れる。

| 検査 | 壊れる理由 | 直し方 |
| --- | --- | --- |
| `t_wf_uses_only_checkout_and_upload_artifact` | `uses:`の数を2に固定している | 数を3にし、`jdx/mise-action@`が40桁のコミットSHAで固定され、`# v`のコメントを持つことを加える。SHAの固定の判定は弱めない |
| `t_wf_steps_run_in_plan_order` | stepの並びを`checkout`〜`stop`の8個に固定している。`jdx/mise-action`の行はそのまま出力される | `sed`に`jdx/mise-action@`を`mise-action`へ置き換える規則を足し、期待を`checkout`、`mise-action`、`shellcheck`、`unit`、`test-ci`、`smoke`、`contract`、`collect`、`upload-artifact`、`stop`の10個にする |
| `t_ci_test_ci_scenarios` | 名前付きのstepを6件に固定している | 7件にする。`mise-action`は名前を付けない`uses`であり、数えない。job名`e2e`と、`smoke`、`contract`のstep名が変わらない確認は残す |
| `t_wf_yaml_parses_with_expected_shape` | `len(names) == 8`に固定している | 10にする。`permissions`、`runs-on`、`timeout-minutes`の確認は残す |

次の検査は壊れないが、強めて直す。判定を弱めない。

| 検査 | 追加する内容 |
| --- | --- |
| `t_wf_step_timeouts_are_unit3_test_ci10_smoke8_contract5` | `shellcheck`の`timeout-minutes`が3であることを加える。名前も`..._shellcheck3_unit3_...`へ改める |
| `t_wf_each_step_runs_its_command` | `shellcheck`stepの`run:`の行が、`mise which shellcheck`と自動の導入を止める2つの環境変数、`-s sh -S style`を持つことを加える。mise-actionのstepの`install_args`が`--locked`を持つ確認を加える |
| `t_wf_dummy_credentials_are_workflow_env_only` | 変更しない。`env:`の行が1つのままであること（5.2節の理由）が、この検査で裏づけられる |

`t_wf_run_lines_have_no_expression_or_block_scalar`と`t_wf_expressions_only_in_concurrency_and_artifact_name`は、
追加するstepに式とブロックの記法を使わないため、そのまま通る。`with:`の値に`${{`を使わない。

ゲートの検査（`t_gate_*`）は、次の理由で壊れない。ただし、実行して確かめる。

| 検査 | 壊れない理由 |
| --- | --- |
| `t_gate_m09_*`（M09のブロック） | ブロックの先頭を`^if has_match '.*scripts/e2e`で探す。新しいブロックは`has_match`の`if`ではなく、この行より前にある |
| `t_gate_no_compose_calls_or_or_true_wrapped_docker` | 新しい行に`docker`と`\|\| true`を含めない |
| `t_gate_m09_is_not_added_to_the_existing_loop` | M02〜M08の`for test in`の行を変えない |
| `t_gate_does_not_register_contract_and_states_why` | NOTEの行とcontractの扱いを変えない |
| `t_managed_resource_check_*` | `managed_check`の定義を変えない |

新しく足す検査は、次の2つである。

| 検査 | 内容 |
| --- | --- |
| `t_gate_runs_shellcheck_with_pinned_options` | ゲートが`mise which shellcheck`と`-s sh -S style`を持ち、`sh -n`を持たず、`mise exec`を使わないことを静的に確かめる |
| `t_shellcheck_config_and_mise_toml_are_restricted` | `.shellcheckrc`の行が4つだけで`disable=`を含まないこと。`mise.toml`が`min_version`と`[tools]`のshellcheckだけで、`[tasks]`などを含まないこと |

`t_shell_syntax_and_python_compile_pass`（`sh -n`で7ファイルを確かめる）は、M09自身の構文検査であり、
品質ゲートの`sh -n`とは別である。残す。
M09 unitに加える検査も、Docker、AWS CLI、miseの実行を使わない（静的な確認だけ）。
未導入と版違いの動作確認は、8節のとおり手作業の確認にする。

## 8. 検証境界と手順

| 層 | 内容 | 実行主体 |
| --- | --- | --- |
| 静的 | `git grep`による`shellcheck disable`の列挙（ファイル全体に効く先頭の`disable=`は、列挙結果の各行が対象行の直前にあることをレビューで確かめる）、`.shellcheckrc`と`mise.toml`の内容、`sh -n`の不在、実行に使う`mise exec`の不在 | メインエージェント |
| unit | `sh tests/m09-execution-and-ci.sh unit`（Docker、AWS CLIを使わない） | メインエージェント、CI |
| smoke | 変更したファイルに対応するM02〜M08と、M09 smoke（Dockerを使う） | メインエージェント、CI |
| 品質ゲート | `sh scripts/quality-gate.sh`。shellcheckの0件、未導入と版違いの失敗 | メインエージェント |
| CI | `shellcheck`stepが`unit`の前で通る。job名`e2e`が変わらない | CI |
| ローカルの導入 | macOS（Colima）とLinuxで`mise install --locked`を実行し、版を記録する | 利用者の端末 |

### 8.1 一時ファイルを使う確認

構文エラー、指摘、未導入、版違いの確認は、次の手順で行う。
一時ファイルは`git ls-files`の対象に入らないため、`git add -N`で一時的にindexへ入れる。
置き場は`$KIROCREW_SCRATCH`ではなく、リポジトリ内の対象のディレクトリ（`tests/`など）にする。
`git ls-files`はリポジトリ内のパスだけを返すためである。

1. 一時ファイル（例: `tests/zz-r01-tmp.sh`）を作る。内容は、`if then`のような構文エラー、
   または未クォートの変数のような指摘である。AC-R0104のために、構文エラー以外の指摘
   （未クォートの変数など、構文は正しいが`-S style`が報告する内容）を持つファイルでも確かめる。
2. `git add -N tests/zz-r01-tmp.sh`で、そのパスだけをindexへ入れる。
3. `sh scripts/quality-gate.sh`を実行し、失敗することと、終了コードが非0であることを確かめる。
4. `git reset -- tests/zz-r01-tmp.sh`で、そのパスだけをindexから外す。パスを指定しない`git reset`は使わない。
5. 一時ファイルを、絶対パスを指定して削除する。
6. `git status --short`で、一時ファイルが残っていないことを確かめる。

構文エラーは、`sh -n`が検出していたものと同等であることを確かめる（FR-R0112）。
確かめる種類は、`if`の閉じ忘れ、クォートの閉じ忘れ、`fi`の過不足とする。shellcheckはこれらをerrorとして報告する。
同等でない種類が見つかった場合は、判定を弱めないために、ゲートに`sh -n`を戻すかどうかを利用者に諮る。

未導入と版違いの確認は、miseの設定をリポジトリの外に作って行い、リポジトリの`mise.toml`を書き換えない。

| 状態 | 作り方 | 期待 |
| --- | --- | --- |
| mise無し | `command -v mise`が失敗するPATHで、品質ゲートを実行する | 失敗し、導入手順を表示する |
| shellcheck未導入 | `MISE_DATA_DIR`を空の一時ディレクトリへ向けて、品質ゲートを実行する | `mise which`が失敗し、導入手順を表示する。PATH上の別のshellcheckで通らない |
| 版違い | `MISE_DATA_DIR`に別の版を入れた一時ディレクトリを使う、または実体の`--version`を偽のスクリプトで置き換える | 版の不一致で失敗する |

`mise install --locked`の失敗側（lockに無い版、チェックサムの不一致）は、一時ディレクトリの複製で確かめる。
リポジトリの`mise.toml`と`mise.lock`は書き換えない。
`mise trust`は、内容を確かめる前に実行しない（NFR-R0109）。

## 9. `mise.lock`の再生成の手順

shellcheckの版を上げるときの手順を、`docs/ローカル実行とCI.md`に書く。

1. `mise.toml`の`shellcheck`の版を、完全な版で書き換える。
2. `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`を実行する。
3. 差分が、shellcheckの4つの環境のURLとSHA256だけであることを確かめる。
4. 4つのSHA256を、公式のGitHubリリースの資産のSHA256（APIの`digest`）と照合して記録する。
5. `mise install --locked`と、品質ゲートを実行する。指摘が増える場合は、先に4節の手順で解消する。

miseの版を上げるときは、`min_version`、CIの`version`、`sha256`を同時に更新する。
`sha256`は、公式の`SHASUMS256.txt`から取る。

## 10. リスクと未確認

| 項目 | 内容 | 対応 |
| --- | --- | --- |
| 品質ゲートの実行時間 | メインが実測した（2026-11-07、Linux aarch64の2コアのEC2）。`shellcheck -s sh -S style`を20ファイルへ実行して約74秒だった（m09が52.6秒、残り19ファイルが21.8秒）。サブエージェントの120秒での停止は、ツールの時間の上限による | 2分では余裕が小さいため、CIの`shellcheck`stepの上限は最初から3分にする（利用者の判断、2026-11-07）。初回CIで実測し、足りなければ上限を見直す。並列化（`xargs -P`）は、出力の順序と終了コードを確かめてから検討する。除外の理由に`-S`の変更は使わない |
| CIの実行時間 | mise本体の取得、shellcheckの導入、実行で何秒増えるか未確認。`shellcheck`stepに3分、job全体は15分の上限。mise-actionのstepには上限を付けない | 初回CIで実測し、`docs/ローカル実行とCI.md`の表へ書く。stepの上限は`timeout-minutes: 3`で足りるかを確かめる。mise-actionのstepの上限は、実測の後に必要なら足す。`sha256`はlinux-x64だけで、runnerがarm64に変わると止まる（安全側）ため、ubuntu-24.04（x86_64）が前提であることを文書に書く |
| mise-actionの`install_args` | `install_args: --locked shellcheck`が受理される形か、`--locked`が重複しないかは、ソースでの確認が初回CIの前に要る | 5.2節のとおり、初回CIの前にソースで確かめ、結果を記録する |
| macOSでのmiseの導入 | Homebrewによる導入と、`mise install --locked`の実機での確認は未実施 | 利用者の端末で確認する。結果を文書に記録する。未確認のまま完了としない（AC-R0101） |
| macOSのxargs | BSDのxargsは、入力が空のとき実行しない。GNUと異なる | 3節の手順で一覧が空でないことを先に確かめるため、差は出ない |
| CIの版の比較 | CIでは実体の`--version`を期待と比べない。`mise.lock`と`--locked`に頼る | `mise.toml`と`mise.lock`の差分のレビューで補う。`run:`が1行に制限される範囲で、比較を足せるか実装時に検討する |
| CIの`run:`の長さ | 環境変数を3つ付けた1行が長い | 短い書き方を実装時に比べる。既存の検査を弱めずに済む方法を優先する。専用のシェルは作らない（NFR-R0101） |
| 設定の自動の信頼 | `mise-action`はPRの`mise.toml`を自動で信頼する | 5.4節のとおり、内容の制限、レビュー、CIの権限で守る。この限界を文書に書く |
| `cache: false`の影響 | 毎回mise本体とshellcheckを取得する | 時間が許容できなければ、キーに`mise.lock`のハッシュを含めるキャッシュを検討する（NFR-R0110）。まず実測する |
| mise lockの再生成 | 版を上げるたびに4つの環境の照合が要る | 9節の手順を文書化する |
| 除外の増加 | 迷う行を除外に寄せると、安全に関わる指摘が隠れる | 4.5節で利用者の判断に上げる。AC-R0107で1件ずつレビューする |
| m09の検査の行の固定 | m09の修正でコメントや行が変わると、他のファイルが引用する行の検査が壊れる可能性 | コミット3ごとにM09 unitを実行して確かめる |
| `source=`の相対パス | `SCRIPTDIR`の基点が、`tests/`と`scripts/`で異なる | ファイルごとに`shellcheck`を実行し、解決されることを確かめる。解決できない行は`source=/dev/null`と理由 |
| 作業中の一時ファイル | 8.1節の確認で、リポジトリ内に一時ファイルを作る | 手順の最後に削除し、`git status --short`で確かめる |

## 11. FR/NFR と設計の対応

| ID | 設計、実装、検証の対応 |
| --- | --- |
| FR-R0101 | `mise.toml`に版、`mise.lock`にURLとSHA256を置く（2節）。CIはmise-action、ローカルは`mise install --locked`（5.2節、5.5節、9節） |
| FR-R0102 | `mise which shellcheck`の実体で実行し、`mise current shellcheck`で期待する版を得る。環境変数3つを明示する（1.1節、3節）。`mise exec`は、未導入のときにPATH上の別のshellcheckで成功するため使わない。取得の失敗は`if !`で受けて`FAILED:`を出す（3節）。未導入と版違いは8.1節で確かめる |
| FR-R0103 | ゲートが`-s sh -S style`を明示して実行し、`sh -n`のループを置き換える（3節、5.1節） |
| FR-R0104 | `git ls-files -z '*.sh'`を一時ファイルへ書き、`xargs -0`で渡す（3節） |
| FR-R0105 | 未導入は成功扱いにせず、導入手順を表示して失敗させる（3節の表） |
| FR-R0106 | `xargs`の終了コードを`status`へ反映する。`\|\| true`を使わない（3節、5.1節） |
| FR-R0107 | 修正または`# shellcheck disable=SCxxxx # 理由`の個別除外（4節） |
| FR-R0108 | 一括の除外をしない。`.shellcheckrc`は4つの設定だけ（2.1節、7節の新しい検査） |
| FR-R0109 | `# shellcheck source=`を行ごとに書く。複数の候補は`source=/dev/null`と理由（4.2節、4.4節） |
| FR-R0110 | `-S style`をゲートと`.shellcheckrc`の両方に明示する（2.1節、3節） |
| FR-R0111 | 最小の変更。迷う行の扱いと、利用者の判断に上げる手順（4.1節、4.5節）。差分をレビューで確かめる |
| FR-R0112 | 一時ファイルによる構文エラーの確認（8.1節）。`git add -N`と`git reset -- <パス>` |
| FR-R0113 | `AGENTS.md`、`docs/ローカル実行とCI.md`、`README.md`を更新する（2節、コミット5） |
| FR-R0114 | `e2e`jobの`unit`の前に`shellcheck`stepと`timeout-minutes: 3`。job名と権限を変えない（5.2節、5.3節） |
| FR-R0115 | mise-actionをコミットSHAで固定し、`version`と`sha256`、`install_args: --locked shellcheck`を明示する（1.1節、5.2節）。`mise.lock`の差分はレビューで確かめる（5.4節） |
| NFR-R0101 | 自前のシェルや解析を作らない。既存のゲートへの呼び出しとCIの1行だけを足す（3節、5.2節） |
| NFR-R0102 | CI、macOS、Linuxで同じ`mise.toml`と`mise.lock`を使い、SHA256で完全性を確かめる（1.1節、5.5節） |
| NFR-R0103 | CIのubuntu-24.04、macOS、Linuxで確認する。macOSは未確認（8節、10節） |
| NFR-R0104 | 既存のゲートの判定を弱めない。壊れる検査は判定を保って更新する（7節） |
| NFR-R0105 | 品質ゲートとCIの実行時間を実測し、文書に書く（3節、10節） |
| NFR-R0106 | 除外のコメントと文書に、AWS識別子、ARN、認証情報、利用者の絶対パスを書かない。M09 unitの識別情報の検査が文書を確かめる（7節） |
| NFR-R0107 | 文書は日本語で、`npm run -s lint:md`で確かめる（6節のコミット5） |
| NFR-R0108 | 一時ファイルは8.1節の手順で削除し、`git status --short`で確かめる |
| NFR-R0109 | `mise.toml`は`min_version`とshellcheckだけ。ほかの設定ファイルを足さない。新しい検査で確かめる（2.1節、5.4節、7節） |
| NFR-R0110 | 4つの環境のSHA256を公式の情報源と照合して記録する。mise本体は`sha256`とminisignで検証する。`cache: false`にする（1.1節、5.5節） |

## 12. ACと設計、タスクの対応

| AC | 設計の対応 | タスク |
| --- | --- | --- |
| AC-R0101 | 1.1節、5.5節、8節 | T-R0104、T-R0138。macOSとLinuxは利用者の端末で確かめる |
| AC-R0102 | 3節、8.1節 | T-R0134、T-R0150 |
| AC-R0103 | 5.2節 | T-R0133、T-R0141 |
| AC-R0104 | 3節、5.1節、8.1節 | T-R0132、T-R0134、T-R0154（構文エラー以外の指摘を含む一時ファイル） |
| AC-R0105 | 8.1節 | T-R0134 |
| AC-R0106 | 4節 | T-R0127、T-R0129、T-R0139 |
| AC-R0107 | 4.1節、4.5節、4.6節 | T-R0117、T-R0128 |
| AC-R0108 | 4.1節 | T-R0116、T-R0117、T-R0128 |
| AC-R0109 | 6章、8節 | T-R0116、T-R0127、T-R0135、T-R0141、T-R0145、T-R0155（最終の差分でM02〜M09のunitとsmokeを記録） |
| AC-R0110 | 2節、コミット5 | T-R0142〜T-R0144、T-R0147 |

## 13. レビューの後の補足（2026-11-07）

- FR-R0102の版の比較は、ローカルの品質ゲートだけで行う。CIは、`install_args: --locked shellcheck`による導入と、mise-actionのSHAと`version`の固定で担保し、版の比較をしない（5.2節と10節の「CIの版の比較」と一致させた）。
- T-R0131でm09へ足す検査は、shellcheckの指摘を出さない書き方にする。コミット4でゲートをshellcheckへ切り替えたとき、追加したコードで失敗しないようにするため。
- shellcheckは変更範囲に関わらず毎回実行するため、文書だけの変更でもmiseが要る。AGENTS.mdの表に書く（T-R0142）。
- `security-review`（planの後）のLow 3件と要確認2件への補足:
  - CIで`mise.toml`の内容の制限を確かめる検査は、mise-actionが設定を自動で信頼した後のunit stepで動く。この検査は事後の検知であり、防御の本体はjobの権限（`contents: read`、Secretsを使わない）とレビューである。`pull_request_target`へ変えないこと、`permissions`を広げないことを、`docs/ローカル実行とCI.md`の限界の記述に書く（T-R0143）。
  - ローカルでmise本体を照合するときは、同じリリースの`SHASUMS256.txt`だけに頼らない。`docs/ローカル実行とCI.md`に、CIの`sha256`と同じ固定の4つの値（環境ごと）を載せ、その値と照合する手順にする（T-R0143）。
  - mise-actionの`github_token`の入力は、既定で`${{ github.token }}`をmiseへ渡す。PRの`mise.toml`のコードから、読み取り専用で短命のトークンが見える。5.4節の「Secretsを読まない」はこの点を除く意味であり、文書にこの点を書く。既定の挙動と、止められるかをT-R0153で確かめる。
  - ローカルで信頼していない`mise.toml`（別のブランチやPRを取得したとき）に対して、`mise current`と`mise which`がどう動くか（エラーか、自動の信頼か）を、T-R0106の実機の確認に含める。手順書にも「差分を確かめるまで`mise trust`しない」と書く（T-R0143）。
  - `install_args: --locked shellcheck`の受け付けと、`--locked`が重複しないことは、T-R0153で初回CIの前に確かめる。
