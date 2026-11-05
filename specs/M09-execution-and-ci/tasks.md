# M09実装タスク

## 1. 進め方

`plan.md` 8章の14実装単位（U1からU14）を、T901からT926の26タスクに分ける。
U1の前提ゲート（G1からG5）は、T901からT906の6タスクに分ける。
U2からU14は、1単位を1タスクに対応させる（T907からT918、T924）。
残りは、必須レビュー、品質ゲート、コミット、別Issueの起票のタスク（T919からT923）と、
`contract`の実行（T925）、任意レビュー（T926）である。T925とT926は、既存の番号を変えないため、末尾に足した。
各タスクは、対応する検査が通ってから次へ進む。検査は先に失敗するケースを書いてから実装する。
リポジトリのファイルを書き換える検査は書かない（`plan.md` 5.1）。

| タスク | plan.md 8章の単位 | 内容 |
| --- | --- | --- |
| T901 | U1 G4 | 完成版の生成の実装手段（Dockerなし） |
| T902 | U1 G5 | Squidのエントリポイント |
| T903 | U1 G1 | コンテナ名の解決 |
| T904 | U1 G3 | pause方式と送信元ACL（Colima） |
| T905 | U1 G2 | ソケットなしのMiniStack（利用者の端末で実行） |
| T906 | U1 判定 | ゲートの判定、`spec.md`への反映 |
| T907 | U2 | 入口の骨格と前提検査 |
| T908 | U3 | テンプレートと生成 |
| T909 | U4 | 本番向けの検査 |
| T910 | U5 | Squidのイメージ |
| T911 | U6 | MiniStackの契約検証 |
| T912 | U7 | pause方式のランナー |
| T913 | U8 | 入口の完成 |
| T914 | U9 | 実通信の検査（`smoke`と`contract`のモードの実装。`smoke`はエージェントが実行） |
| T915 | U10 | CIワークフロー |
| T916 | U11 | 文書 |
| T917 | U12 | 品質ゲートへの登録（`unit`と`smoke`。`contract`は登録しない） |
| T918 | U13 | 最終確認 |
| T919 | 必須レビュー1 | `evidence-code-review` |
| T920 | 必須レビュー2 | `security-review` |
| T921 | 品質ゲート | `sh scripts/quality-gate.sh`（`unit`と`smoke`を含む。認証情報は不要） |
| T922 | コミット | コミット対象の確認（コミットは利用者の指示後） |
| T923 | 別Issue | 11章の2件の起票（利用者の承認後） |
| T924 | U14 | CI初回の確認（PR作成後。利用者の指示後） |
| T925 | U9 | `contract`の実行と結果の記録（利用者の端末。エージェントは実行しない） |
| T926 | 任意レビュー | `aws-well-architected-review-lite` |

### 1.0 進捗

| タスク | 状態 | 備考 |
| --- | --- | --- |
| T901からT904 | 完了 | G4、G5、G1、G3。G1とG3のCIでの確認（T924）は未了 |
| T905 | 完了 | G2の結果を利用者の貼り付けで受領した（2026-11-04）。観測4の一部は既存証跡による |
| T906 | 完了 | 判定と反映を`gate-results.md`の末尾に記録した。ゲートは通過（観測4と取得時間の再確認はT924） |
| T907以降 | 未着手 | |

### 1.1 検査コマンドの共通事項

検査は3層に分ける（`plan.md` 1章、FR-922）。エージェントのシェルは、AWS認証情報の環境変数を設定できない
（安全ポリシー。回避しない。NFR-902）。このため、エージェントは`unit`と`smoke`だけを実行する。

| 層 | コマンド | Docker | AWS CLIと認証情報 | 実行主体 | 品質ゲート |
| --- | --- | --- | --- | --- | --- |
| unit | `sh tests/m09-execution-and-ci.sh unit` | 使わない。`docker`、`aws`、`docker-compose`は偽物かPATHから外す | 使わない | エージェント、CI | 登録する |
| smoke | `sh tests/m09-execution-and-ci.sh smoke`（引数なしも同じ） | 使う（pause方式の通信検証） | 使わない | エージェント、CI | 登録する |
| contract | `sh tests/m09-execution-and-ci.sh contract` | 使う | 要る（ダミー認証情報） | 利用者の端末、CI。エージェントは実行しない | 登録しない |
| 構文 | `sh -n`（`scripts/e2e*.sh`、`ecs/squid/*.sh`）、`python3 -B -m py_compile scripts/e2e-taskdef.py` | 使わない | 使わない | エージェント、CI | `unit`の中 |
| 文書 | `npm run lint:md`、`git diff --check` | 使わない | 使わない | エージェント | 既存のゲート |

エージェントは`contract`を実行せず、「未検証」と報告する。利用者の端末での実行結果は、T925で受け取り、
`specs/M09-execution-and-ci/contract-results.md`に記録する。

Dockerを使うタスクの前に、ColimaをAGENTS.mdの条件付き設定で有効にする。

```sh
if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
  export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock
fi
```

Colimaを使っていない環境では、Docker runtimeとDocker contextを変更しない。
Dockerの設定ファイル、AWSの認証情報、Dockerレジストリの認証情報は、読まず、出力しない。
`~/.docker/config.json`の読み取りが`Operation not permitted`になる場合は、
`$KIROCREW_SCRATCH/docker-config`に空の`config.json`（内容は`{}`）を作り、`DOCKER_CONFIG`で指す。
Composeは新基盤では使わない。旧基盤の存在確認が要るときだけ`docker-compose`（`docker compose`ではない）を読み取りで使う。

AWS CLIの呼び出しが要る検査（`contract`、G2）は、利用者が自分のターミナルでダミー認証情報（`test`）を設定した状態で実行する。
エージェントのシェルでは環境変数を設定しない（NFR-902）。エージェントは、`start`、`test`、`test:ci`、`smoke`、
品質ゲートのいずれでも、AWS CLIとダミー認証情報を使わない。設定が無い場合は、その検査を未検証として報告し、成功と断定しない。

### 1.2 全タスク共通の受け入れ条件

次の条件は、各タスクの受け入れ条件に加えて、Dockerを使う全タスクに適用する。

後始末

- 終了時に、`docker ps -aq --filter label=swsc.managed=true`が空である
- 終了時に、`docker ps -a --format '{{.Names}}'`の出力に、`swsc-`で始まる名前が無い
- 終了時に、`docker network ls --format '{{.Name}}'`の出力に、`^swsc-`に一致する名前が無い（ネットワーク`swsc-net`の回収。
  `--filter name=swsc-`は部分一致のため使わない）
- 回収は、`swsc-`の接頭辞とラベル`swsc.managed=true`の両方が一致するものだけに行う。
  他のプロジェクト（`m05`、`pr99-review`、Composeのプロジェクト）のコンテナとネットワークは、止めず、消さない。
  例外は、`smoke`の項目7が、名前を指定して作る使い捨てのコンテナ（`swsc-`の接頭辞を付けない。例 `m09-smoke-port-holder`）で、
  検査の`trap`が名前を指定して回収する
- リポジトリ直下に、作業で作った一時物（`.e2e/`、`e2e-logs/`、S14の`.s14-deny.*`、`.e2e/gate/`）が残っていない。
  ただし、実装途中のタスクが次のタスクへ引き継ぐ`.e2e/`は、T907以降のタスクに限り、`.gitignore`に入っていることを確かめる
  （`.gitignore`への追加はT907の作業のため、T901からT906のゲートの間は、`.e2e/gate/`を作業後に`.e2e/`ごと削除する）
- 一時物を消すときは、自分が作った名前を指定し、変数が空でないことを確かめてから消す。`rm -r <名前>`を使い、広いパターンは使わない
- 検査が作る一時ディレクトリ（`mktemp -d`）は`trap`で消え、終了後に残らない
- `$KIROCREW_SCRATCH`配下の写しとログは、タスクの終了までに削除する。`/tmp`は使わない
- 失敗経路でも、終了コードが元の値を保つ

コミット対象の確認

- `git add`はファイルを名指しで行い、`git add .`、`git add -A`、`git add -u`は使わない
- `.kiro/settings/cli.json`は、変更があってもコミットしない。`git diff --cached --name-only`に現れないことを確かめる
- `.e2e/`、`e2e-logs/`、`$KIROCREW_SCRATCH`の写し、実験の生ログをリポジトリへ持ち込まない
- コミット対象は、`plan.md` 2.1と2.2の一覧に収まる。`git status --short`で想定外の変更が無いことを確かめる
- このspecのタスクでは、`git commit`、`git push`、PR作成、Issueの編集と起票を行わない
  （T922、T923、T924は利用者の指示を待つ）
- 公開物（文書、workflow、ログ、`gate-results.md`）に、AWSアカウントID、認証情報、実ARN、12桁の数字を書かない。
  必要な場合は`<ACCOUNT_ID>`などの記号に置き換える

### 1.3 前提ゲート（T901からT906）

T901からT906は、実装を止めるゲートである。
生成の実装手段、WireMockの宛先、MiniStackの比較の規則、Squidの引き渡しは、ゲートの結果で決まる。
T906が「ゲートを通過した」と明記できるまで、T907以降に着手しない。
T907のうち、ゲートに依存しない部分（`package.json`のscriptsや`.gitignore`）の下書きも先行しない。

実行の区切り: G2（T905）は`aws`を呼ぶため、利用者の端末で実行し、貼り付けを待つ必要がある。
サブエージェントは貼り付けを待てない。このため、実行を2つに分ける。

| 実行 | 範囲 |
| --- | --- |
| 実行1 | T901からT904と、T905の準備（候補タグの選定、`taskdef.json`の作成、手順の提示）。手順を提示して終了する |
| 実行2 | 利用者の貼り付けを受けた後のT905の判定とT906以降。T905の完了は、メインエージェントが貼り付けを受け取った時点とする |

結果の記録先は、全ゲートで`specs/M09-execution-and-ci/gate-results.md`の1か所とする。
ゲートごとに、次の5つの節を持つ（`plan.md` 4.2）。

