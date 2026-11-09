# R02〜R05 実装計画

## 1. 設計の要点と方針

自前の検査を、一般的なツール（actionlint、gitleaks、bats-core、jq、yq）に置き換える。
全ての版は`mise.toml`と`mise.lock`で固定し、R01の`shellcheck_gate`と同じ方式で導入と照合を行う。
`spec.md`を要件の正とし、`clarify.md`の決定（Q-R0201〜Q-R0209、FR-R0231〜FR-R0238、AC-R0221〜AC-R0226）は変えない。
このplanは、決定を実装の手順に落とし、実測が要る事項を13章の表に残す。

| 方針 | 対応する要件 |
| --- | --- |
| 5つのツールを`mise.toml`の`[tools]`に完全な版で足し、`mise.lock`の4環境のURLとSHA256を使う | FR-R0228、NFR-R0202 |
| 実行は`mise which <ツール>`の実体で行う。`mise exec`とPATH上の別の実行ファイルは使わない | FR-R0202、FR-R0229 |
| 未導入、版違いは、導入手順つきの`FAILED:`で失敗する。SKIPして成功に数えない | FR-R0229、FR-R0204 |
| 版の照合は1つの関数にまとめ、`shellcheck_gate`と5つの新しいゲートで重複させない | NFR-R0201 |
| 置き換えの前後で判定を弱めない。成功する入力と、契約を壊した入力の両方で旧と新を比べる | NFR-R0204、FR-R0206 |
| YAMLは`yq -e`、JSONは`jq -e`で読む。`null`と`false`は失敗とする | FR-R0233、FR-R0227 |
| gitleaksの規則は独自の2段だけにし、グローバルな除外を置かない | FR-R0236、FR-R0211 |
| 信号の検査の本体は字句のまま移す。`exit`を使う処理は`run`で隔離する | FR-R0234、FR-R0235 |
| 変更は1つのPR、commit 0〜8の順で進め、各commitで品質ゲートが通る | FR-R0238、NFR-R0211 |

### 1.1 R01から引き継ぐ実機の事実

R01のplan（1.1節）で確かめた事実を、そのまま前提にする。新しく確かめた事実はない。

| 事実（R01で確認済み） | このplanでの扱い |
| --- | --- |
| `mise exec`は未導入のときPATH上の別の実行ファイルで成功する | 使わない。`mise which`の実体を実行する |
| 自動の導入を止める設定は`MISE_EXEC_AUTO_INSTALL=false`、`MISE_AUTO_INSTALL=false`、`MISE_LOCKED=1` | 5つのゲートでも、miseを呼ぶ各コマンドへ付ける。`export`はしない |
| `set -eu`の下で`var=$(...)`は失敗時にスクリプトを止める | `if ! var=$(...); then`で受け、`FAILED:`を出してから`status=1`にする |
| `jdx/mise-action`はSHAで固定済み。`install_args`で導入の対象を指定する | `--locked shellcheck`を`--locked`に改める（commit 0） |

### 1.2 このplanの作業で確かめたこと（2026-11-08）

導入とDockerは実行していない。次は`gh api`と`mise`の参照だけで確かめた。

| 項目 | 結果 |
| --- | --- |
| 最新の安定版 | actionlint v1.7.12（2026-03-30）、gitleaks v8.30.1（2026-03-21）、bats-core v1.14.0（2026-07-21）、jq-1.8.2（2026-06-20）、yq v4.54.2（2026-11-06）。`clarify.md`の値と一致し、より新しい版は無い |
| miseのbackend | `mise registry`で、5つともaquaのbackendで引ける。miseは2026.11.3（`min_version`と同じ） |
| bats-coreのaqua定義 | `type: github_archive`。対象は`darwin`と`linux`。配布物はソースのアーカイブで、`bin/bats`を取り出す。ビルド済みのバイナリではない |
| yqのaqua定義 | `type: github_release`。資産名は`yq_<OS>_<Arch>`。チェックサムは`checksums-bsd`のSHA512を参照する |
| mise上のbatsの版 | `mise ls-remote bats`に1.12.0、1.13.0、1.14.0が出る |
| 現状のワークフロー | `jobs.e2e.steps`は10個（checkout、mise-action、shellcheck、unit、test-ci、smoke、contract、collect、upload-artifact、stop）。`t_wf_*`は18関数 |
| 現状の`.bats` | 追跡対象に無い |

## 2. 変更するファイル

| ファイル | 区分 | 変更内容 | commit |
| --- | --- | --- | --- |
| `mise.toml` | 変更 | `[tools]`に`actionlint`、`gitleaks`、`bats`、`jq`、`yq`を足す。`min_version`は変えない。他の節は書かない | 0 |
| `mise.lock` | 変更 | `mise lock`で5つの4環境のURLとSHA256を足す。shellcheckの記録は変わらない | 0 |
| `.github/workflows/e2e-test.yml` | 変更 | `install_args`を`--locked`へ。commit 1と2で`actionlint`と`gitleaks`のstepを足す | 0、1、2 |
| `scripts/quality-gate.sh` | 変更 | 版の照合の関数を1つに共通化し、`actionlint`、`gitleaks`、`bats`、`jq`、`yq`の確認と実行を足す。実行条件に、`tests/bats/`、`tests/lib/run-bats.sh`、`scripts/lib/`、`mise.toml`、`mise.lock`、`.gitleaks.toml`の変更を足す（M09は全て。M02〜M08は対応する`.bats`と共通部分） | 0〜2、4 |
| `scripts/lib/resolve-tool.sh` | 新規 | 版の照合の関数`resolve_tool`の定義だけ。`quality-gate.sh`と`tests/lib/run-bats.sh`が`.`で読み込む（4.2節） | 1 |
| `.gitleaks.toml` | 新規 | 独自の規則2段と、個別の除外 | 2 |
| `tests/m09-execution-and-ci.sh` | 変更 | `t_wf_*`の構造比較への置き換え。`wf_*`の4関数とPyYAMLの分岐の削除。識別情報の検査の削除。最後にbatsへ移し、薄い入口にする | 1、2、3、7 |
| `tests/m08-e2e-suite.sh` | 変更 | `unit_doc`の識別情報の部分の削除。JSONの取り出しをjqへ。最後にbatsへ移し、薄い入口にする | 2、3、6 |
| `tests/m03-wiremock-scenarios.sh` | 変更 | `validate_json`と`validate_mapping`をjqへ | 3 |
| `tests/m07-scenario-isolation.sh` | 変更 | JSONの取り出しをjqへ。後にbatsへ移し、薄い入口にする | 3、5 |
| `tests/s14-taskdef-contract.sh`、`tests/m02`、`m04`、`m05`、`m06` | 変更 | batsへ移し、薄い入口にする（m03も段階1で移す） | 4、5 |
| `tests/bats/*.bats` | 新規 | 移した検査。1ファイルが旧の1ファイルに対応する | 4〜7 |
| `tests/bats/helpers/common.bash` | 新規 | `setup`から読む共通部分（10.2節） | 4 |
| `tests/bats/helpers/fakes.bash` | 新規 | 偽のdockerとawsの用意（`make_base_bin`、`make_fake`、`make_shims`、`no_calls`） | 4（使うのは7） |
| `tests/lib/run-bats.sh` | 新規 | 旧の入口が呼ぶ、batsの薄い起動部。`resolve_tool`を読み込んで使う（10.1節） | 4 |
| `AGENTS.md`、`docs/ローカル実行とCI.md`、`README.md` | 変更 | 各commitの変更に合わせて更新し、commit 8で整合を確かめる | 0〜8 |
| `scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh`、`swsc_mask`、`swsc_collect_scrub` | 変更しない | FR-R0214、FR-R0226 | なし |

`package.json`は、入口を変えない限り変更しない。`.gitignore`は、`gitleaks dir`が`.gitignore`を尊重しない場合だけ検討する（13章）。
`tests/lib/run-bats.sh`は、自前のチェック用シェルではなく、batsを呼ぶだけの起動部である。
置き換えられない理由は、旧の入口（`sh tests/<ファイル> [mode]`）の維持（FR-R0232）が、batsの機能では実現できないためである。
この理由を`docs/ローカル実行とCI.md`に残す。

## 3. 導入（`mise.toml`と`mise.lock`）

### 3.1 `mise.toml`

`min_version`は変えない（`2026.11.3`）。`[tools]`は次のとおりにする。範囲指定と`latest`は使わない。

```toml
min_version = "2026.11.3"

[tools]
actionlint = "1.7.12"
bats = "1.14.0"
gitleaks = "8.30.1"
jq = "1.8.2"
shellcheck = "0.11.0"
yq = "4.54.2"
```

### 3.2 `mise.lock`の作成と確認

| 手順 | 内容 | 失敗時 |
| --- | --- | --- |
| 1 | commit 0の作業の最初に、5つの最新の安定版を`gh api repos/<owner>/<repo>/releases/latest`で確かめ直す | 新しい版があれば、この計画の版を更新して記録する |
| 2 | `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`を実行する | あるツールが4環境の一つで失敗したら、13章の表に載せ、そのツールだけspec.md 5.2のC案を検討する（利用者に諮る） |
| 3 | 差分が、5つの公式のGitHubリリースのURLとSHA256だけであることを確かめる | 公式以外のURLが出たら止める |
| 4 | `checksum_source`が`mise-versions`の項目は、公式の資産のSHA256（APIの`digest`、またはリリースの`checksums`ファイル）と照合して記録する | 不一致なら止める |
| 5 | `mise install --locked`で5つを導入し、各`--version`の出力を記録する | 13章の表の該当項目へ結果を書く |
| 6 | batsの実体（`mise which bats`）で、`@test`を1つ持つ一時の`.bats`を実行する | 失敗したらbatsだけC案を検討する（13章） |

batsは`github_archive`のため、`mise.lock`のURLがソースのアーカイブ（タグのアーカイブ）になる可能性がある。
`mise.lock`のSHA256はそのアーカイブの値になる。記録される値の出所を手順4で確かめ、ビルド済みバイナリのつもりで読まない。

### 3.3 CIの導入

`jdx/mise-action`の`install_args`を`--locked shellcheck`から`--locked`へ改める。これ以外の`with:`（`version`、`sha256`、`cache`、`env`）は変えない。
`--locked`だけにすると、`mise.toml`の全ツールが入る。
mise-actionのソースで、`install_args: --locked`が受理され、`--locked`が重複しないことを、初回のCIの前に確かめる（R01と同じ）。

## 4. 品質ゲートの中での順序

### 4.1 順序

`clarify.md`の5章に従う。共通ゲート、`shellcheck`、`actionlint`、`gitleaks`、Markdown、M02〜M08、S14、M09の順にする。

| 順 | ゲート | 実行の条件 | 追加するcommit |
| --- | --- | --- | --- |
| 1 | 共通（`git diff --check`の3行） | 毎回 | 既存 |
| 2 | `shellcheck` | 毎回 | 既存（R01） |
| 3 | `actionlint` | 毎回 | 1 |
| 4 | `gitleaks` | 毎回 | 2 |
| 5 | Markdown | `.md`などの変更があるとき | 既存 |
| 6 | M02〜M08、S14、M09（`bats`を内部で使う） | 既存の条件 | 4〜7（入口は同じ） |

`bats`、`jq`、`yq`は、独立したゲートを作らない。これらの存在と版は、使う側（M02〜M09の入口、2.2の`tests/lib/run-bats.sh`）が、
同じ照合の関数で確かめる。ただし、使い始めるcommitで、導入済みで版が合うことを先頭の確認として足す（4.3節）。
`jq`と`yq`を使う`unit`は、ゲートの先頭の確認で失敗が分かるため、利用者が導入を忘れても、原因が分かる表示になる。

### 4.2 共通の関数

`shellcheck_gate`の版の照合の部分を、関数`resolve_tool`へ抜き出す。ゲートごとの関数が重複しない形にする。

| 項目 | 内容 |
| --- | --- |
| 入力 | ツール名、版を取り出す式、版の確認のコマンド（`--version`など）の別 |
| 処理 | `command -v mise`、`mise current <ツール>`で期待する版、`mise which <ツール>`で実体のパス、版の出力から版を取り出して比べる |
| 結果 | 実体のパスを変数に入れる。失敗したら、導入手順つきの`FAILED:`を出し、`status=1`にして`return 0`する |
| 失敗の文言 | R01と同じ3種（miseが無い、ツールが未導入、版が違う）。ツール名だけ差し替える |
| 環境変数 | `MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1`を、miseを呼ぶ各コマンドに付ける |

ツールごとに版の表示が違う。`--version`の出力の形（actionlintは`1.7.12`の行、gitleaksは`version`サブコマンド、
batsは`Bats 1.14.0`、jqは`jq-1.8.2`、yqは`... version v4.54.2`の想定）は、推測で書かない。
commit 0で5つの実際の出力を記録し、取り出す式と`mise current`の値（`jq`は`1.8.2`か`jq-1.8.2`か）の対応を決める（13章）。
取り出す式は`sed -n 's/…/\1/p'`の1行にとどめ、新しい解析の部品は作らない。

`resolve_tool`は、`scripts/lib/resolve-tool.sh`（新規。関数の定義だけで、読み込んでも副作用がない）に置く。
`scripts/quality-gate.sh`と`tests/lib/run-bats.sh`が、どちらも`.`で読み込む。比べた案と選んだ理由は次のとおり。

| 案 | 判断 |
| --- | --- |
| 共有ファイルに置いて両方が読む（採用） | 重複しない（NFR-R0201）。入口を直接実行したとき（CIの`unit`のstepを含む）も、未導入と版違いを導入手順つきで失敗にできる（FR-R0229） |
| `run-bats.sh`に複製する | 重複し、NFR-R0201と4.2節の方針に反する |
| `run-bats.sh`は版を確かめず、ゲートの先頭の確認に任せる | 入口を直接実行したとき、版違いが分からず、FR-R0229に反する |
| `quality-gate.sh`を`source`する | 末尾でゲートを実行する副作用の有無が文書から確かめられない（未確認）。読み込むだけで済む形にできない |

この関数は新しい検査ではなく、R01の`shellcheck_gate`の照合を移したものである。miseの実体と版を、導入手順つきの表示で照合する処理は、
一般的なツールで代えられない。

### 4.3 各ゲートの形と失敗時の表示

| ゲート | 実行 | 失敗時の表示（要点） |
| --- | --- | --- |
| `actionlint` | `git ls-files -z '.github/workflows/*.yml' '.github/workflows/*.yaml'`を一時ファイルへ書く。0件は失敗。ファイルを引数に渡す形か、引数なしの探索かは13章のU11で実測して決める | `FAILED: actionlintが未導入。mise install --lockedを実行する`。版違いは期待と実際を出す |
| `gitleaks` | `<実体> dir . --config .gitleaks.toml --redact --no-banner --exit-code 1`（FR-R0237）。終了コードを`status`へ反映する。`\|\| true`を使わない | `FAILED: gitleaksが未導入。...`。検出は`--redact`で値を出さない |
| 先頭の確認 | `bats`、`jq`、`yq`の実体と版を`resolve_tool`で確かめる（commit 0で`jq`と`yq`と`bats`は使われないため、使い始めるcommitで足す） | 導入手順つきの`FAILED:` |

`git ls-files`は、R01と同じく一時ファイルへ書き、終了コードを見る。パイプにしない。空の一覧は成功にしない。
`actionlint`と`gitleaks`の実行は、`run`関数（既存）で包み、終了コードを`status`へ反映する。
`shellcheck_gate`の`trap`は、各関数で閉じる（R01と同じ）。関数が増えても、`trap`が上書きされないよう、一時ファイルは関数ごとに作って消す。

## 5. CIのstep

`clarify.md`の5章の順序と上限を、そのまま適用する。

| 順 | step | `timeout-minutes` | 追加するcommit |
| --- | --- | --- | --- |
| 1 | checkout | なし | 既存 |
| 2 | mise-action（`install_args: --locked`） | なし | 0（`install_args`の変更） |
| 3 | `shellcheck` | 3 | 既存 |
| 4 | `actionlint` | 2 | 1 |
| 5 | `gitleaks` | 2 | 2 |
| 6 | `unit` | 3 | 既存 |
| 7 | `test-ci` | 10 | 既存 |
| 8 | `smoke` | 8 | 既存 |
| 9 | `contract` | 5 | 既存 |
| 10 | `collect`（`if: always()`） | なし | 既存 |
| 11 | upload-artifact（`if: failure()`） | なし | 既存 |
| 12 | `stop`（`if: always()`） | なし | 既存 |

| 項目 | 内容 |
| --- | --- |
| batsのstep | 作らない。`unit`、`smoke`、`contract`の既存のstepが、薄い入口を通して`bats`を呼ぶ |
| `run:`の形 | 式（`${{`）を含めない。1行にする。`uses:`は増やさない（NFR-R0208） |
| `actionlint`の`run:` | `git ls-files`の結果を渡す形か、引数なしで`.github/workflows/`を探索させる形かを、13章の実測で決める。実体のパスは`mise which actionlint`で得る |
| `gitleaks`の`run:` | 4.3節と同じ引数。実体のパスは`mise which gitleaks`で得る |
| 上限 | 2分は`clarify.md`の値。初回のCIの実測が1分未満なら据え置き、超えたら上げる。合計がjobの15分に収まることを、実測で確かめる |
| 不変 | job名`e2e`、ほかのstep名、`permissions: contents: read`、`persist-credentials: false`、ダミー認証情報の`env`を変えない |