| 節 | 内容 |
| --- | --- |
| 環境 | 日時、Docker runtime（Colimaの有無）、イメージのタグとダイジェスト、`python3`の版 |
| 手順 | 実行したコマンド（秘密情報を含まない形）。マウントはリポジトリ直下の`.e2e/gate/`で行った旨 |
| 観測 | `plan.md` 4.3の観測項目ごとの結果。数値は実測値 |
| 分岐の決定 | 4.3の結果表のどの行に当たるか。一つに決める |
| 後続への影響 | 変更するタスクと、`spec.md`の直す箇所 |

| 区分 | 通過の条件 |
| --- | --- |
| 通過の条件1 | G1からG5の全節が揃い、観測項目に欠けが無い |
| 通過の条件2 | ゲートごとの分岐が一つに決まっている |
| 通過の条件3 | G2の結果が「ここで止めて利用者に判断を求める」の行に当たっていない（当たる場合は利用者の決定を記録する） |
| 通過の条件4 | ゲート用のコンテナとネットワークが回収され、作業開始前の`git status --short`との差が、`specs/M09-execution-and-ci/`の文書だけである。`.e2e/`は、`.e2e/gate/`ごと削除されている（`.gitignore`への追加はT907の作業のため、ゲートの間は無視対象を前提にしない） |
| 通過しない | 観測が欠ける、分岐が決まらない、ポート8080か4566が空いていない、G2の貼り付けが無い |

ゲートの実験の順序は、G4、G5、G1、G3、G2とする。G1とG3はG5で調べたSquidの内容を使う。G2は独立である。

### 1.4 並列実行の可否

共有するファイルは次のとおり。

| ファイル | 編集するタスク |
| --- | --- |
| `specs/M09-execution-and-ci/gate-results.md` | T901、T902、T903、T904、T905、T906 |
| `specs/M09-execution-and-ci/spec.md`、`plan.md` | T906のみ（分岐に該当する場合。G5の決定をplan 3.4へ書くのもT906） |
| `tests/m09-execution-and-ci.sh` | T907からT916（`unit`、`smoke`、`contract`のケース追加。T914、T915の順に直列） |
| `scripts/e2e-lib.sh`、`scripts/e2e.sh` | T907、T909、T911、T912、T913 |
| `scripts/e2e-taskdef.py` | T908、T909、T911、T912 |
| `ecs/squid/` | T910のみ（G5の結果はT910の内容に反映する） |
| `specs/M09-execution-and-ci/contract-results.md` | T925のみ |
| `.github/workflows/e2e-test.yml` | T915のみ |
| `docs/ローカル実行とCI.md` | T916のみ（T924で所要時間を反映） |
| `README.md`、`AGENTS.md` | T916のみ |
| `scripts/quality-gate.sh` | T917のみ（登録する場合） |
| `package.json`、`.gitignore` | T907のみ |

並列にできる組は次の一組だけである。

| 並列にできる組 | 理由と条件 |
| --- | --- |
| T916の文書本体（`docs/ローカル実行とCI.md`、`README.md`、`AGENTS.md`）と、T914またはT915 | 編集するファイルが重ならず、文書の作成はポートを使わない。T916の`unit`の文書検査（`tests/m09`の編集）は、T914とT915の後に行う。「所要時間の目安」の節は、T924まで空けておく |

並列にできない組と理由は次のとおり。

| 並列にできない組 | 理由 |
| --- | --- |
| T901からT906のどれか同士 | `gate-results.md`を共有し、T902からT905はポートとコンテナ名を使う。T901もT902の前提を与える |
| T907からT915のどれか同士 | `tests/m09-execution-and-ci.sh`を共有する。依存順に1つずつ進める |
| T908とT910 | 論理的には独立だが、同じ検査ファイルを編集するため直列にする |
| T914、T917、T918、T921、T925の相互 | ポート8080と4566、`swsc-`の名前を共有するため（T925は利用者の端末だが、同じホストなら直列にする） |
| T914とT915 | どちらも`tests/m09`を編集するため、T914、T915の順に直列にする |
| T919とT920 | 必須レビューは、コンテキストとモデルを分けるため、1スキル1サブエージェントで直列に実行する |

## 2. タスク

### T901: G4 完成版の生成の実装手段（前提ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-911（生成と比較の実装手段） |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（新規。G4の節）、`.e2e/gate/`（一時） |
| 依存 | なし |
| 並列 | 不可（以降のゲートの前提。`gate-results.md`を新規作成する） |
| 受け入れ条件 | `plan.md` 4.3のG4の観測1から5が実測値で揃い、分岐が一つに決まっている |
| 検査コマンド | `python3 --version`、`command -v jq curl`、下記の手元実験、`git status --short` |

- Dockerを使わない。ポートの確認は不要である
- `gate-results.md`を作り、冒頭に全ゲートの判定表（G1からG5、結果の分岐、日時）の枠を置く
- 観測1: 値に`/`、`:`、`@`、`\`、`"`、改行を含めてプレースホルダーを置換し、JSONが壊れないかを確かめる
- 観測2: 未置換のプレースホルダーの検出と、許可リスト外のキーの名指しが書けるかを確かめる
- 観測3: キーの順序を固定し、同じ入力で同じバイト列になるかを確かめる
- 観測4: 環境変数の順序差と既定値の無視を含む比較が、標準ライブラリだけで書けるかを確かめる
- 観測5: このMacの`python3`の版と、`jq`の有無を記録する。ランナーの版はT924で確認する
- 実験のスクリプトは`.e2e/gate/`に置く（リポジトリには持ち込まない）。実験後に`.e2e/gate/`を削除する

結果の分岐（`plan.md` 4.3のG4）は次のとおり。

| 結果 | 決定と記録 |
| --- | --- |
| `python3`の標準ライブラリで全項目が書ける | 採用する。`jq`は使わない。前提検査は`python3`と`curl`を見る。`spec.md`の追加修正は無い |
| `python3`が古く、構文が動かない | 構文を古い版に合わせる。標準ライブラリ以外には依存しない |
| 利用者の環境に`python3`が無い | 前提検査で止める（FR-912）。`jq`への切り替えは、両方の環境に`jq`があるときだけ検討し、`spec.md`のFR-912とNFR-911を直す |
| `jq`だけで書ける | 比較と変換の保守性を見て決める。両方の実装は持たない。決定を`spec.md`に反映する |

### T902: G5 Squidのエントリポイント（前提ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-909（`ubuntu/squid:latest`の据え置きとダイジェスト記録）、FR-908の前提 |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（G5の節）、`.e2e/gate/`（一時） |
| 依存 | T901 |
| 並列 | 不可（`gate-results.md`を共有。Dockerを使う） |
| 受け入れ条件 | `plan.md` 4.3のG5の観測1から5が揃い、分岐が一つに決まっている |
| 検査コマンド | 下記。終了時に1.2の後始末の確認 |

- 先に1.1のColima設定を行う。`docker pull ubuntu/squid:latest`でイメージを取得し、ダイジェストを記録する
- 観測1: `docker image inspect ubuntu/squid:latest --format`で`Config.Entrypoint`、`Config.Cmd`、`Config.User`を読む
- 観測2: 元のエントリポイントのスクリプトを`docker run --rm --entrypoint cat`で読み、
  ディレクトリ作成、権限、`squid`の起動引数を記録する
- 観測3: tmpfsなしで、`/var/log/squid`と`/var/spool/squid`が書き込み可能かを、使い捨てのコンテナで確かめる
- 観測4: `.e2e/gate/`に`squid-config/squid.conf`の写しを置き、`cache_peer wiremock parent 8080 0 no-query`を
  `cache_peer <名前> parent 8080 0 no-query name=wiremock`へ置換したものに対して、`squid -k parse -f`が通るかを確かめる
- 観測5: `cache_peer`の3行と`never_direct`を除き`always_direct allow api_domains`を足した`direct`の設定が、
  `squid -k parse`を通るかを確かめる
- 使い捨てのコンテナには`--rm`、名前`swsc-gate-*`、ラベル`swsc.managed=true`を付ける。マウントは`.e2e/gate/`だけ
- 実験後に、ゲート用のコンテナを回収し、`.e2e/gate/`を削除する

結果の分岐（`plan.md` 4.3のG5）は次のとおり。

| 結果 | 決定と記録 |
| --- | --- |
| 元のエントリポイントに`exec`で引き渡せる | `plan.md` 3.4の手順4に、そのパスと引数を書く |
| 元のエントリポイントが設定を上書きする、または環境に依存する | 引き渡さず、イメージの`Cmd`と同じ引数で`squid`を直接`exec`する |
| tmpfsなしでは書き込めない | `entrypoint.sh`に、ディレクトリの作成と所有者の設定を足す（T910の内容に反映） |
| `parse`が起動前に使えない | 検査を起動後の`cache.log`の確認に変える。`smoke`の「directの構文」は使い捨てのコンテナで行う |
| `name=wiremock`を受け付けない | `cache_peer_access`の2行も置換する。派生元の行の存在検査に2行を足す（T910の内容に反映） |

### T903: G1 コンテナ名の解決（前提ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-910、Q-915 |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（G1の節）、`.e2e/gate/`（一時） |
| 依存 | T902 |
| 並列 | 不可（ポート8080を使う。`gate-results.md`を共有） |
| 受け入れ条件 | `plan.md` 4.3のG1の観測1から4が揃い、分岐が一つに決まっている |
| 検査コマンド | 下記。事前に`lsof -nP -iTCP:8080 -sTCP:LISTEN`。終了時に1.2の後始末の確認 |

- 事前に、ポート8080が空いていることを確かめる。使用中なら、止めて利用者に報告する。他のプロジェクトのコンテナは止めない
- 先に1.1のColima設定を行う
- ネットワーク`swsc-net`（ラベル付き）を作り、`swsc-gate-wiremock`（`wiremock/wiremock:3.13.1`、
  `docker-compose.yml`の定義と同じマウント）、`swsc-gate-pause`（`alpine:3.20`、`sleep infinity`）を置く