## 6. 段階の計画

### 6.1 R04の段階とcommit

`clarify.md`の2章の4段階を、commit 4〜7に1対1で置く。各段階の最後に、検査の数と判定の一致を確かめてから、次の段階へ進む。

| 段階 | commit | 対象 | 先に済ませる置き換え |
| --- | --- | --- | --- |
| 1 | 4 | `s14`、`m02`〜`m05` | m03のJSON（commit 3で済み） |
| 2 | 5 | `m06`、`m07` | m07のJSON（commit 3で済み） |
| 3 | 6 | `m08` | m08の識別情報の部分（commit 2で済み）、JSON（commit 3で済み） |
| 4 | 7 | `m09` | `t_wf_*`（commit 1）、識別情報（commit 2）、JSON（commit 3） |

R02、R03、R05を先に済ませる理由は、batsへ移す前に、同じ検査を二度書き換えないためである（`clarify.md`の8章）。

### 6.2 各段階の後の確認

| 確認 | 方法 | 一致しないとき |
| --- | --- | --- |
| 旧の記録 | 段階を始める前に、旧のファイルを実行し、検査名と判定の一覧、件数、終了コードを`$KIROCREW_SCRATCH`に保存する（コミットしない） | 旧が失敗しているなら、先に原因を調べる |
| 件数 | `bats --count`の値と、旧の件数が一致する | その段階を直す。次へ進まない |
| 名前 | 旧の検査名を、`@test`の名前にそのまま使う。名前の一覧を`diff`で比べる | 差分を表に残し、理由を書く |
| 成功の入力 | 全ての`@test`が通る | 直す |
| 壊した入力 | 6.4節の方法で、旧と新が同じ検査で落ちる | 直す |
| 入口 | `sh tests/<ファイル> [mode]`の終了コードが、旧と同じ（AC-R0222） | 直す |
| 実行時間 | 旧と新を記録する（NFR-R0205） | CIの15分に収まらないなら、内容を見直す |
| Docker | 段階1のm02〜m05とm09のsmokeは、Dockerのある環境で確かめる（12章） | 実行できなかったものは「未確認」と書く |

### 6.3 旧の検査名と`@test`名の対応表の作り方

対応表は、段階ごとに`specs/R02-R05-tool-replacement/verification/phase-N-mapping.md`へ書く。次の手順で、手作業の転記を避ける。

| 手順 | 内容 |
| --- | --- |
| 1 | 旧の出力から、検査名の一覧を取り出す。`check`、`must`、`expect`、`expect_*`が出力する名前の形式は、段階の開始時に実際の出力で確かめる |
| 2 | `@test`の名前に、旧の名前をそのまま使う。1つの旧の検査が複数の`@test`に分かれる場合と、複数が1つに集まる場合は、その理由を表に書く |
| 3 | `bats --count`と、`grep -c '^@test'`の値が一致することを確かめる |
| 4 | 表の列は、旧のファイルと行、旧の名前、新のファイルと`@test`名、判定の一致（成功、壊した入力）とする |
| 5 | コミットに含めるのは、表の本文だけとする。旧の実行の生ログは含めない |

現状の件数（`clarify.md`の2章）は次のとおり。段階の開始時に、旧の出力で数え直し、ずれを表に残す。

| ファイル | 現状 | 備考 |
| --- | --- | --- |
| `s14` | `check` 5件 | `check`関数あり |
| `m02`、`m04`、`m05` | `check`なし | 直列のスクリプト。連続する確認を`@test`に区切る方法を、旧の出力の単位で決める（13章） |
| `m03` | `check_body`、`check_delay`あり | 件数は旧の出力で数える |
| `m06` | `expect`が主 | 検査名、期待出力、期待終了コードの3つを`@test`で保つ（6.2節） |
| `m07` | `check` 19件 | `expect_rc`、`expect_out`、`expect_err`を含む |
| `m08` | `check` 30件 | |
| `m09` | 仮の数字: 静的な行数は227、`clarify.md`は234。実機の旧の出力で確定するまで、どちらも仮の数字で、一方を正としない | モード別（`unit`、`smoke`、`contract`）の実行時の件数を、段階4の開始時（T-R0316）に旧の出力で数えて確定する。静的な行数は実行時の件数と一致しない（smokeとcontractの項目は包みの行から複数回呼ばれる）。234の出所も記録する（13章） |

### 6.4 壊した入力で判定の一致を確かめる方法

旧と新の両方に、同じ壊した入力を与え、同じ検査名が落ちることを比べる。壊した入力は一時ファイルで作り、リポジトリを書き換えない。

| 対象 | 壊し方の例 | 期待 |
| --- | --- | --- |
| ワークフロー | 7.4節の表の壊した定義 | 旧の`t_wf_*`と新の構造比較が、同じ契約で落ちる |
| 識別情報 | 実行時に組み立てた実在しない値（NFR-R0206）を一時ファイルに入れる | gitleaksが落ち、値が出力に出ない |
| JSON | 壊れたJSON、キーの欠落、空の配列、`null` | 旧と新が同じ終了コード |
| テストの枠組み | 偽のdockerを失敗させる、期待出力を変える | 旧と新の同じ検査が落ちる |

## 7. R02（actionlintと構造比較）の設計

### 7.1 actionlint

4.3節のとおり、全ワークフローを検査し、終了コードを反映する（FR-R0201、FR-R0202）。
actionlintは`run:`のシェルを、`shellcheck`が実行できる環境ではそれで検査する。`mise`が入れたshellcheckがPATHにあるとき、
actionlintはそれを使う可能性がある。`.shellcheckrc`との関係と、既存の`run:`に指摘が出るかを、13章の実測で決める。
指摘が出た場合は、ワークフローの中身を変えない（FR-R0207）ため、actionlintの`-ignore`で個別に除外し、理由を書く。
式の誤りを含む一時のワークフローで、actionlintが失敗することを確かめる（AC-R0205）。

### 7.2 構造比較の方式

`yq -e`でYAMLを読み、契約を比べる。`yq`の実体は`mise which yq`で得て、テストの`setup`で変数に入れる。

| 項目 | 内容 |
| --- | --- |
| 読み方 | `yq -e '<式>' "$WF"`。結果が`null`または`false`なら終了コード1 |
| `on`キー | YAML 1.2として読まれるため、`True`の分岐は要らない（`clarify.md`の1章）。実機で`on`が文字列のまま読めることを確かめる（13章） |
| 比較の単位 | 契約ごとに1つの式にする。複数の契約を1つの式にまとめない。落ちたときに、どの契約かが分かるようにする |
| 順序 | stepの名前の並びは、`.jobs.e2e.steps[] \| (.name // .uses)`を配列にして比べる |
| 弱めない | 旧は行の完全一致だった。新は構造の一致にし、値の取りこぼしを防ぐため、式の結果が空のときも失敗にする（`-e`） |

### 7.3 契約と式の対応

`t_wf_*`の18関数を、次の契約に割り当てる。式は実装時に書き、ここでは検査する値だけを固定する。
`t_wf_yaml_parses_with_expected_shape`の内容は、他の契約に分解して吸収する。PyYAMLの`import`と、SKIPの表示は残さない（FR-R0204）。

| 旧の`t_wf_*` | 新の契約（読む箇所） | 検査する値 |
| --- | --- | --- |
| `file_exists` | ファイルの存在 | `.github/workflows/e2e-test.yml`が読める |
| `triggers_are_pull_request_and_main_push_only` | `.on` | `pull_request`と`push.branches == ["main"]`だけ |
| `permissions_are_contents_read_only` | `.permissions`と各jobの`permissions` | `{"contents": "read"}`。jobに別の権限が無い |
| `dummy_credentials_are_workflow_env_only` | `.env` | 3つのダミーの値だけ。jobとstepに`env`が無い |
| `concurrency_groups_pr_by_ref_and_pushes_by_sha` | `.concurrency` | `group`と`cancel-in-progress`の式 |
| `step_timeouts_are_…` | `.jobs.e2e.steps[]`の`timeout-minutes` | shellcheck 3、actionlint 2、gitleaks 2、unit 3、test-ci 10、smoke 8、contract 5。jobは15 |
| `collect_always_upload_on_failure_stop_always` | `if` | collectとstopが`always()`、uploadが`failure()` |
| `uploads_logs_with_fixed_name_path_and_seven_day_retention` | upload-artifactの`with` | name、path、`retention-days: 7`、`if-no-files-found` |
| `never_reads_secrets_context` | 全体の文字列 | `secrets`の参照が無い |
| `run_lines_have_no_expression_or_block_scalar` | 各stepの`run` | `${{`を含まない。1行 |
| `expressions_only_in_concurrency_and_artifact_name` | 全体 | `${{`を持つ箇所が2つだけ |
| `uses_checkout_mise_action_and_upload_artifact` | `uses` | 3つ。それぞれが40桁のSHAで固定され、`# v`のコメントを持つ |
| `checkout_does_not_persist_credentials` | checkoutの`with` | `persist-credentials: false` |
| `steps_run_in_plan_order` | stepの並び | 5章の順（`uses`のstepは名前の代わりにactionの名前を使う） |
| `each_step_runs_its_command` | 各stepの`run` | 各stepのコマンド（`shellcheck`、`actionlint`、`gitleaks`の引数を含む） |
| `has_no_docker_compose_call` | `run` | `docker compose`を含まない |
| `job_runs_on_ubuntu_2404_with_15_minute_limit` | `.jobs.e2e.runs-on`と`.jobs.e2e.timeout-minutes` | `ubuntu-24.04`と15 |
| `yaml_parses_with_expected_shape` | 上の各契約に分解 | job名`e2e`、stepの数（commit 1で11個、commit 2で12個） |
| （`t_wf_*`以外で、ワークフローを読む検査） | 段階4の開始時に、`grep`で一覧にして割り当てる | |

コメント（`# v7.0.1`など）はYAMLの構造として読めない。コメントの有無を確かめる契約だけは、構造比較ではなく
`grep -Eq`で行う。これを、構造比較へ寄せられない箇所として表に残し、理由を書く。
SHAの固定は、`uses`の値を`yq`で取り出して正規表現で比べる。

### 7.4 壊した定義（AC-R0204）

契約ごとに少なくとも1つ、一時ファイルで作る。作り方は`yq -i`ではなく、一時ファイルへ`sed`で書き換える。
旧のテストの`sed`による壊し方（m09の`tpl.json`の例）に倣う。

| 契約 | 壊した定義 | 期待 |
| --- | --- | --- |
| permissions | `contents: read`を`write`に変える | 落ちる |
| timeout | stepの`timeout-minutes`を消す、または値を変える | 落ちる |
| `if: always()` | collectの`if`を消す | 落ちる |
| SHA固定 | `uses`のSHAをタグ（`@v4`など）に変える | 落ちる |
| Secrets | `${{ secrets.X }}`を足す | 落ちる |
| stepの並び | unitとtest-ciを入れ替える | 落ちる |
| trigger | `pull_request_target`を足す | 落ちる |
| `persist-credentials` | `false`を`true`に変える | 落ちる |
| 式 | `run`に`${{ github.x }}`を足す | 落ちる |
| artifactの保持 | `retention-days`を変える | 落ちる |

同じ壊した定義を旧の`t_wf_*`にも与え、旧と新が同じ契約で落ちることを比べる（11章）。

## 8. R03（gitleaks）の設計

### 8.1 `.gitleaks.toml`の規則

既定の規則は使わない（`[extend] useDefault`を書かない）。規則は独自の2段だけにする（`clarify.md`の7章）。

| 段 | 規則のid | `path` | `regex`の方針 |
| --- | --- | --- | --- |
| 1 | 12桁、`arn:aws`、`AKIA`の3つ | 置き換え前の11ファイルに限る。ファイルごとの完全一致の正規表現を並べる | 置き換え前の`grep -E`と同じ文字列。`[0-9]{12}`、`arn:aws`、`AKIA` |
| 2 | ARN、アクセスキー、アカウントIDの3つ | 指定しない（追跡対象の全体） | ARN: `arn:aws`に続くパーティション、サービス、リージョン、12桁のアカウント。アクセスキー: `AKIA`または`ASIA`に続く英大文字と数字の16文字。アカウントID: `account`や`aws`などの語が近くにある12桁 |

| 項目 | 内容 |
| --- | --- |
| 11ファイル | M09の10ファイルと`docs/E2Eテスト.md`。2.1節のFR-R0210の列挙と同じ |
| 段2の`path` | 指定しない。11ファイルは段1と段2の両方で検査される。重複して検出しても害は無く、構造上の除外を増やさずに済む |
| 正規表現の最終形 | 実装時に書く。ここでは形の方針だけを固定する。最終形は、8.3節の壊した入力と、実際の検出の実測で確かめる |
| `.gitleaks.toml`自身 | 段1の`path`に含めない。規則の文字列を持つため、段2の値の形に合わないことを実測で確かめる |
| `description` | 置き換え元（`t_doc_has_no_identity_values`、`unit_doc`）を書く |
| 禁止 | `[extend] useDefault`、グローバルな`[allowlist]`、`stopwords`、ファイル全体を全規則から外す除外 |
| 値の出力 | `--redact`で出さない。`gitleaks`の設定に、値を出力する`report`の形式を使わない |

### 8.2 誤検知の除外

除外は、規則ごとの`[[rules.allowlists]]`に1件ずつ書く。`paths`と`regexes`を`condition = "AND"`で絞り、`description`に理由を書く。

| 手順 | 内容 |
| --- | --- |
| 1 | 規則を置いた状態で`gitleaks dir`を実行し、検出の一覧を取る（`--redact`を付けたまま、ファイルと行と規則のid） |
| 2 | 検出の一覧を、11ファイルの内と外に分ける |
| 3 | 11ファイルの内の検出は、原則として除外せず、ファイル側を直す |
| 4 | 11ファイルの外の検出（`tests/m07`、`tests/m08`、`tests/m09`、`scripts/e2e-lib.sh`など）は、先に実行時に値を組み立てる形に直せるかを確かめる |
| 5 | 直せない行だけを、`paths`（そのファイル）と`regexes`（その行の文字列）で絞る除外にする |
| 6 | 除外の全件（規則、パス、文字列、理由）を、この章の表に列挙する（AC-R0209） |

除外の一覧（commit 2で埋める）:

| 規則 | パス | 文字列 | 理由 |
| --- | --- | --- | --- |
| （実測の後に記入。0件の可能性がある） | | | |

### 8.3 導入の確認と壊した入力

| 確認 | 方法 | 期待 |
| --- | --- | --- |
| 版 | `mise which gitleaks`の実体の版を、期待と比べる | 一致 |
| 12桁のID | 実行時に`printf`で組み立てた12桁の数字を、一時ファイルへ書く | 品質ゲートが失敗し、出力に値が出ない |
| ARN | 実行時に`arn:`と`aws:`などを連結して組み立てる | 同上 |
| アクセスキー | 実行時に`AKI`と`A`とダミーの16文字を連結して組み立てる | 同上 |
| 範囲 | 11ファイルの各ファイルに、上の値を一つずつ入れる | 各ファイルで失敗する（段1が効く） |
| 範囲外 | `specs/`の文書に`arn:aws`の語だけを書く | 失敗しない（段2が値の形に絞られる） |

検出の確認は、手動確認に加えて、永続するunit（`t_gitleaks_rules_detect_runtime_built_values`、T-R0347）にする。
段1の`path`が一時ディレクトリの相対パスに当たるかはU8、U9で決める。当たらない場合は、段2の3種類だけをunitにし、
段1の11ファイルぶんは手動確認（T-R0343、T-R0246）に残す。この場合の理由を、U9の結果の後にここへ書く。
式の誤りでactionlintが落ちることも、永続するunit（`t_actionlint_rejects_expression_error`、T-R0348）で確かめる。

一時ファイルは、追跡対象に入れる必要があるかを13章の実測で決める（`gitleaks dir`が`git ls-files`ではなくディレクトリを走査する場合は、
追跡対象に入れずに検出できる）。入れる場合は`git add -N`で入れ、`git reset -- <パス>`で外す（R01の8.1節と同じ）。

### 8.4 置き換える検査

`t_doc_has_no_identity_values`（m09）と、`unit_doc`（m08）の識別情報の部分（`[0-9]{12}`と`arn:aws`の2つの`grep`）を削除する。
`unit_doc`のシナリオ名と禁止の形の検査は残す。`swsc_mask`と`swsc_collect_scrub`は変えない（FR-R0214）。
削除の前に、gitleaksの検査が品質ゲートに入っていて、旧の検査と同じ範囲以上を検査していることを確かめる（AC-R0207）。

### 8.5 `.gitignore`との関係