- Squidは`swsc-gate-pause`の名前空間に参加させ、`cache_peer`の宛先にWireMockの名前を渡す（T902の置換を使う）
- 観測1: Squidの`cache.log`に、ピアの解決の失敗が出ないこと
- 観測2: Clientイメージ（`Dockerfile.test-client`から`swsc-gate-client`として作る）から、Squid経由で
  `http://api.example.com`を要求し、WireMockの応答が返ること
- 観測3: WireMockをSquidより後に起動した場合に、ピアが復帰するか
- 観測4: ColimaとLinux（CI）の結果の差。Linux側はT924で確認し、ここでは「未確認」と明記する
- 実験後に、ゲート用のコンテナとネットワークを回収し、`.e2e/gate/`を削除する

結果の分岐（`plan.md` 4.3のG1）は次のとおり。

| 結果 | 決定と記録 |
| --- | --- |
| 解決できる | コンテナ名を`SQUID_MOCK_HOST`に渡す（FR-910どおり）。起動順は、WireMockの待機の後にSquidとする |
| 解決できない | `docker inspect`で`swsc-net`上のWireMockのIPアドレスを読み、`SQUID_MOCK_HOST`に渡す。T906で`spec.md`のFR-910とQ-915を「名前またはIPアドレス」に直す |
| 解決できるが、起動順が逆だと復帰しない | 起動順（WireMock、pause、Squid）を固定し、文書に残す。`start`の待機でこの順序を保証する |
| ColimaとLinuxで結果が異なる | 両方で通る方式（IPアドレス）に統一する。差の原因を記録する |

### T904: G3 pause方式と送信元ACLのColimaでの先行確認（前提ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-906、FR-907 |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（G3の節）、`.e2e/gate/`（一時） |
| 依存 | T903 |
| 並列 | 不可（ポート8080を使う。`gate-results.md`を共有） |
| 受け入れ条件 | `plan.md` 4.3のG3の観測1から5がColimaで揃い、分岐が一つに決まっている。CIでの再確認はT924と明記する |
| 検査コマンド | 下記。事前に`lsof -nP -iTCP:8080 -sTCP:LISTEN`。終了時に1.2の後始末の確認 |

- T903の構成（WireMock、pause、Squid）をそのまま使う。ポートの確認とColima設定も同じ
- 観測1: ClientからSquid経由で許可ドメインを要求し、200が返る
- 観測2: Squidの`access.log`で、Clientの送信元が`127.0.0.1`であり、`local_src`で許可される
- 観測3: 許可外ドメインが403（`TCP_DENIED`）になり、WireMockの受信総数が0のまま
- 観測4: `docker restart`でSquidだけを再起動した後も、観測1が成功する
- 観測5: `sleep infinity`がalpine:3.20のbusyboxで動く。動かなければ`tail -f /dev/null`を試す
- 実験後に、ゲート用のコンテナとネットワークを回収し、`.e2e/gate/`を削除する
- CIでの確認（GitHub Actionsのランナー）は、この時点では行わない。T924で、本番のworkflowの初回実行で確かめる

結果の分岐（`plan.md` 4.3のG3）は次のとおり。

| 結果 | 決定と記録 |
| --- | --- |
| すべて期待どおり | 採用する |
| 許可ドメインが403になる（`local_src`に一致しない） | `squid.conf`は変更しない（S14の検査が固定している）。送信元アドレスを調べ、`derive-config.sh`で`local_src`の範囲に足す案を`spec.md`の変更として利用者に確認する |
| `sleep infinity`が動かない | `tail -f /dev/null`にする |
| Colimaでは通り、CIでは失敗する | T924で失敗時のアーティファクトから原因を特定する。ゲート用の一時ブランチやworkflowは作らない |

### T905: G2 ソケットなしのMiniStack（前提ゲート。利用者の端末で実行）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-902、FR-904、FR-905、NFR-906、NFR-909 |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（G2の節）、`.e2e/gate/taskdef.json`（一時） |
| 依存 | T901（`python3`の確認）。G1、G3とポートを分けるため順序はT904の後にする |
| 並列 | 不可（ポート4566を使う。`gate-results.md`を共有） |
| 受け入れ条件 | 利用者の貼り付けで、`plan.md` 4.3のG2の観測1から6が揃い、分岐が一つに決まっている |
| 検査コマンド | 下記の手順を利用者が実行する。判定側は`gate-results.md`の記録と、貼り付けに12桁の数字が無いことの確認 |

`aws` CLIにダミー認証情報の環境変数が要る。エージェントのシェルでは環境変数を設定できないため、
このタスクは、手順を書いて利用者の端末で実行してもらい、貼り付けを受けて判定する。

エージェントが行うこと

- ポート4566が空いていることを`lsof -nP -iTCP:4566 -sTCP:LISTEN`で確かめる。使用中なら、止めて報告する
- 候補のタグを選ぶ。MiniStackの公式のリリースの一覧で最新の安定版を確認し、そのタグがイメージレジストリに存在することを
  `docker manifest inspect`などの読み取りで確かめる。`latest`と日付だけのタグは候補にしない。
  選んだタグと確認の根拠（リリースの日付、確認したコマンド）を`gate-results.md`のG2の節に書く
- `.e2e/gate/taskdef.json`を作る。内容は`plan.md` 3.1のテンプレートの`{{...}}`を、
  `swsc-client:gate`、`swsc-squid:gate`、`mock`に置換したものである（イメージは取得されないので存在しなくてよい）
- 下記の手順と、貼り付けてほしい項目を利用者に提示し、ここで一度止まる（実行1の終了。1.3）
- 貼り付けを受けたら（実行2）、`gate-results.md`のG2の節に記録し、分岐を決める

利用者の端末で実行する手順（リポジトリルートで実行）

```sh
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-northeast-1
EP=http://127.0.0.1:4566
# Colimaを使う場合のみ（DOCKER_HOSTを設定）
export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock

# 1. ソケットを渡さずに起動する。<候補のタグ>は、エージェントが選んだタグ。先にpullして取得時間を測る
time docker pull ministackorg/ministack:<候補のタグ>
docker run -d --name swsc-gate-ministack --label swsc.managed=true \
  -p 127.0.0.1:4566:4566 ministackorg/ministack:<候補のタグ>
docker image ls ministackorg/ministack --format '{{.Tag}} {{.Size}}'

# 2. 応答を待つ（応答しない場合は、その旨を貼り付ける）
aws --endpoint-url "$EP" ecs list-task-definitions

# 3. 登録する
aws --endpoint-url "$EP" ecs register-task-definition \
  --cli-input-json file://.e2e/gate/taskdef.json --query 'taskDefinition.revision'

# 4. 項目ごとに取り出す
aws --endpoint-url "$EP" ecs describe-task-definition --task-definition swsc-e2e \
  --query 'taskDefinition.{nm:networkMode,cpu:cpu,mem:memory,req:requiresCompatibilities,c:containerDefinitions[].{n:name,i:image,e:essential,env:environment,p:portMappings,d:dependsOn,h:healthCheck}}'

# 5. 出力とログに、12桁の数字とARNが出るか
aws --endpoint-url "$EP" ecs describe-task-definition --task-definition swsc-e2e \
  | grep -Eo 'arn:aws[^"]*|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)' | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'
docker logs swsc-gate-ministack 2>&1 \
  | grep -Eo 'arn:aws[^"]*|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)' | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'

# 6. 回収する
docker rm -f swsc-gate-ministack
docker ps -aq --filter label=swsc.managed=true
```

貼り付けてほしい内容は、手順1から5の出力である。手順5は、数字を`<ACCOUNT_ID>`に置換した出力にする。
アカウントIDとARNの実値、認証情報、`~/.aws`の内容は貼らない。実AWSの認証情報が環境変数に入っていないことを、
手順の前に`env | grep -c '^AWS_'`などで確かめる。

判定は、貼り付けの観測を`gate-results.md`に転記して行う。分岐（`plan.md` 4.3のG2）は次のとおり。

| 結果 | 決定と記録 |
| --- | --- |
| 登録とdescribeが応答し、全項目が一致して返る | 採用する。タグを固定する（NFR-909）。固定したタグを`gate-results.md`に書く |
| 応答するが、一部の項目が欠落または変形して返る | T911の比較に正規化の規則を足す。返らない項目は、describeとの比較をやめ、完成版を直接検査する対象として文書に列挙する。`networkMode`、`name`、`image`、`environment`のいずれかが返らない場合は、次の行へ進む |
| ソケットなしでは起動しない、またはECS APIが応答しない | MiniStackの公式の設定で回避できるかを調べる。回避できなければ、ここで止めて利用者に判断を求める。選択肢は(A)AWS CLIのクライアント側検証だけにしてFR-904を緩める、(B)読み取り専用でもソケットを渡す（NFR-906を緩める。推奨しない）、(C)別のエミュレータ。エージェントは自動で選ばない |
| `cpu`、`memory`、`requiresCompatibilities`を拒否する | Fargateの有効な組み合わせに直す。それでも拒否するなら、テンプレートから外し、`spec.md`のFR-902を直す |
| 出力またはログにダミーのアカウントIDとARNが出る | 出力は`--query`で除外する。ログはT913の収集でマスクしてから再検査する |

貼り付けが届くまで、T906以降に進まない。貼り付けが得られない場合は、G2を未検証として報告し、利用者の判断を待つ。
完了の記録: 2026-11-04に貼り付けを受領し、`gate-results.md`のG2の節に記録した（タグ`1.5.37`で通過）。