`gitleaks dir`は`.gitignore`を尊重しない（13章 U7、確認済み）。このため、追跡対象でない生成物（`node_modules/`、`e2e-logs/`）だけを、
必要になった場合に限り、規則の`allowlist`にパスと理由つきで書く（FR-R0237）。この2つ以外のパスの除外は書かない。
実測（`verification/phase-2-results.md` 3章）: 作業ツリー全体（`node_modules/`と`e2e-logs/`を含む、実在するもの）を走査し、検出は0件だった。
このため、除外は書かない（T-R0240は省略する）。将来、`node_modules/`や`e2e-logs/`に識別情報の形が現れて誤検知が起きたときに、理由つきでallowlistを足す。

## 9. R05（jq）の設計

### 9.1 範囲

FR-R0224〜FR-R0227に従う。置き換えるのは、JSONの単純な値の取り出しだけである。
JSONでない出力（ログの`key=value`の行など）を`sed`で取り出す箇所は、置き換えない（FR-R0225）。

### 9.2 置き換えの対象の一覧（現時点で確認した箇所）

行番号は、このplanを書いた時点の値である。commit 3の作業の開始時に、`grep`で全体を数え直し、この表を更新する（FR-R0227）。

| ファイル | 場所 | 旧の取り出し | 新の式（方針） | 空、null、壊れたJSON |
| --- | --- | --- | --- | --- |
| `tests/m03-wiremock-scenarios.sh` | `validate_json` | `python3`で`json.load` | `jq -e . "$1" >/dev/null` | 壊れたJSONで失敗（同じ） |
| `tests/m03-wiremock-scenarios.sh` | `validate_mapping` | `python3`で必須のキーを確認 | `jq -e '(.request \| has("method") and has("urlPath")) and (.response \| has("status"))'`の形 | キーの欠落で失敗。旧の欠落の表示は、必要なら`jq`の別の式で保つ |
| `tests/m07-scenario-isolation.sh` | 約216行（`error-500-then-200`の2つの定義の比較） | `python3`の埋め込み | `jq -e`で`name`、`scenarioName`、`request`の各値を比べる | 欠落と不一致で失敗 |
| `tests/m07-scenario-isolation.sh` | 約448行（`name`から`urlPath`を取る） | `python3 -c`の1行 | `jq -r --arg n "$2" '.mappings[] \| select(.name==$n) \| .request.urlPath'`。旧は見つからなければ空 | 見つからないときの扱い（空を返すか失敗か）を旧と同じにする。`-e`の使い分けは箇所ごとに決める |
| `tests/m08-e2e-suite.sh` | 約617行（`"count"`を`sed`で取る） | `sed -n 's/.*"count" *: *\(…\)/\1/p'` | `jq -e '.count'` | 空は旧も失敗（`[ -n "$_n" ]`）。`null`も失敗 |
| `tests/m09-execution-and-ci.sh` | `python3 -c`でJSONを読む箇所（約317、326、336、412、424、765、825、1230、2106行など） | `python3`の埋め込み | 単純な値の取り出しと条件つきの選択だけ`jq -e`へ。`e2e-taskdef.py`を呼ぶ箇所は変えない | 箇所ごとに表へ追記する |

置き換えない箇所（理由）:

| ファイル | 場所 | 理由 |
| --- | --- | --- |
| `tests/m07`の約284行 | Markdownの文書からコードブロックを取り出す | JSONの取り出しではなく、Markdownの処理である |
| `tests/m07`の約425、486行、`tests/m08`の約526〜537行 | `key=value`の行を`sed`で取り出す | JSONでない出力（FR-R0225） |
| `tests/m07`、`tests/m08`、`tests/m09`の信号の検査の`python3` | `signal`を使う処理 | 信号の検査は字句のまま保つ（FR-R0234） |
| `tests/m09`の`sed 's/"family": …'`など | 壊したテンプレートを作る文字列の置換 | 値の取り出しではなく、壊した入力の生成である |
| `scripts/e2e-taskdef.py`、`scripts/scenario-lib.sh` | 複雑な整合検査 | FR-R0226 |

### 9.3 判定の維持

置き換えごとに、次の4つの入力で、旧と新の終了コードを比べる。

| 入力 | 期待 |
| --- | --- |
| 現在の正しい入力 | 旧と新がともに成功 |
| 壊れたJSON | ともに失敗 |
| キーの欠落 | ともに失敗 |
| 空の配列、`null` | ともに失敗（旧が成功する箇所は、旧の判定を保つ） |

結果を、置き換えの一覧の表に追記する（AC-R0216）。
`jq`の実体は、テストの`setup`で`mise which jq`から得る。`jq`の実行時に`-e`を付け、`null`と`false`を失敗にする。

## 10. R04（bats-core）の設計

### 10.1 入口

旧の入口（`sh tests/<ファイル> [unit|smoke|contract]`）は、同じ名前、引数、終了コードで残す（FR-R0232）。
各`tests/<ファイル>.sh`は、`tests/lib/run-bats.sh`を呼ぶ薄い入口にする。

| 項目 | 内容 |
| --- | --- |
| 引数の検査 | 引数の数とモードの値を検査し、不正なら終了コード2（旧と同じ文言）。この検査は旧のまま入口に残す |
| bats | `scripts/lib/resolve-tool.sh`の`resolve_tool`を`.`で読み込み、同じ関数で実体と版を得る（4.2節。複製しない）。未導入と版違いは導入手順つきで失敗する |
| 既定のモード | 引数なしのときの既定を、旧のまま保つ。確認できた旧の既定は、`m06`、`m07`、`m09`が`smoke`（`MODE=${1:-smoke}`）、`s14`が`unit`のみ（`unit`以外は不正）。`m08`の既定は`smoke`（`_mode=smoke`。T-R0305で確認し、`verification/phase-6-mapping.md`の1章に記録）。`m02`〜`m05`の既定は未確認で、各段階の開始時（T-R0272）に旧の入口から読み取り、この表に足す。品質ゲートはM02〜M08を引数なしで呼ぶ。`run-bats.sh`と薄い入口は、同じ既定を保つ |
| 絞り込み | `--filter-tags <mode>`。タグは`# bats test_tags=unit`の形で付ける。`--filter-tags`の対応は13章で確かめる |
| 終了コード | batsの終了コードをそのまま返す（FR-R0222） |
| シェル | 入口は`sh`、中身は`bash`。macOSのbash 3.2とubuntuのbashで動くかを13章で確かめる |
| 信号 | 前面のシェルで実行する前提は、旧の冒頭の検査（22〜29行）と同じ。`setup_file`に移し、同じ文言で失敗させる（`clarify.md`の6.1） |

### 10.2 `setup`と`helpers`

旧の9ファイルが各自で持つ共通部分を、`tests/bats/helpers/`へ1回だけ置く。移した後、重複する定義は残さない（AC-R0213）。

| 旧の共通部分 | 新しい置き場 | batsでの形 |
| --- | --- | --- |
| `total`、`failures`、結果の集計 | なし | batsの集計に任せる |
| `check`（名前、関数） | `@test`の名前と本体 | 旧の名前を`@test`の名前にする |
| `must`（コマンドが成功すること） | `@test`の本体 | コマンドを直接書く。失敗で`@test`が落ちる |
| `rc_is`（終了コードの検査） | `run`と`[ "$status" -eq N ]` | `run`で隔離する |
| `expect`（m06。名前、期待出力、期待終了コード、コマンド） | `run`、`[ "$output" = … ]`、`[ "$status" -eq N ]` | 3つを全て保つ（6.2節） |
| `expect_rc`、`expect_out`、`expect_err`（m07） | 同上 | 同上 |
| `make_base_bin`、`make_fake`、`make_shims`、`no_calls`、`run_e2e` | `helpers/fakes.bash` | `setup`から`load`する |
| `trap cleanup EXIT` | `teardown_file`、`teardown` | コンテナの削除は、後始末の漏れを`managed_check`が検出する |
| 一時ディレクトリ（`TMP`、`SWSC_TEST_DIR`） | `setup`で`mktemp -d`、`teardown`で削除 | `BATS_TEST_TMPDIR`を使えるか13章で確かめる |

`bats-support`と`bats-assert`は使わない（`clarify.md`の10章）。`run`、`[ ... ]`、`$status`、`$output`で足りない箇所が出たら、
その箇所と版の固定の方法を表に書いて、利用者に諮る。

### 10.3 `run`による隔離（`exit`と信号）

| 項目 | 内容 |
| --- | --- |
| `exit`を使う関数 | `run <関数>`で呼ぶ。サブシェルで実行され、`exit`が`@test`全体を止めない。判定は`$status` |
| スクリプトの`exit` | 旧の末尾の`exit 0`、`exit 1`は、`@test`の成否で表す。`setup_file`と`teardown_file`で前後の処理を担う |
| 信号の検査 | `lib_call`経由の`kill -INT $$`、`kill -TERM $$`と、Pythonの`signal`を使う関数は、本体を字句のまま移す。呼び出しだけを`@test`にし、`run`で実行して終了コードを見る |
| 信号の一覧 | commit 4〜7の各段階の開始時に、`grep -n 'kill -INT\|kill -TERM\|signal\.SIG'`で全件を数え、この表へ追記する（FR-R0234） |
| `bats`が信号を受けたとき | `teardown_file`が走らないことがある。後始末の漏れは、品質ゲートの`managed_check`が検出する |

現時点の信号の検査の所在（行番号は目安）:

| ファイル | 内容 |
| --- | --- |
| `tests/m07` | `unit_signal_exit_codes`（約375行）。Pythonの`signal`（約594〜609行） |
| `tests/m08` | 信号の検査は2件（`check`の`INT`と`TERM`、`smoke_case_signal`）。Pythonの`signal`（約949〜1011行）。`kill -INT`、`kill -TERM`は無い（T-R0305で確認） |
| `tests/m09` | 冒頭の`SIGINT`無視の検査（約27行）。`kill -TERM "$PPID_PARENT"`（約190行）。偽のawsの`kill -INT "$PPID"`、`kill -TERM "$PPID"`（約749行）。`lib_call`経由の`kill`（約1806、1834、1846、1890、3551〜3628行）。Pythonの`signal`（約2171行） |

### 10.4 shellcheckとの関係

`.bats`は、シェルの記法が拡張されている。`shellcheck`のゲートの対象に含めるかは未確認で、13章で実測して決める。
`shellcheck -s bats`が使えれば、`git ls-files -z '*.bats'`を別の呼び出しで足す。使えなければ、`.bash`の補助だけを`-s bash`で検査し、
`.bats`を対象外にする理由を文書に残す。推測では決めない。

## 11. 壊れる既存の検査と直し方

### 11.1 m09の`t_wf_*`（R02）

7.3節の表のとおり、18関数を構造比較へ置き換える。判定が同じことを、次の3つで確かめる。

| 確認 | 方法 |
| --- | --- |
| 現在のワークフロー | 旧の18関数が全て通る入力で、新の契約もすべて通る |
| 壊した定義 | 7.4節の各定義に旧と新を実行し、同じ契約が落ちる。表にして残す |
| 取りこぼし | 旧の関数が固定していた行（`awk`の範囲、完全一致）を一つずつ列挙し、新の式が同じ値を読んでいることを確かめる。新しい式が読めていない値があれば、式を足す |

置き換え後、`wf_block`、`wf_has_line`、`wf_top_block`、`wf_step_timeout`と`import yaml`が残っていないことを、`git grep`で確かめる（AC-R0202）。

### 11.2 commit 1〜2で追加するstepによる影響

`actionlint`と`gitleaks`のstepを足すと、次の検査が壊れる。R01で`shellcheck`を足したときと同じ形で直す。

| 検査 | 壊れる理由 | 直し方 |
| --- | --- | --- |
| `t_wf_steps_run_in_plan_order` | stepの名前の並びを固定している | 5章の順（`actionlint`、`gitleaks`を足した12個）に直す。構造比較の中で行う |
| `t_ci_test_ci_scenarios` | 名前付きのstepの数を固定している | 数を上げる。job名`e2e`と`smoke`、`contract`のstep名が変わらない確認は残す |
| `t_wf_step_timeouts_…` | 名前に`shellcheck3_unit3_…`と書いている | `actionlint2`と`gitleaks2`を加える |
| `t_wf_each_step_runs_its_command` | 各stepの`run`を固定している | 追加するstepの`run`を加える |
| `t_wf_yaml_parses_with_expected_shape` | step数を固定している | 構造比較に吸収する。step数は、commit 1で11個、commit 2で12個にする |

commit 0の`install_args`の変更で、`install_args`の値を固定している検査があれば、同じcommitで直す。
`t_wf_dummy_credentials_are_workflow_env_only`は、`env:`が1つのままであることを裏づけるため、変えない。

### 11.3 ゲートの検査

`t_gate_*`は、新しいゲートの行を足しても壊れないことを、R01と同じ理由（M09のブロックの先頭、`|| true`の不在、`for test in`の行の不変）で確かめる。
新しい検査として、次を足す（静的な確認だけ）。

| 検査 | 内容 |
| --- | --- |
| `t_gate_runs_pinned_tools` | ゲートが`mise which`で実体を得て、`mise exec`を使わず、`\|\| true`を持たないこと。対象のツールは段階的に足す（commit 1でactionlintとyq、commit 2でgitleaks） |
| `t_gate_checks_jq_first` | ゲートの先頭の確認がjqの実体と版を確かめること（commit 3） |
| `t_gate_checks_bats_first` | ゲートの先頭の確認がbatsの実体と版を確かめること（commit 4） |
| `t_gate_triggers_cover_bats_paths` | M02〜M09の実行条件が、`tests/bats/`と`tests/lib/run-bats.sh`の変更でも対応するテストを走らせること（commit 4） |
| `t_mise_toml_is_restricted` | `mise.toml`が`min_version`と`[tools]`の6つ（shellcheckを含む）だけであること |
| `t_gitleaks_config_has_no_global_allowlist` | `.gitleaks.toml`に`useDefault`、トップレベルの`[allowlist]`、`stopwords`が無いこと |

これらも、batsへ移した後は`@test`として書く。新しい検査はbatsで書く（FR-R0221）が、M09がbatsへ移る前（commit 1〜6）は、
M09の既存の形で書き、commit 7で移す。

### 11.4 テストの本文を読む検査（自己参照の検査）

M09には、`tests/m09-execution-and-ci.sh`自身の行を`grep`で読む検査がある（`smoke_item`と`contract_item`の登録順、`unit`の呼び出し位置など。
`t_smoke_registers_items_1_to_11_in_order`、`t_contract_registers_c1_to_c6_in_order`、`t_smoke_runs_unit_before_docker`）。
M09の中でファイル名を参照する行は20行ある（呼び出しを含む。自身の本文を読む検査の全数は未確認）。
m08には、自分や他のテストの本文を読む検査は無い（T-R0305で確認）。m07は未確認。
薄い入口にして本体を移すと、読む対象が変わるため、そのままでは0件になって落ちる。次の手順で扱う。

| 手順 | 内容 |
| --- | --- |
| 1 | 各段階の開始時（T-R0272、T-R0294、T-R0305、T-R0316）に、`git grep -nE 'tests/(m0[2-9]\|s14)'`で、テストの本文を読む検査を一覧にする。T-R0316の分割表にも含める |
| 2 | 検査ごとに、読む先（`.sh`の入口か`.bats`か）と、契約を保つ式を決める。入口の形を読む検査は薄い入口を読む。登録順を読む検査は、`.bats`の`@test`の並び（`grep -n '^@test'`）を読む式にする |
| 3 | 読む先を変える検査は、現在の入力と壊した入力（順序の入れ替え、項目の欠落）で、旧と新が同じ判定になることを確かめる。判定が弱まる式は採用しない |
| 4 | 書き換えは、その対象を移す段階のタスクに含める。M09の自己参照はT-R0349で、T-R0323（本体の削除）の前に行う |

## 12. 検証境界と手順

| 層 | 内容 | 実行主体 |
| --- | --- | --- |
| 静的 | `git grep`による、`import yaml`、`wf_block`などの不在。`make_fake`などの定義が1か所であること。`mise.toml`と`.gitleaks.toml`の内容 | メインエージェント |
| unit | `sh tests/<ファイル>.sh unit`。Docker、AWS CLIを使わない。batsの`unit`は、CIと端末で実行する | メインエージェント、CI、利用者の端末 |
| smoke | Dockerを使うsmoke（m02〜m05、m09の`smoke`など）。**メインが実行する**。このplanの担当は実行しない | メインエージェント、CI |
| 品質ゲート | `sh scripts/quality-gate.sh`。5つのゲートの未導入と版違いの失敗を含む | メインエージェント |
| CI | 5章のstepの順で通る。job名`e2e`が変わらない | CI |
| ローカルの導入 | macOS（Colima）とLinuxで`mise install --locked`と品質ゲートを実行する | 利用者の端末 |

### 12.1 未導入と版違いの確認

R01の8.1節と同じ手順で、リポジトリの`mise.toml`を書き換えずに確かめる。