### T906: ゲートの判定と`spec.md`への反映

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-902、FR-904、FR-910（`spec.md`の直し）、1.3のゲート条件 |
| 触るファイル | `specs/M09-execution-and-ci/gate-results.md`（判定表と全体の節）。分岐に該当する場合だけ`specs/M09-execution-and-ci/spec.md`と`plan.md` |
| 依存 | T901からT905 |
| 並列 | 不可 |
| 受け入れ条件 | 1.3の通過の条件1から4をすべて満たす。`plan.md` 12章の番号1と2の扱いが決まっている |
| 検査コマンド | `npm run lint:md`、`git status --short`（作業開始前との差の比較）、1.2の後始末の確認、`grep -E '[0-9]{12}' specs/M09-execution-and-ci/*.md`が0件 |

- `gate-results.md`の冒頭の判定表に、G1からG5の分岐、確定した値（MiniStackのタグ、`python3`の版、
  `SQUID_MOCK_HOST`の方式、Squidの引き渡し）を埋める
- 後続への影響を一覧にする。`plan.md` 4.3の各表の「決定」を、T907以降のどのタスクで反映するかを書く
- `plan.md` 12章の番号1（G1）と番号2（G2）に該当する場合だけ、`spec.md`を直し、`plan.md` 12章の状態を「反映済み」に変える。
  該当しない場合は、「ゲートの結果、変更なし」と記録する
- `spec.md`を直すときは、FR/NFRの番号と数値が`plan.md`と食い違わないことを`grep`で確かめる
- `spec.md`を直した場合は、直した箇所の範囲で、analyzeの確認（FR/NFR/タスクの番号、値、モード名の突き合わせ）をやり直し、
  `gate-results.md`に記録する（`plan.md` 12章）。NFR-906の緩和など、安全側の要件を緩める分岐に当たる場合は、
  実装に進む前に利用者の明示的な承認を`gate-results.md`に記録する。承認が無い緩和を基準に、T919とT920のレビューを行わない
- G5の決定（`plan.md` 3.4の手順4の引き渡し先）を`plan.md`に書くのも、このタスクで行う
- ゲート用のコンテナ、ネットワーク、`.e2e/gate/`が回収されていることを確かめる。`.e2e/`は、この時点では`.gitignore`にまだ無いため、
  ごと削除されていることを確かめる
- 完了報告に、ゲートを通過したと明記する。通過の条件を満たさない場合は、T907に進まず、利用者に判断を求める
- 完了の記録: 2026-11-04に完了した。ゲートは通過（G2の観測4の一部は既存証跡による。CIの初回で再確認）。
  G1とG3のCIでの確認はT924で行う（未了）。判定の結果は`gate-results.md`の末尾の表に記録した

### T907: 入口の骨格と前提検査（U2）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-901、FR-905、FR-912、FR-920、NFR-902、NFR-909 |
| 触るファイル | `package.json`、`.gitignore`、`scripts/e2e.sh`、`scripts/e2e-lib.sh`、`tests/m09-execution-and-ci.sh`（いずれも新規か最小の変更） |
| 依存 | T906 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の引数、前提検査（操作ごとに必要なものだけ）、FR-920の検査が通る。`package.json`の`lint:md`は変わらない |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh -n scripts/e2e.sh scripts/e2e-lib.sh`、`npm run lint:md` |

- 先に、`unit`の枠と失敗するケースを書く。不正なモード、`unit`に余計な引数、未知の操作が終了コード2になること
- `package.json`のscriptsに`start`、`test`、`logs`、`stop`、`clean`、`test:ci`の6つを足し、
  `sh scripts/e2e.sh <操作>`へ委譲する。`logs`は追加の引数を受ける
- `.gitignore`に`.e2e/`と`e2e-logs/`を足す
- `e2e-lib.sh`に、名前と版の定数（MiniStackは`ministackorg/ministack:1.5.37`、その他は`alpine:3.20`、`wiremock/wiremock:3.13.1`）、
  操作ごとの前提検査、`swsc_aws`を置く
- 前提検査は、操作が必要とするものだけを検査する（FR-912、`plan.md` 3.8）。`start`、`test`、`test:ci`（smoke層）は、
  `docker`、`python3`、`curl`の欠落を検出し、`aws`の欠落と認証情報の有無を問わない。`contract`（contract層）は、
  `docker`、`aws`、`python3`の欠落と、ダミー認証情報の未設定と`test`以外の値を検出する。いずれも原因を示して非ゼロで終了する
- ポートの空き確認は、前提検査に含めない。`start_main`と`contract`が、自分の`swsc-`を停止した後に行う（T913、T911）。
  ここでは、前提検査にポートの確認が含まれないことを`unit`で固定する
- `docker-compose`がPATHにあっても呼ばれないことを、呼ばれたら失敗する偽で確かめる
- `swsc_aws`以外で`aws`コマンドを直接呼ばないことを`grep`で確かめる。`start`、`test`、`test:ci`が偽の`aws`を呼ばず、
  認証情報が無くても前提検査を通ることを確かめる

### T908: テンプレートと生成（U3）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-902、FR-903、NFR-905、NFR-909、NFR-911 |
| 触るファイル | `ecs/task-definition.template.json`、`scripts/e2e-taskdef.py`（`render`）、`scripts/e2e-lib.sh`（`swsc_render`）、`tests/m09-execution-and-ci.sh` |
| 依存 | T907 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「完成版の生成」の全ケースが通る。同じ入力で同じバイト列になる。生成の呼び出しが`swsc_render`の1か所に集まっている |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`python3 -B -m py_compile scripts/e2e-taskdef.py` |

- `swsc_render`は、`start`（T913）と`contract`（T911）が同じ入力で呼ぶ、完成版の唯一の生成経路である。`unit`で別の経路が無いことを`grep`で確かめる
- `--upstream`の値は、英数字と`-`と`_`だけ（長さ1〜32）を許し、`mock`と`direct`の判定は`local`プロファイルではSquid側が行う

- 実装手段はT901の決定に従う
- テンプレートは`plan.md` 3.1の内容にする。`mock`の既定値とWireMockの宛先を書かない。ロールのARNを書かない
- `render`は、`plan.md` 3.2の表の検査を行う。値の文字種、未置換、未知のプレースホルダー、
  許可リスト外のキーの名指し、`dependsOn`と`healthCheck`の形式
- `unit`のケース: 正常、未置換、未知のプレースホルダー、値の文字種違反、`volumes`などの名指し、固定値の項目、
  Clientの`HTTP_PROXY`と`NO_PROXY`、Clientに`healthCheck`が無いこと、同じ入力で同じバイト列
- 完成版は`.e2e/taskdef.json`に出す。コミットしない。`unit`は`.e2e/`に書かない（一時ディレクトリを使う）

### T909: 本番向けの検査（U4）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-909 |
| 触るファイル | `scripts/e2e-taskdef.py`（`--profile production`、`check-production`）、`scripts/e2e.sh`、`tests/m09-execution-and-ci.sh` |
| 依存 | T908 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「本番向け」の全ケースが通る。層1から3が`unit`で固定される |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`python3 -B -m py_compile scripts/e2e-taskdef.py` |

- 先に失敗するケースを書く: `mock`、`Mock`、`MOCK`、前後に空白のある`direct`、空、欠落、`SQUID_MOCK_*`の残存、合格
- `--profile production`で`--upstream`が`direct`以外、または`--mock-host`、`--mock-port`が指定されたら拒否する
- `check-production`は、任意のJSONに対して`plan.md` 3.6の条件を検査する。不合格の出力には名前だけを書き、値を書かない
- JSONとして読めない、またはファイルが無い場合は終了コード2にする
- 層1は、`unit`がテンプレートを読み、`mock`の文字列と`SQUID_MOCK_`の文字列が無いことで固定する

### T910: Squidのイメージ（U5）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-908、FR-909（層4の出力） |
| 触るファイル | `ecs/squid/Dockerfile`、`ecs/squid/derive-config.sh`、`ecs/squid/entrypoint.sh`、`tests/m09-execution-and-ci.sh` |
| 依存 | T909、T902の分岐 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「Squidの派生」の全ケースが通る。`squid-config/squid.conf`は変更されていない |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh -n ecs/squid/derive-config.sh ecs/squid/entrypoint.sh`、`git diff --stat -- squid-config` |

- `derive-config.sh`は`plan.md` 3.4の規則に従う。行の比較は`awk`の`$0 == 文字列`で行う
- 先に失敗するケースを書く: 未設定、`mock`と`direct`以外（大文字、前後の空白）、`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`の文字種違反、
  注入になる値（空白、`;`、改行、`$(`）、派生元の行が欠けた場合
- `mock`と`direct`の出力と、派生元の行が1行ずつ存在することを固定する
- `entrypoint.sh`は、派生、`squid -k parse`、`upstream=<mock|direct>`の出力、元のエントリポイントへの引き渡しの順にする。
  引き渡しは`exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC`とする（G5）。tmpfsは要らない。
  派生元の行の存在検査は、`cache_peer`、`cache_peer_access`の2行、`never_direct`の4行を対象にし、`name=wiremock`は受理される（G5）
- ビルド文脈（`.e2e/context/squid/`）のコピーが`squid.conf`と`cmp`で同一であることを`unit`で確かめる
- `smoke`の3と4（不正な値、`direct`の構文）はT914で行う

### T911: MiniStackの契約検証（U6）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-904、FR-905、FR-918、NFR-901、NFR-902、NFR-906 |
| 触るファイル | `scripts/e2e-contract.sh`、`scripts/e2e-taskdef.py`（`compare`）、`scripts/e2e-lib.sh`（`swsc_aws`）、`scripts/e2e.sh`（`contract`操作の振り分け）、`tests/m09-execution-and-ci.sh` |
| 依存 | T910、T905の分岐 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「契約の比較」と、偽の`aws`の呼び出し、`contract`操作の順序（認証情報の検査がMiniStackの起動と`aws`の前）の全ケースが通る |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh -n scripts/e2e-contract.sh`、`python3 -B -m py_compile scripts/e2e-taskdef.py` |

- `swsc_aws`は、`--endpoint-url`と`--region`を毎回明示し、認証情報が未設定か`test`以外なら`aws`を呼ばずに終了コード1にする。
  既定の認証情報にはフォールバックしない。`swsc_aws`の呼び出し元は`e2e-contract.sh`だけにする
- 1回の呼び出しに限り、`AWS_CONFIG_FILE=/dev/null`、`AWS_SHARED_CREDENTIALS_FILE=/dev/null`、
  `AWS_EC2_METADATA_DISABLED=true`を与え、`AWS_PROFILE`を外す。偽の`aws`で環境を記録して検査する
- `contract`操作は、`plan.md` 3.5の表（8手順）に従う。MiniStackの起動と削除を担当するのはこの操作だけである。
  contract層の前提検査（認証情報を含む）を、コンテナの作成と`aws`の呼び出しより前に行い、
  既存の`swsc-ministack`の削除の後に、ポート4566を確認する（`swsc-`以外が使用中なら止まる）
- 完成版は、`start`と同じ`swsc_render`（T908）を同じ入力で呼んで作る。別の生成経路を持たない
- 出力は`--query`で必要な項目だけを取り、ARNを返す項目を取らない。Dockerソケットを渡さない。
  describeの結果は`.e2e/ministack-describe.json`、`docker inspect`の`Mounts`と公開ポートは`.e2e/ministack-inspect.json`に残す
- 終了経路（成功、失敗、`INT`、`TERM`）の`EXIT` `trap`は、失敗時は`collect`を呼んでから`swsc-ministack`だけを削除する
- `compare`は、完成版とdescribeの出力を、順序差（環境変数、コンテナ）と空の既定項目（`mountPoints`、`volumesFrom`など）を無視して比べる。
  null、空の配列、空のオブジェクトは同じとみなす（G2でdescribeは入力と一致した）
- MiniStackのイメージは`ministackorg/ministack:1.5.37`に固定する。問題が出た場合は`1.5.36`へ戻す。
  `tag@sha256`の参照形式にするかは、`docker image inspect`で貼り付けのダイジェストの種別を確かめてから決める
- `contract`の出力とログ（`docker logs`、`docker inspect`）は、識別情報の検査の前にマスクしてから保存する
- `unit`のケース: 一致、項目ごとに1つだけ違う入力（`image`、環境変数の値、`essential`、ポート、`dependsOn`、
  `healthCheck`、コンテナ数、`networkMode`）で不一致、環境変数の順序差と既定値の追加は一致
- 登録失敗で、段階名を示して終了コード1になること。認証情報が無いとき、偽の`docker`にコンテナ作成の呼び出しが無いこと
- 記録した`docker`の引数に、`docker.sock`と`--privileged`が無く、MiniStackの`-p`が`127.0.0.1:4566:4566`だけで、
  `swsc-`の名前とラベルが付くこと

### T912: pause方式のランナー（U7）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-902、FR-906、FR-910、FR-911、NFR-903、NFR-906、NFR-907 |
| 触るファイル | `scripts/e2e-runner.sh`、`scripts/e2e-taskdef.py`（`docker-args`）、`scripts/e2e-lib.sh`、`tests/m09-execution-and-ci.sh` |
| 依存 | T911、T903とT904の分岐 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「変換」と「引数の安全」の全ケースが通る |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh -n scripts/e2e-runner.sh`、`python3 -B -m py_compile scripts/e2e-taskdef.py` |

- `docker-args`は、コンテナごとに`.e2e/run/<name>.args`（1行1引数）と`.env`（`--env-file`用、パーミッション0600）を出す。改行を含む値は失敗させる
- 起動順は`plan.md` 3.3の表と下の段落に従う。WireMockの起動、管理APIの応答の待機、pause、Squidの順に固定する（G1）。
  `unit`に、偽の`docker`と`curl`の呼び出し記録で、この順序を固定するケースを足す。
  WireMockの宛先は、コンテナ名で渡す（G1で解決できた）
- `HEALTHY`の待機は`docker inspect`の`State.Health.Status`を読む。WireMockの待機はホストの`curl`、Squidの待機は`nc -z 127.0.0.1 3128`で、上限120秒
- `unit`のケース: `.args`と`.env`の内容、値が引数に出ないこと、`HEALTHY`の待機、
  未対応の条件（`COMPLETE`）と`CMD`形式の名指し、ポートの重複
- 記録した`docker`の引数に、`docker.sock`、`--privileged`、Squidとpauseの`-p`が無い。
  全ての作成に`swsc-`とラベルが付く。ランナーはMiniStackを起動しない（T911の`contract`が担当）