| 状態 | 作り方 | 期待 |
| --- | --- | --- |
| mise無し | `command -v mise`が失敗するPATHで実行 | 導入手順つきで失敗 |
| ツール未導入 | `MISE_DATA_DIR`を空の一時ディレクトリへ向けて実行 | 5つのそれぞれが`FAILED:`で失敗。PATH上の別の実行ファイルで通らない |
| 版違い | 実体の`--version`を偽のスクリプトで置き換える | 版の不一致で失敗 |

### 12.2 一時ファイルと後始末

| 対象 | 置き場 | 削除の時期 |
| --- | --- | --- |
| 旧の実行の記録（検査名、判定、件数、実行時間） | `$KIROCREW_SCRATCH`配下 | 対応表を書いた後 |
| 壊した定義、壊した入力 | `$KIROCREW_SCRATCH`配下の一時ファイル。追跡対象に入れる必要があるときだけ`git add -N` | 確認の直後。`git reset -- <パス>`で外し、絶対パスで削除 |
| 導入の確認で作ったmiseの一時ディレクトリ | `$KIROCREW_SCRATCH`配下 | 確認の直後 |
| Dockerの検証資源 | 管理対象は`swsc-`の接頭辞 | 検証の後に`managed_check`で残存を確かめ、リポジトリの後始末（`npm run clean`）で削除 |

各commitの前に`git status --short`を実行し、想定外の生成物（`.local/`、`__pycache__/`、テストの出力）が無いことを確かめる。
削除したものと残したものを、作業の最後の報告に1行で書く。

## 13. リスクと未確認

実測で決める事項は、推測で埋めず、次の表に残す。「確かめる時期」の作業で、結果を書き、状態を「確認済み」に改める。

| # | 項目 | 確かめる内容と方法 | 確かめる時期 | 状態 |
| --- | --- | --- | --- | --- |
| U1 | batsがmise（aqua）で入るか | aquaの定義は`github_archive`（ソースのアーカイブ）。`mise lock`が4環境を記録し、`mise install --locked`が成功し、`mise which bats`の実体で`@test`が動くか。`bin/bats`が同梱の`libexec`を相対で見つけられるか | commit 0 | 確認済み（phase-0-results.md 5章） |
| U2 | yqがmiseで入るか | `github_release`、`checksums-bsd`のSHA512。`mise.lock`のSHA256の出所が`mise-versions`か、公式の資産か。4環境の記録の可否 | commit 0 | 一部確認（SHA256 は一致。checksums-bsd の SHA512 は未照合。phase-0-results.md 3章） |
| U3 | actionlint、gitleaks、jqの4環境 | `mise lock`が4環境を記録できるか。URLが公式のリリースか | commit 0 | 確認済み（4環境の記録、公式の URL。phase-0-results.md 2章） |
| U4 | `--version`の出力の形と`mise current`の値 | 5つの出力から版を取り出す式。jqの`1.8.2`と`jq-1.8.2`の表記。gitleaksは`version`サブコマンドか | commit 0 | 確認済み（出力の形と版の取り出し。phase-0-results.md 4章） |
| U5 | 取得物の完全性 | `mise.lock`のSHA256が、公式の資産の値と一致するか（`gh api`の`digest`、または`checksums`ファイル） | commit 0 | 確認済み（24件一致。phase-0-results.md 3章） |
| U6 | `jdx/mise-action`の`install_args: --locked` | ソースで受理される形か。`--locked`が重複しないか | commit 0（初回のCIの前） | 確認済み（ソースで受理、重複しない。phase-0-results.md 6章） |
| U7 | `gitleaks dir`と`.gitignore` | `.gitignore`の対象（`node_modules/`、`e2e-logs/`）を走査するか。走査するなら8.5節の除外を書く | commit 2 | 確認済み（尊重しない。`.gitignore`の対象の値も検出した。`verification/phase-2-results.md` 1章） |
| U8 | gitleaksの`dir`の走査範囲 | 追跡対象でない一時ファイルを検出するか。壊した入力の置き方（8.3節）に影響する | commit 2 | 確認済み（検出する。`verification/phase-2-results.md` 1章） |
| U9 | gitleaksの規則の機能 | `[[rules.allowlists]]`の`condition = "AND"`と`paths`、`regexes`が、8.30.1で使えるか。`path`のみの規則（正規表現の`path`）の書き方 | commit 2 | 未確認 |
| U10 | 2段の規則の最終形と、除外が要る行 | 実測で検出の一覧を取り、8.2節の表を埋める。0件の可能性もある | commit 2 | 確認済み（既存の範囲の検出は0件。除外は不要。`verification/phase-2-results.md` 3章） |
| U11 | actionlintと`shellcheck` | 既存の`run:`で指摘が出るか。`shellcheck`がPATHに無いときの挙動。`-ignore`が要るか。`run:`の形（引数の渡し方） | commit 1 | 未確認 |
| U12 | `.bats`をshellcheckの対象に含めるか | `shellcheck -s bats`が0.11.0で使えるか。使えなければ`.bash`の補助だけを`-s bash`で検査する | commit 4 | 確認済み: `-s bats`は無い。`-s bash`で`.bats`を検査でき、`.bats`を対象に含める（`phase-4-results.md` 1.1） |
| U13 | `bats --filter-tags`と`test_tags` | 1.14.0で使えるか。`unit`、`smoke`、`contract`の絞り込みで、旧のモードと同じ件数になるか | commit 4 | 確認済み: 絞り込みは使える。件数はタグで数えられる（`phase-4-results.md` 1.2） |
| U14 | `sh`の入口からbatsを呼ぶときのbash | macOSのbash 3.2と、ubuntuのbashで動くか。batsの要求するbashの版 | commit 4（macOSは利用者の端末） | 一部確認: Linux（bash 5.2）で動く。macOS（bash 3.2）は未確認で、T-R0293 で確かめる（`phase-4-results.md` 1.3） |
| U15 | `BATS_TEST_TMPDIR`と`setup_file`の使い方 | 一時ディレクトリの置き方。信号を受けたときの`teardown_file`の挙動 | commit 4 | 確認済み: TERM では`teardown_file`が動かず、子の`sleep`が孤児になる。後始末は入口の trap で行う（`phase-4-results.md` 1.4） |
| U16 | 直列のスクリプト（m02、m04、m05）の`@test`の区切り | 旧の出力の単位で区切る。旧に`check`が無いため、件数の定義を決める | commit 4 | 未確認 |
| U17 | m09の件数のずれ | 静的な行数は227、`clarify.md`は234で、どちらも仮の数字。一方を正とせず、実機の旧の出力で、モード別の実行時の件数を数えて確定する。234の出所（静的な数え方では再現できていない）も記録する | commit 7の開始時 | 未確認 |
| U18 | 実行時間 | actionlint、gitleaks、batsの追加分。段階ごとの旧と新。CIのjob全体が15分に収まるか。stepの合計の上限はjobの15分を超え得る | 各commit、初回のCI | 未確認 |
| U19 | macOSの導入 | `mise install --locked`と品質ゲートの実行（Colima、arm64） | 利用者の端末 | 未確認 |
| U20 | 信号の検査の完全な一覧 | 10.3節の一覧が全件か。`grep`で段階ごとに数え直す | 段階の開始時 | 未確認 |
| U21 | `docs/ローカル実行とCI.md`の記述 | `AGENTS.md`、README、文書が実装と一致するか。入口の変更の有無 | commit 8 | 未確認 |

リスクと対応:

| リスク | 内容 | 対応 |
| --- | --- | --- |
| 設定の自動の信頼 | mise-actionがPRの`mise.toml`を自動で信頼する | R01の5.4節のとおり、`mise.toml`の内容の制限（`t_mise_toml_is_restricted`）、レビュー、CIの権限で守る。ツールを足しても、`[tasks]`などを足さない |
| 取得物の増加 | ツールが5つ増え、導入の時間が増える | 実測して文書に書く。`cache: false`は変えない |
| 判定が弱まる | 構造比較が、旧の行の完全一致より取りこぼす | 11.1節の取りこぼしの確認と、7.4節の壊した定義 |
| コメントの検査 | `# v7.0.1`のコメントは構造として読めない | `grep -Eq`で行う箇所を表に残す（7.3節） |
| batsの移行の量 | `m09`は3950行で、判定の一致の確認が重い | 4段階に分け、各段階の後に件数と判定を確かめる。次の段階へ進まない |
| bashの前提 | 入口は`sh`、中身は`bash`になる | U14で確かめ、文書に前提を書く |
| macOSでの確認の遅れ | U14のmacOS側（T-R0293）が遅れると、commit 5〜7の後で`run-bats.sh`の前提を直すことになる | T-R0293の結果の記録を、T-R0294（commit 5の開始）の前提にする。未実施なら利用者に諮ってから進む |
| gitleaksの誤検知 | 11ファイルの外で、検査の入力の文字列が検出される | 8.2節の手順。一括の除外は書かない |
| 信号の検査 | 書き直すと意味が変わる | 本体を字句のまま移す。差分が呼び出しの形だけであることをレビューで確かめる |
| PR全体の大きさ | 1つのPRに9つのcommitが入る | 利用者の決定（`clarify.md`のQ-R0209）。commitごとに品質ゲートが通る |