### T913: 入口の完成（U8）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-901、FR-903、FR-911、FR-912、FR-915、FR-916、FR-918、FR-920、FR-921、NFR-905、NFR-908 |
| 触るファイル | `scripts/e2e.sh`、`scripts/e2e-lib.sh`、`tests/m09-execution-and-ci.sh` |
| 依存 | T912 |
| 並列 | 不可 |
| 受け入れ条件 | `unit`の「前提検査」「ポートの確認」「`aws`を呼ばない経路」「stopとclean」「`test:ci`の順序」「収集」「FR-920」の全ケースが通る |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh -n scripts/e2e.sh scripts/e2e-lib.sh` |

- `start`、`test`、`logs`、`stop`、`clean`、`test:ci`、`collect`、`trap`を、`plan.md` 3.7、3.8、6章に従って完成させる
- `start`の本体は`start_main`関数とし、`trap`を持たせない。`start`操作（単独）のラッパーだけが、`start_main`の失敗時に`stop`する。
  ポートの確認は、`start_main`の中の、自分の`swsc-`の停止の後に置く（前提検査には含めない）。`python3`の`socket`で
  `127.0.0.1:8080`への接続を試み、応答があれば「`swsc-`以外が使用中」として止まる。メッセージに旧基盤の可能性を書く。
  旧基盤を名前で検出しない
- `start_main`は、完成版を`swsc_render`（T908）で作る。MiniStackとAWS CLIは使わない
- `test:ci`は、`set -e`の下で動く形にする。`start_main || rc=$?`で受け、`rc`が0のときだけ`test_run || rc=$?`、
  その後に`collect || true`、`stop || true`の順に呼び、`exit "$rc"`で返す（`plan.md` 3.8の擬似コード）。
  `EXIT`の`trap`は、`INT`と`TERM`で本体に届かなかった場合の最終防衛（`collect`、`stop`の順）に限る
- `unit`に、呼び出し順のケースを足す。偽で`start_main`失敗、`test`失敗、`collect`失敗を起こし、いずれも`collect`が`stop`より前に呼ばれ、
  `start_main`失敗でも`collect`に届き、終了コードが失敗の元の値を保つこと。`start`操作（単独）は、失敗時に`stop`を呼び、`collect`は呼ばないこと。
  `INT`が130、`TERM`が143
- `stop`と`clean`は、接頭辞`swsc-`とラベル`swsc.managed=true`の両方が一致するものだけを削除する。
  片方だけ一致するもの、他のプロジェクトのものを触らない。削除の順序と二重実行の終了コード0を固定する
- `collect`は冪等にする。対象なしで終了コード0。既存の収集物を壊さない
- 識別情報の検査は、`arn:aws`と、前後が英数字と`-`でない12桁の数字に限る。UUIDの偶然の一致を拾わないことを`unit`で固定する。
  一致した行はマスクし、再検査で残ったファイルは削除して`scrub.txt`にファイル名だけを記録する
- `scrub.txt`は、`collect`の実行ごとの先頭で作り直す。その回の削除または記録があるときだけ、単独の`collect`は終了コード1を返す。
  `unit`に、続けて2回実行した`collect`の2回目が、削除対象が無ければ終了コード0を返すケースを足す
- マスクの処理を入れる（G2: MiniStackの出力にはARNとダミーの12桁が含まれる）。CIの初回で、ログに実際に出るかを再確認する
- `swsc_wiremock_total`は、`/__admin/requests`の`requests[].request.url`が`/api/`で始まるものだけを数える。
  `/squid-internal-periodic/store_digest`を数えない（G1、G3）。`unit`に、偽の`curl`が返すJSONで固定するケースを足す
- FR-920の検査は、`scripts/e2e*.sh`、`ecs/`、`.github/workflows/e2e-test.yml`、`package.json`に対し、コマンドとして呼ぶ形
  （行頭、または`;`、`&&`、`\|`、`$(`の直後）の`docker-compose`と`docker compose`（空白区切り）が無いことを固定する。
  コメントとメッセージでは「旧基盤」と書く。`tests/`は対象外（偽の置き場）。`docker compose`を含む入力で検査が失敗するケースを足す

### T914: 実通信の検査（U9。`smoke`と`contract`のモード）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-904、FR-906、FR-907、FR-908、FR-909、FR-910、FR-911、FR-912、FR-922、NFR-902、NFR-903、NFR-906、NFR-907、NFR-908 |
| 触るファイル | `tests/m09-execution-and-ci.sh`（`smoke`と`contract`）。欠陥が見つかった場合だけ、原因のタスクのファイル |
| 依存 | T913 |
| 並列 | 不可（ポート8080と4566、`swsc-`の名前を使う） |
| 受け入れ条件 | エージェントが実行する`smoke`の1から11がすべて通る。終了後に1.2の後始末の確認が通る。`contract`のモードは実装し、`sh -n`と`unit`で構文と呼び出しを確かめる。実行はしない（T925で利用者が行う） |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh smoke`、引数なしの`sh tests/m09-execution-and-ci.sh`、1.2の確認コマンド |

- 事前に、1.1のColima設定を行い、ポート8080の空きを`swsc-`の停止の後に確かめる。使用中なら止めて報告する。
  `smoke`はAWS CLIとダミー認証情報を使わない。エージェントのシェルで環境変数を設定しない
- `smoke`は、開始時に`swsc-`の残りを`stop`で消し、`unit`が落ちたらDockerを起動しない
- 検査の内容は`plan.md` 5.2の表のとおり（1から11）。項目1は起動順（WireMock、pause、Squid）、項目2は`/api/`で始まる受信数だけを数えることを含む。
  7は、`swsc-`の接頭辞を付けない名前（例 `m09-smoke-port-holder`）の使い捨てのコンテナで8080を塞ぎ、`start`が
  「`swsc-`以外が使用中」として止まることを確かめる。検査の`trap`が、コンテナ名を指定して必ず回収する。
  6も同じコンテナを使い、`start`と`test:ci`が非ゼロで終わり、`swsc-`が残らず、`e2e-logs/`が作られることを確かめる
- 5は、2回目の`start`が、1回目の`swsc-wiremock`が8080を持つ状態でも止まらないことを確かめる
- 8は、子として本物の入口を起動し、`INT`で130、`TERM`で143になり、`swsc-`と`.e2e/`の一時物が残らないことを確かめる。
  `INT`の送信はM07の`smoke_child_signal`の方式を再利用する
- 10は、収集した`e2e-logs/`に12桁の数字とARNが無いことを確かめる
- 11は、`SQUID_UPSTREAM`に不正な値を渡して`test:ci`を起動し（本番のスクリプトに分岐を持ち込まない）、
  非ゼロで終わり、`e2e-logs/containers/swsc-squid.log`が作られ、空でないことを確かめる
- `smoke`は、全項目が成功したときだけ、自分が作った`e2e-logs/`を消す。失敗時は残す。`clean`は呼ばない。
  M03からM08、S14の検査と同時には動かさない
- `contract`のモードは、`unit`に続けて、`plan.md` 5.4のC1からC6を行う。ダミー認証情報の環境変数が無い場合は、
  `contract`が始まる前に「認証情報が無い」と表示して非ゼロで終わる（成功にしない）。実行は利用者の端末とCIだけである

### T915: CIワークフロー（U10）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-913、FR-914、FR-915、FR-916、FR-917、FR-918、NFR-901、NFR-902、NFR-904、NFR-905、NFR-910、NFR-911 |
| 触るファイル | `.github/workflows/e2e-test.yml`、`tests/m09-execution-and-ci.sh`（workflowの静的検査） |
| 依存 | T913（`collect`と`stop`が前提）、T914（`tests/m09`の編集をT914の後に直列にする。`smoke`と`contract`のモードがworkflowから呼ばれる） |
| 並列 | 不可（`tests/m09`を共有）。T916の文書本体とは並列にできる |
| 受け入れ条件 | `unit`の「workflow」「FR-920」の全ケースが通る |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`npm run lint:md` |

- 内容は`plan.md` 3.9に従う。`actions/checkout`と`actions/upload-artifact`の現行のメジャー版は、
  公式リポジトリで確認して書く（Q-908）。リスクR-10を文書に残す
- `concurrency`のグループは`${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}`、
  `cancel-in-progress`は`${{ github.event_name == 'pull_request' }}`にする（NFR-910。`main`のpushをコミットごとの別グループにする）
- 手順の順序は、チェックアウト、`unit`、`test-ci`、`smoke`、`contract`、`collect`（`if: always()`）、
  アップロード（`if: failure()`）、`stop`（`if: always()`）にする。`smoke`と`contract`のステップのタイムアウト（8分、5分）は仮値
- `unit`の静的検査: トリガー、`permissions`、`runs-on`、`timeout-minutes`、ダミーの`env`、`concurrency`のグループと`cancel-in-progress`、
  `if: always()`と`if: failure()`、アーティファクトの名前と保存期間、`secrets.`が無い、`run:`に`${{`が無い、
  `uses:`が2つの公式アクションだけ、ステップの順序、`docker compose`と`docker-compose`が無い
- PyYAMLがあるときだけ構文を読む。無いときは`SKIP`と表示し、成功として数えない
- このタスクでは、GitHub Actionsの実行は行わない（T924）

### T916: 文書（U11）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-919、NFR-905 |
| 触るファイル | `docs/ローカル実行とCI.md`（新規）、`README.md`、`AGENTS.md`（品質ゲート表の行）、`tests/m09-execution-and-ci.sh`（文書の検査） |
| 依存 | T913。文書本体の下書きはT913の後に開始できる。所要時間の節は空けておく |
| 並列 | 文書本体はT914、T915と並列にできる。`tests/m09`の編集はT915の後 |
| 受け入れ条件 | `unit`の「文書」が通る。M07、M08、S14の`unit`と`static`が通る。`npm run lint:md`が0件 |
| 検査コマンド | `sh tests/m09-execution-and-ci.sh unit`、`sh tests/m07-scenario-isolation.sh`の`unit`相当、`sh tests/m08-e2e-suite.sh unit`、`sh tests/s14-compose-port-binding.sh`の`static`相当、`npm run lint:md` |

- 先に、M07、M08、S14の検査が`README.md`と`docs/`の何を`grep`しているかを読み、既存の行を書き換えず、足す変更を中心にする
- `docs/ローカル実行とCI.md`の節は`plan.md` 9章の表に従う。M08の`docs/E2Eテスト.md`と同じ体裁にする
- ダミー認証情報の設定手順は、利用者が自分のターミナルで行うことを書く（`contract`だけが要る）。リポジトリに設定を置かないことを書く。
  `start`、`test`、`smoke`は認証情報を要らないことを書く
- 「検査の層と実行主体」の節に、`unit`、`smoke`、`contract`の違いと、エージェントとCIと利用者の端末のどれが実行するかを書く。
  品質ゲートに登録するのは`unit`と`smoke`であることを書く
- `README.md`は、実行手順を`npm run <操作>`に更新する。旧Compose手順は消さず、「移行完了後に削除」と明記する
- `AGENTS.md`の品質ゲート表に、新基盤の行を足す（表の末尾の「Ministackを追加した場合は表へ追加する」に従う）。既存の行は書き換えない
- 文書、README、AGENTS.mdに、AWSアカウントID、ARN、認証情報を書かない。MiniStackのダミーのIDも書かない
- ゲートの結果の節に、`gate-results.md`の判定表の要約を書く

### T917: 品質ゲートへの登録（U12。`unit`と`smoke`）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-922、NFR-904 |
| 触るファイル | `scripts/quality-gate.sh` |
| 依存 | T914、T916 |
| 並列 | 不可（ポートを使う） |
| 受け入れ条件 | `unit`と`smoke`がゲートに登録され、`contract`は登録されていない。`smoke`の実測値が記録され、ゲートが通り、残存の検査が通る。ゲートの実行にダミー認証情報の環境変数は要らない |
| 検査コマンド | `sh scripts/quality-gate.sh`の前後の所要時間、`sh -n scripts/quality-gate.sh`、1.2の確認コマンド |

- `unit`を登録する。M09の対象ファイル（`scripts/e2e*`、`ecs/`、`tests/m09`、workflow、`docs/ローカル実行とCI.md`）の変更時に実行する
- `smoke`を登録する。AWS CLIと認証情報を使わないため、エージェントのシェルでゲートを通せる。
  M03からM07、S14の所要時間の合計を基準値として計測し、M09の`smoke`が基準値の半分以下で、
  ゲート全体が登録前の1.5倍以内であることを確かめる。超える場合は、実測値を示して利用者に確認する（登録を自動では外さない）
- `contract`は登録しない（ダミー認証情報の環境変数が要り、エージェントのシェルでは設定できないため。NFR-902、FR-922）
- 実行条件は、`docker-compose`を使う既存のブロックの後ろに、独立したブロックで置く。既存の行と`has_match`の条件は変えない
- `squid-config/`、`test-client/`、`wiremock-scenarios/`の変更時も、M09の検査を実行する
- ブロックの最後に、`docker ps -aq --filter label=swsc.managed=true`が空であることを確かめる
- `ecs/squid/*.sh`の`sh -n`と、`.py`の`python3 -B -m py_compile`は、M09の`unit`で行う
- 判断と実測値はT918の報告に含める

### T918: 最終確認（U13）

| 項目 | 内容 |
| --- | --- |
| 要件 | `spec.md` 7章の完了条件すべて、FR-920、FR-922、NFR-901、NFR-903、NFR-911 |
| 触るファイル | なし（確認のみ。失敗があれば原因のタスクへ戻って直す） |
| 依存 | T917 |
| 並列 | 不可（ポート8080と4566、`swsc-`の名前を使うため、検査を順に実行する） |
| 受け入れ条件 | 下記のエージェントが実行するコマンドが順にすべて成功する。`contract`は、T925の結果が記録されているか、未検証と明記されている。変更ファイルが`plan.md` 2.1と2.2の一覧に収まる |
| 検査コマンド | 下記 |

- 1.1のColima設定を行い、`sh tests/m09-execution-and-ci.sh unit`（Dockerなし）と`smoke`を実行する。
  エージェントのシェルでは、AWS CLIとダミー認証情報を使わない
- `contract`は実行しない。T925の結果（`contract-results.md`）があれば内容を確かめ、無ければ「未検証」と報告に明記する
- `smoke`を2回、別々に起動し、結果の行が同じであることを比べる（NFR-908）
- 既存の検査を個別に実行し、結果が変わらないことを確かめる:
  `sh tests/m03-wiremock-scenarios.sh`、M04からM08の検査入口、`sh tests/s14-compose-port-binding.sh`
  （M02は稼働中のスタックが要るため、ゲートからは実行しない）
- `sh -n`（`scripts/e2e*.sh`、`ecs/squid/*.sh`、`tests/m09-execution-and-ci.sh`）と、`python3 -B -m py_compile scripts/e2e-taskdef.py`
- `npm run lint:md`、`git diff --check`
- `git diff --name-only origin/main...HEAD`が、`plan.md` 2.1と2.2の一覧に収まる（`git status --short`の未追跡も合わせて見る）
- `docker-compose.yml`、`tests/m02`から`m08`、`tests/s14-compose-port-binding.sh`、`squid-config/`、`wiremock-scenarios/`、
  `test-client/`、`Dockerfile.test-client`、`scripts/scenario-lib.sh`に差分が無い（`git diff --stat`）
- NFR-901の確認として、`aws`の直接呼び出しが`swsc_aws`の1か所だけで、毎回`--endpoint-url`が付くことを、`unit`の結果と`grep`で確かめる
- `spec.md` 7章の完了条件の各項目に対応する検査があることを突き合わせる
- 実行後に、1.2の後始末の確認（ラベル、名前、ネットワーク、`.e2e/`、`e2e-logs/`、`$KIROCREW_SCRATCH`の写し）を行う
- 実装後の整合確認として、`spec.md`、`plan.md`、`tasks.md`、`clarify.md`の番号と数値（FR/NFR/タスクの番号、モード名、コマンド名）に
  食い違いが無いことを確かめる

### T919: 必須レビュー1 evidence-code-review

| 項目 | 内容 |
| --- | --- |
| 要件 | コミット前の必須レビュー（AGENTS.md） |
| 触るファイル | なし（レビューの結果を受けた修正は、原因のタスクのファイル） |
| 依存 | T918 |
| 並列 | 不可（T920と直列。1スキル1サブエージェント） |
| 受け入れ条件 | `evidence-code-review`の報告に、未対応の重要な指摘が無い。修正した場合は、該当の検査を再実行している |
| 検査コマンド | `sh scripts/review-snapshot.sh m09`（スナップショットの作成） |

- メインエージェントが、`sh scripts/review-snapshot.sh m09`でスナップショットを作り、レビュー対象マニフェストを依頼文に含める
- サブエージェントを1つだけ起動し、依頼文に`/Users/satoshi/.kiro/crew/skills/evidence-code-review/SKILL.md`を明記して、
  `read`で本文を読ませる。本文を読めなかった結果は、正式な結果として扱わず、再実行する
- 重い検査（`smoke`、品質ゲート）はサブエージェントに実行させない
- 指摘のうち、SHOULD、BETTER、NITSだけを理由に同じレビューを繰り返さない。新たな実質変更が無い限り、残件を記録して停止する
- 実質的な修正をした場合は、T918の該当部分を再実行する
- サブエージェントの設定は、AGENTS.mdの「サブエージェントの実行条件」の表に従い、次の必須値で起動する:
  1スキルにつき1サブエージェント、`include_memory=false`、`include_lessons=false`、`include_project=true`、effort `medium`、
  ファイル変更禁止、Git操作禁止。モデルは、AGENTS.mdの推奨に従い、利用可能な一覧から解決する
- 実質的な修正で変更範囲が広がった場合は、T919とT920の2つのレビューを、スナップショットから再実行する

### T920: 必須レビュー2 security-review

| 項目 | 内容 |
| --- | --- |
| 要件 | コミット前の必須レビュー（AGENTS.md）、NFR-901、NFR-902、NFR-906、NFR-907 |
| 触るファイル | なし（レビューの結果を受けた修正は、原因のタスクのファイル） |
| 依存 | T919の完了 |
| 並列 | 不可（T919と直列） |
| 受け入れ条件 | `security-review`の報告に、未対応の重要な指摘が無い。修正した場合は、該当の検査を再実行している |
| 検査コマンド | `sh scripts/review-snapshot.sh m09` |

- T919の修正が入った場合は、スナップショットを作り直す
- サブエージェントを1つだけ起動し、依頼文に`/Users/satoshi/.kiro/crew/skills/security-review/SKILL.md`を明記して、`read`で本文を読ませる
- 重点は、認証情報の扱い（ダミー値、`~/.aws`を読まない）、Dockerソケットを渡さないこと、ポートの公開範囲、
  設定の注入（`SQUID_MOCK_*`）、CIの権限とインジェクション（`${{ }}`）、アーティファクトの識別情報、`swsc-`の回収の対象範囲
- 実質的な修正をした場合は、T918の該当部分を再実行する。2つのレビューの結果は、T921の前に揃える
- サブエージェントの設定は、T919と同じ必須値（`include_memory=false`、`include_lessons=false`、`include_project=true`、
  effort `medium`、ファイル変更禁止、Git操作禁止）にする。T920の修正が変更範囲を広げた場合は、T919とT920をスナップショットから再実行する

### T921: 品質ゲート

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-922、NFR-904、M09全体（コミット前の最終ゲート） |
| 触るファイル | なし（確認のみ） |
| 依存 | T920 |
| 並列 | 不可（全タスクの完了後に単独で実施） |
| 受け入れ条件 | ゲートが成功し、終了時にコンテナの残存が無い。結果を記録する。ゲートの実行にダミー認証情報は要らない |
| 検査コマンド | `sh scripts/quality-gate.sh`、続けて`docker ps -aq --filter label=swsc.managed=true` |

- 1.1のColima設定を行ってから、すべての修正の後に一度だけ最終実行する。失敗した場合は、原因のタスクへ戻って直し、再実行する
- エージェントのシェルでAWS認証情報の環境変数を設定しない。ゲートの中でM09の`unit`と`smoke`が実行されたことを出力で確かめる
- `contract`はゲートに含まれない。報告に、`contract`の状態（T925の結果、または未検証）を明記する
- 実行後に、1.2の後始末の確認を行う
- このタスクで`git commit`、`git push`、PR作成は行わない

### T922: コミット対象の確認（コミットは利用者の指示後）

| 項目 | 内容 |
| --- | --- |
| 要件 | 1.2のコミット対象の確認 |
| 触るファイル | なし（確認のみ。コミット自体は利用者の指示を待つ） |
| 依存 | T921 |
| 並列 | 不可 |
| 受け入れ条件 | コミット対象の一覧が`plan.md` 2.1と2.2に収まり、`.kiro/settings/cli.json`が含まれない |
| 検査コマンド | `git status --short`、`git diff --name-only`、`git ls-files --others --exclude-standard`、`git diff --cached --name-only` |

- コミット対象を1ファイルずつ名指しで示す（新規: `ecs/`、`scripts/e2e*.sh`、`scripts/e2e-taskdef.py`、`tests/m09-execution-and-ci.sh`、
  `.github/workflows/e2e-test.yml`、`docs/ローカル実行とCI.md`、`specs/M09-execution-and-ci/`。変更: `package.json`、`.gitignore`、
  `README.md`、`AGENTS.md`、`scripts/quality-gate.sh`（登録した場合））
- `.kiro/settings/cli.json`、`.e2e/`、`e2e-logs/`、`$KIROCREW_SCRATCH`の写し、実験の生ログが一覧に無いことを確かめる
- ステージ後に、`git diff --cached --name-only`の中に`.kiro/settings/cli.json`が無いことを確かめる
- 公開物の最終確認として、コミット対象に対し`grep -Er 'arn:aws|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)'`を実行し、
  実値が無いことを確かめる（検査コードの正規表現の記述は除く）
- コミットの前に、`git add`は名指しで行い、利用者の指示を待つ。`git push`とPR作成も指示後とする

### T923: 別Issueの起票（利用者の承認後）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-920、`spec.md` 7章（別Issueとして起票）、Q-912 |
| 触るファイル | なし（Issueの起票。リポジトリのファイルは変更しない） |
| 依存 | T921。起票は利用者の承認が前提 |
| 並列 | T922、T924と並列にできる（ファイルを変更しない） |
| 受け入れ条件 | `plan.md` 11.1と11.2の2件が、案どおりに起票されている。Issue本文にアカウントIDとARNが無い |
| 検査コマンド | `gh issue view <番号>`で本文を確認（起票後） |

- 利用者の承認が出るまで、Issueを編集せず、起票しない
- 起票内容は`plan.md` 11章の案どおりにする: 11.1（既存検査のECSタスク定義方式への移行。受け入れ条件9件）、
  11.2（docker-compose.ymlの削除。11.1の完了に依存。受け入れ条件7件）
- 優先度はM09の直後とする。Issue #9にも、新方針との差分（Composeからタスク定義方式）の注記を、利用者の判断で足す
- Issue番号は、`spec.md`の完了条件（別Issueとして追跡）に反映するかを利用者に確認する

### T924: CI初回の確認（U14。PR作成後。利用者の指示後）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-917、FR-919、NFR-904。G1とG3のLinuxでの再確認 |
| 触るファイル | `docs/ローカル実行とCI.md`（所要時間の節）。結果によって`.github/workflows/e2e-test.yml`と`specs/M09-execution-and-ci/gate-results.md` |
| 依存 | T922。PRの作成は利用者の指示を待つ |
| 並列 | 不可 |
| 受け入れ条件 | `plan.md` 10章のCI初回の項目（確認項目2、3、16から19）が記録される |
| 検査コマンド | `gh run list`、`gh run view`（PR作成後） |

- PRを作成した後に、workflowの実行結果を確認する。PR本文にアカウントID、ARN、実値を書かない
- 確認項目2と3: Linuxのランナーでpause方式と`local_src`が動く。G1とG3のColimaの結果との差を`gate-results.md`に記録する
- G1またはG3の分岐がCIで覆った場合（名前解決が通らない、送信元が`local_src`に一致しない、など）は、手戻りの手順に従う:
  `gate-results.md`に覆った事実と原因を記録し、T910（`derive-config.sh`）またはT912（ランナー）、T903またはT904の決定へ戻って直し、
  `unit`と`smoke`を再実行する。直した内容はPRに追加のコミットで載せる（利用者の指示に従う）
- 確認項目16: `ubuntu-24.04`のDocker、AWS CLI v2、`python3`、`curl`、Nodeのバージョン
- 確認項目17: `unit`、`test:ci`、`smoke`、`contract`の各ステップの時間と合計。`test:ci`の10分、`smoke`の8分（仮値）、
  `contract`の5分（仮値）のステップと、15分のジョブに収まる。設定値の1/2を超えたら、値と根拠を文書に残す。
  ジョブの上限を超える場合は、見直しを利用者に確認する。Docker Hubのレート制限による取得の失敗が出たかも記録する（R-16）
- `contract`のCI実行の結果を、T925の記録と照らして確認する（ローカルでは未検証でも、CIで実行される）
- 確認項目18: 一時ブランチで失敗を注入し、アーティファクトが取得でき、中身に識別情報が無い。一度だけ行い、本番のworkflowに分岐を入れない
- 確認項目19: 同じPRに2回pushして、1回目が取り消される。`main`へのpushは、短時間に複数回pushしても、互いに取り消されない
  （`concurrency`のグループがコミットごとに別であること。`main`へのpushを確認できるのはマージ後のため、利用者の指示に従う）
- 失敗した場合は、アーティファクトから原因を特定してから直す。原因を確かめずに同じ処理を再実行しない
- 結果を`docs/ローカル実行とCI.md`の「所要時間の目安」に反映し、`npm run lint:md`を通す
- 一時ブランチは検証後に破棄する。pushとブランチの削除は、利用者の指示に従う

### T925: `contract`の実行と結果の記録（U9。利用者の端末。エージェントは実行しない）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-904、FR-905、FR-922、NFR-902、NFR-906 |
| 触るファイル | `specs/M09-execution-and-ci/contract-results.md`（新規） |
| 依存 | T914（`contract`のモードの実装）。T918と並べて進めてよい。T919以降の着手の前提にはしない |
| 並列 | 不可（ポート4566と`swsc-`の名前を使う。T914、T918、T921と同じホストなら直列） |
| 受け入れ条件 | 利用者の貼り付けで、`plan.md` 5.4のC1からC6が記録され、すべて通っている。または、貼り付けが得られず「未検証」と明記されている |
| 検査コマンド | 利用者が自分のターミナルで実行する（下記）。判定側は`contract-results.md`の記録と、貼り付けに12桁の数字、ARN、認証情報が無いことの確認 |

`contract`はダミー認証情報の環境変数が要り、エージェントのシェルでは設定できない（NFR-902）。
エージェントは、手順を書いて利用者の端末で実行してもらい、貼り付けを受けて記録する。

エージェントが行うこと

- 事前に、`sh tests/m09-execution-and-ci.sh unit`が通り、`contract`のモードが実装されていること（T914）を確かめる
- 下記の手順と、貼り付けてほしい項目を利用者に提示し、ここで一度止まる
- 貼り付けを受けたら、`contract-results.md`に記録する。環境（日時、Docker runtime、MiniStackのタグ）、手順、C1からC6の結果を書く。
  貼り付けに12桁の数字、ARN、認証情報が含まれる場合は、記録する前に`<ACCOUNT_ID>`などの記号に置き換える

利用者の端末で実行する手順（リポジトリルートで実行）

```sh
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-northeast-1
# Colimaを使う場合のみ（DOCKER_HOSTを設定）
export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock
env | grep -c '^AWS_'   # 実AWSの認証情報が入っていないことを確かめる（出力は3であること）
sh tests/m09-execution-and-ci.sh contract
docker ps -aq --filter label=swsc.managed=true   # 空であること
```

貼り付けてほしい内容は、`contract`の標準出力（C1からC6の結果の行）と終了コードである。
アカウントIDとARNの実値、認証情報、`~/.aws`の内容は貼らない。

貼り付けが得られない場合は、`contract`を未検証として報告し、成功と断定しない。CIの初回（T924）で実行結果を確認する。

### T926: 任意レビュー aws-well-architected-review-lite

| 項目 | 内容 |
| --- | --- |
| 要件 | `plan.md` 10章（任意スキルレビュー） |
| 触るファイル | なし（レビューの結果を受けた修正は、原因のタスクのファイル） |
| 依存 | T920。T921の前に行う |
| 並列 | 不可（T919、T920の後。1スキル1サブエージェント） |
| 受け入れ条件 | 報告に、未対応の重要な指摘が無い。または、見送る判断と理由が報告に書かれている |
| 検査コマンド | `sh scripts/review-snapshot.sh m09` |

- CI/CDとネットワークを変更するため、`aws-well-architected-review-lite`を実行する（`plan.md` 10章）
- T919と同じ設定（1サブエージェント、`SKILL.md`を`read`で読ませる、`include_memory=false`、`include_lessons=false`、
  `include_project=true`、effort `medium`、ファイル変更禁止、Git操作禁止）にする。重い検査は実行させない
- 見送る場合は、理由を報告に書く。任意のため、この結果でT921をブロックしない（SHOULD、BETTER、NITSだけを理由に繰り返さない）

## 3. 依存関係

`plan.md` 8章の順を守る。T901からT906のゲートが全体を止め、T907からT915は検査ファイルを共有するため直列に進む。

| タスク | 依存 | 並列にできる相手 |
| --- | --- | --- |
| T901 | なし | なし |
| T902 | T901 | なし |
| T903 | T902 | なし |
| T904 | T903 | なし |
| T905 | T904、利用者の貼り付け | なし |
| T906 | T901からT905 | なし |
| T907 | T906 | なし |
| T908 | T907 | なし |
| T909 | T908 | なし |
| T910 | T909 | なし |
| T911 | T910 | なし |
| T912 | T911 | なし |
| T913 | T912 | なし |
| T914 | T913 | T916の文書本体 |
| T915 | T913、T914 | T916の文書本体 |
| T916 | T913（文書本体）、T915（`unit`の文書検査） | 文書本体のみT914、T915と並列 |
| T917 | T914、T916 | なし |
| T918 | T917 | なし |
| T919 | T918 | なし |
| T920 | T919 | なし |
| T921 | T920（T926は任意で、T921の前に行う） | なし |
| T922 | T921 | T923 |
| T923 | T921、利用者の承認 | T922 |
| T924 | T922、利用者の指示 | なし |
| T925 | T914、利用者の端末での実行 | なし（T918と並べて進めてよい。ホストが同じなら直列） |
| T926 | T920 | なし |

## 4. 要件対応表

`plan.md` 8.1の対応を、タスクに置き換えた。FR-901からFR-922の22件とNFR-901からNFR-911の11件、合計33件を含む。

| 要件 | タスク |
| --- | --- |
| FR-901 | T907、T913 |
| FR-902 | T905、T906、T908、T912 |
| FR-903 | T908、T913 |
| FR-904 | T905、T906、T911、T914、T925 |
| FR-905 | T907、T911、T914、T925 |
| FR-906 | T904、T912、T914 |
| FR-907 | T904、T914 |
| FR-908 | T910、T914 |
| FR-909 | T909、T910、T914 |
| FR-910 | T903、T906、T912、T914 |
| FR-911 | T912、T913、T914 |
| FR-912 | T907、T913、T914 |
| FR-913 | T915 |
| FR-914 | T915 |
| FR-915 | T913、T915 |
| FR-916 | T913、T915 |
| FR-917 | T915、T924 |
| FR-918 | T911、T913、T915 |
| FR-919 | T916、T924 |
| FR-920 | T907、T913、T918 |
| FR-921 | T913 |
| FR-922 | T914、T917、T918、T925 |
| NFR-901 | T911、T915、T918 |
| NFR-902 | T907、T911、T914、T915、T925 |
| NFR-903 | T912、T914、T918 |
| NFR-904 | T915、T917、T924 |
| NFR-905 | T908、T913、T915、T916 |
| NFR-906 | T911、T912、T914、T925 |
| NFR-907 | T912、T914 |
| NFR-908 | T913、T914 |
| NFR-909 | T902、T905、T907、T908 |
| NFR-910 | T915 |
| NFR-911 | T901、T908、T915、T918 |

### 4.1 欠けの確認

| 確認項目 | 結果 |
| --- | --- |
| FR-901からFR-922（22件）で、対応するタスクが無いもの | なし |
| NFR-901からNFR-911（11件）で、対応するタスクが無いもの | なし |
| `plan.md` 8章のU1からU14で、対応するタスクが無いもの | なし（U1はT901からT906、U9はT914とT925、U14はT924） |
| `plan.md` 4章のG1からG5で、対応するタスクが無いもの | なし（G4はT901、G5はT902、G1はT903、G3はT904、G2はT905） |
| `spec.md` 7章の完了条件で、検査が無いもの | なし（T918で突き合わせる） |

要件IDを持たないタスクは、T906（ゲートの判定）、T919からT923（レビュー、品質ゲート、コミット、Issue）、T926（任意レビュー）である。

## 5. 完了条件

- [x] T901からT906のゲートを通過し、全ゲートの分岐が`gate-results.md`に記録されている
- [x] G2の結果を利用者の端末の貼り付けで判定し、固定したMiniStackのタグを記録している
- [ ] T907からT918を完了している
- [ ] `sh tests/m09-execution-and-ci.sh unit`がDockerなしで通る
- [ ] `sh tests/m09-execution-and-ci.sh smoke`が通り、引数なしでも通る。AWS CLIとダミー認証情報は使っていない
- [ ] `contract`の結果が、利用者の貼り付け（T925、`contract-results.md`）で記録されている。または、未検証と明記されている
- [ ] 失敗経路（`start`失敗、`test`失敗、`collect`失敗、`INT`、`TERM`、ポート衝突）の終了コードと回収を確かめている。
  `start`失敗時に、`collect`が`stop`より先に走り、`e2e-logs/containers/`が作られる（`smoke`の11）
- [ ] `docs/ローカル実行とCI.md`があり、`README.md`と`AGENTS.md`が更新されている
- [ ] 品質ゲートに`unit`と`smoke`が登録され（`contract`は登録しない）、`smoke`の実測値が記録されている
- [ ] `evidence-code-review`と`security-review`を直列に実行し、未対応の重要な指摘が無い。任意レビュー（T926）を実行したか、見送った理由がある
- [ ] `sh scripts/quality-gate.sh`が成功している
- [ ] `docker ps -aq --filter label=swsc.managed=true`が空で、`.kiro/settings/cli.json`と一時物がコミット対象に無い
- [ ] 別Issue（11.1、11.2）が、利用者の承認後に起票されている
- [ ] CI初回の確認（T924）が記録されている（PR作成後）
- [ ] `spec.md`、`plan.md`、`tasks.md`、`clarify.md`が、`analyze`の確認で整合している