## 14. コミットの分け方

`clarify.md`の8章のとおり、1つのPRを9つのcommit（0〜8）に分ける。R05（commit 3）はR04（commit 4〜7）より先に置く。
PR本文は`Closes #34 #35 #36 #37`とする（FR-R0238）。
コミット、push、PR作成は、品質ゲートが通ってからである。このplanでは行わない。

| commit | 内容 | 完了条件 |
| --- | --- | --- |
| 0 | `mise.toml`と`mise.lock`に5つを足す。`install_args`を`--locked`にする。U1〜U6を実測して13章を更新する | `mise install --locked`と、5つの`--version`の記録。`mise.lock`の差分が公式のURLとSHA256だけ。`lint:md`、`git diff --check`。品質ゲートが通る |
| 1（R02） | actionlintのゲートとstep。`t_wf_*`の構造比較への置き換え。`wf_*`とPyYAMLの分岐の削除 | 品質ゲートが通る。M09 unitの`t_wf_*`が通る。7.4節の壊した定義が全て落ちる。式の誤りでactionlintが落ちる。`import yaml`などが無い |
| 2（R03） | `.gitleaks.toml`、gitleaksのゲートとstep。識別情報の検査の置き換え | 品質ゲートが通る。8.3節の壊した入力が落ち、値が出ない。除外の一覧が8.2節に揃い、一括の除外が無い。`swsc_mask`と`swsc_collect_scrub`の差分が無い |
| 3（R05） | JSONの単純な取り出しをjqへ | 品質ゲートが通る。9.3節の4つの入力で、旧と新の判定が一致する。M03〜M09のunit。`e2e-taskdef.py`と`scenario-lib.sh`の差分が無い |
| 4（R04 段階1） | `s14`、`m02`〜`m05`をbatsへ。`helpers`と`run-bats.sh`を作る | 品質ゲートが通る。6.2節の確認（件数、名前、壊した入力、入口）。smokeはメインが実行 |
| 5（R04 段階2） | `m06`、`m07`をbatsへ | 同上。`expect`の3つ（名前、出力、終了コード）が保たれる |
| 6（R04 段階3） | `m08`をbatsへ | 同上 |
| 7（R04 段階4） | `m09`をbatsへ。`unit`、`smoke`、`contract`の件数が一致する | 同上。3つの入口の件数と終了コードが旧と一致 |
| 8 | 文書の最終確認と、実測値の記録 | `npm run -s lint:md`が指摘0。`git diff --check`。品質ゲートが通る。`make_fake`などの定義が1か所。全ACの確認方法を実行して記録 |

各commitの前に、`npm run -s lint:md`（`.md`を変更したとき）、`git diff --check`、`git status --short`、品質ゲートを実行する。
Dockerを使うsmokeは、メインが実行する。実行できなかったものは、「未確認」と書いて完了にしない。

## 15. FR/NFR/ACとの対応

### 15.1 機能要件

| ID | 設計の対応 |
| --- | --- |
| FR-R0201 | 4.3節、5章、7.1節 |
| FR-R0202 | 1章、4.2節、12.1節 |
| FR-R0203 | 7.2節、7.3節（`yq`） |
| FR-R0204 | 7.2節、7.3節、11.1節（PyYAMLの分岐とSKIPの削除） |
| FR-R0205 | 7.3節、11.1節 |
| FR-R0206 | 7.4節、11.1節 |
| FR-R0207 | 5章（追加するstepだけ）、11.2節 |
| FR-R0208 | 4.3節、5章、8.3節 |
| FR-R0209 | 8.1節 |
| FR-R0210 | 8.1節（11ファイル、段2は全体）、8.4節 |
| FR-R0211 | 8.1節、8.2節 |
| FR-R0212 | 8.3節 |
| FR-R0213 | 4.3節、8.1節、8.3節（`--redact`） |
| FR-R0214 | 2章、8.4節 |
| FR-R0215 | 3章、5章、10.1節 |
| FR-R0216 | 6.1節、6.2節、6.3節、11.4節 |
| FR-R0217 | 10.2節（`helpers/fakes.bash`） |
| FR-R0218 | 10.2節（`bats-support`と`bats-assert`は使わない） |
| FR-R0219 | 10.3節、12章（文書に残す） |
| FR-R0220 | 10.1節、2章（文書の更新） |
| FR-R0221 | 11.3節、14章（新しいテストはbats） |
| FR-R0222 | 10.1節 |
| FR-R0223 | 3章、9.2節（前提条件の文書化はcommit 3と8） |
| FR-R0224 | 9.1節、9.2節、9.3節 |
| FR-R0225 | 9.1節、9.2節（置き換えない箇所） |
| FR-R0226 | 2章、9.2節 |
| FR-R0227 | 9.2節、9.3節 |
| FR-R0228 | 3章 |
| FR-R0229 | 1章、4.2節、12.1節 |
| FR-R0230 | 2章、14章（各commitと8） |
| FR-R0231 | 6.1節、6.2節 |
| FR-R0232 | 10.1節 |
| FR-R0233 | 7.2節、4.2節（`mise which yq`、`-e`） |
| FR-R0234 | 10.3節 |
| FR-R0235 | 10.2節、10.3節 |
| FR-R0236 | 8.1節 |
| FR-R0237 | 4.3節、8.5節 |
| FR-R0238 | 14章 |

### 15.2 非機能要件

| ID | 設計の対応 |
| --- | --- |
| NFR-R0201 | 4.2節（共通の関数）、2章（`tests/lib/run-bats.sh`の理由）、7.2節（`wf_*`の削除）、10.2節（重複の削除） |
| NFR-R0202 | 3.2節（SHA256の照合）、U5 |
| NFR-R0203 | 12章（CI、macOS、Linux）、U14、U19 |
| NFR-R0204 | 1章、6.2節、11章 |
| NFR-R0205 | 6.2節、13章のU18、5章（上限） |
| NFR-R0206 | 8.1節、8.3節（実行時に組み立てる） |
| NFR-R0207 | 14章（`lint:md`） |
| NFR-R0208 | 5章（`uses:`を増やさない） |
| NFR-R0209 | 3.1節、11.3節（`t_mise_toml_is_restricted`） |
| NFR-R0210 | 12.2節 |
| NFR-R0211 | 6.1節、14章 |

### 15.3 受け入れ条件

| AC | 設計の対応 | 確認するcommit |
| --- | --- | --- |
| AC-R0201 | 4.3節、12.1節 | 1 |
| AC-R0202 | 7.2節、11.1節 | 1 |
| AC-R0203 | 7.3節、11.1節 | 1 |
| AC-R0204 | 7.4節 | 1 |
| AC-R0205 | 7.1節 | 1 |
| AC-R0206 | 4.3節、8.3節 | 2 |
| AC-R0207 | 8.1節、8.4節 | 2 |
| AC-R0208 | 8.3節 | 2 |
| AC-R0209 | 8.2節（除外の一覧） | 2 |
| AC-R0210 | 8.4節 | 2 |
| AC-R0211 | 3章、10.1節 | 0、4 |
| AC-R0212 | 6.2節、6.3節 | 4〜7 |
| AC-R0213 | 10.2節 | 4〜7 |
| AC-R0214 | 10.3節 | 4〜8 |
| AC-R0215 | 11.3節 | 4〜7 |
| AC-R0216 | 9.2節、9.3節 | 3 |
| AC-R0217 | 3章 | 0、8 |
| AC-R0218 | 2章、9.2節 | 3 |
| AC-R0219 | 6.2節、13章のU18 | 8 |
| AC-R0220 | 14章 | 8 |
| AC-R0221 | 6.1節、6.2節 | 4〜7 |
| AC-R0222 | 10.1節 | 4〜7 |
| AC-R0223 | 7.2節、7.3節 | 1 |
| AC-R0224 | 10.3節 | 4〜7 |
| AC-R0225 | 8.1節、8.2節 | 2 |
| AC-R0226 | 14章 | 8 |

`spec.md`のFR-R0201〜R0230、NFR-R0201〜R0211、AC-R0201〜R0220と、`clarify.md`が追加したFR-R0231〜R0238、AC-R0221〜R0226は、全て上の表に対応している。
抜けは無い。
