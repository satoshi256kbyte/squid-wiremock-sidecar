# ローカル実行とCI

ECS のサイドカー構成（Client、Squid、WireMock）を、ローカルと CI で同じ完成版のタスク定義から起動して検査する。
入口は `scripts/e2e.sh` で、`npm run` から呼ぶ。検査は `tests/m09-execution-and-ci.sh` にある。
設計と判定の記録は `specs/M09-execution-and-ci/` にある。

## 実行方法

```sh
npm run start
npm run test
npm run logs
npm run stop
npm run clean
npm run test:ci
```

| 操作 | 内容 |
| --- | --- |
| `start` | WireMock、管理APIの応答の待機、pause、Squid の順に起動する |
| `test` | Client を実行し、ステータスと WireMock の受信数を検査する |
| `logs` | コンテナのログを表示する。後ろに引数を続けられる |
| `stop` | 起動したコンテナとネットワークを削除する |
| `clean` | `stop` に加えて、生成物（`.e2e/`）と収集ログ（`e2e-logs/`）を削除する。目印（`.swsc-managed`）が無いディレクトリは、削除せずに失敗する |
| `test:ci` | `start`、`test`、`collect`、`stop` を続けて実行する。CI と同じ順序である |
| `test:ci <シナリオ名...>` | M08 の代表シナリオから選んだものを、直列に1回ずつ実行する。名前は `normal`、`error-500-then-200`、`ratelimit-429`、`slow-5000` のいずれか |

M08 の4シナリオは、`npm run test:ci` には含まれない。CI と同じ検査は次の1行で実行する。

```sh
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000
```

出力先は、環境変数 `SWSC_E2E_DIR`（既定は `.e2e/`）と `SWSC_LOG_DIR`（既定は `e2e-logs/`）で変えられる。
どちらも `/` 以外の絶対パスで指定する。
空でない既存のディレクトリや、シンボリックリンクは拒否される。
swsc が作ったディレクトリには目印を置き、`clean` はその目印があるものだけを削除する。

Colima を使う環境では、実行の前に `DOCKER_HOST` を Colima のソケットに向ける。

```sh
if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
  export DOCKER_HOST=unix:///$HOME/.colima/default/docker.sock
fi
```

Colima を使っていない環境では、Docker の runtime と context を変更しない。
Compose は使わない。新基盤は `docker-compose` を呼ばず、`docker run` で直接コンテナを作る。

終了コードは次のとおり。`test:ci` は、途中の失敗があっても後始末を行い、失敗の元の終了コードを返す。

| 終了コード | 意味 |
| --- | --- |
| 0 | 成功 |
| 1 | 検査が失敗した。または、前提（ポートの空き、起動）が満たされなかった |
| 2 | 引数の誤り |
| 130、143 | 実行中に `INT` または `TERM` を受けた。後始末の後に終了する |

## ダミー認証情報の設定

AWS CLI が要るのは `contract` だけである。`contract` は MiniStack に対して、ダミーの認証情報で動く。
次の環境変数の名前を使う。

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`

値は、利用者が自分のターミナルで設定する。値の指定が要る箇所は「公式の MiniStack の案内に従う」。
リポジトリに認証情報や設定を置かない。
実際の AWS の認証情報は、この環境変数に入れない。`contract` の前に、`env | grep -c '^AWS_'` などで確かめる。

`start`、`test`、`test:ci`、`smoke` は認証情報を要らない。
エージェントのシェルでは環境変数を設定しないため、`contract` を実行しない。
CI は、workflow の `env` にダミーの値を書いて `contract` を実行する。

## 検査の層と実行主体

| 層 | コマンド | Docker | AWS CLI と認証情報 | 実行主体 | 品質ゲート |
| --- | --- | --- | --- | --- | --- |
| `unit` | `sh tests/m09-execution-and-ci.sh unit` | 使わない | 使わない | エージェント、CI | 登録する |
| `smoke` | `sh tests/m09-execution-and-ci.sh smoke` | 使う（pause 方式の通信） | 使わない | エージェント、CI | 登録する |
| `contract` | `sh tests/m09-execution-and-ci.sh contract` | 使う | 要る（ダミーの値） | 利用者の端末、CI | 登録しない |

- `unit` は、偽の `docker`、`aws`、`docker-compose` を PATH の先頭に置き、Docker と AWS に触れずに検査する。
- `smoke` は、WireMock、Squid、Client を実際に起動して通信を検査する。
- `contract` は、完成版を MiniStack に登録し、describe の結果と比べる。
- 品質ゲート（`sh scripts/quality-gate.sh`）に登録するのは `unit` と `smoke` だけである。`contract` は登録しない。

## 構成

| 部品 | 役割 |
| --- | --- |
| テンプレート（`ecs/task-definition.template.json`） | Client と Squid の2コンテナを定義する。値は `scripts/e2e-taskdef.py` が埋める |
| 完成版（`.e2e/taskdef.json`） | `start` と `contract` が、同じ入力から同じ方法で作る。コミットしない |
| pause 方式（`scripts/e2e-runner.sh`） | pause コンテナの名前空間に Client と Squid を入れる。Client は Squid を `127.0.0.1` で使う |
| Squid（`ecs/squid/`） | 上流の設定（`SQUID_UPSTREAM`）から派生した設定で起動する。`mock` は WireMock へ、`direct` は外部へ向ける |
| MiniStack（`contract` だけ） | `ministackorg/ministack:1.5.37` を、`127.0.0.1:4566` だけに公開して起動する。Docker のソケットは渡さない |

### 起動と停止

起動順は、WireMock、WireMock の管理APIの応答の待機、pause、Squid の順である。
Squid は WireMock の名前を解決してから起動するため、この順序を守る。

停止は `docker rm -f` で行う。`docker stop` は使わない。
Squid の元のエントリポイントは SIGTERM を `squid` へ転送しないため、`docker stop` では Squid が止まらない（G5）。
`stop` は、接頭辞 `swsc-` とラベル `swsc.managed=true` の両方が一致するものだけを削除する。
他のプロジェクトのコンテナとネットワークは消さない。

### 固定ポートのロック

8080、3128、4566 は、ホスト全体で1つしか使えない。
そのため、入口の `start`、`test`、`test:ci`、`smoke` は、同じ場所のロックを取ってから動く。

- 既定の場所は `/tmp/swsc-e2e-ports.lock` である。`SWSC_LOCK_DIR` で変えられる。
  `$TMPDIR` は使わない。端末やプロセスごとに変わるため、別の実行と排他できないからである。
- ロックは `mkdir` の原子性で取る。ロックの中に、所有者の PID と開始時刻を書く。
- ロックを取った後に、8080 と 3128 と 4566 の空きを確かめる。
- `test:ci` は、トップで1回だけロックを取る。配下の検査へ `SWSC_LOCK_HELD=1` を渡し、二重に取らない。
- 後始末（収集、停止、ロック解放）は、`INT` と `TERM` を受けたときも行う。

ロックが残ったときは、自動では消えない。次の順で確かめてから消す。

1. `ls -ld "$SWSC_LOCK_DIR"`（未設定なら `/tmp/swsc-e2e-ports.lock`）で、ロックの PID と開始時刻を見る。
2. その PID のプロセスが無いことを確かめる。
3. `docker ps -a --filter label=swsc.managed=true` で、管理対象のコンテナが無いことを確かめる。
4. 3つとも問題がなければ、`rmdir` でロックのディレクトリを消す。

### 検査の数え方

`test` は、WireMock の受信数を `/__admin/requests` の記録から数える。数えるのは、URL が `/api/` で始まるものだけである。
Squid が内部で出す要求（`/squid-internal-periodic/` など）は数えない（G1、G3）。

## 旧基盤との関係

旧基盤（`docker-compose.yml`）は、S26 の移行の完了とともに削除した（T2630）。
リポジトリに Compose の定義は無く、全ての検査は新基盤で動く。

- 古いクローンなどで旧基盤を動かしている場合は、先に止める。どちらも 8080 のポートを使い、新基盤の起動が止まる。
- M08 の4シナリオは、新基盤の `sh tests/m08-e2e-suite.sh smoke` と `sh scripts/e2e.sh test:ci <シナリオ名...>` で実行する。

## CIの見方

ワークフローは `.github/workflows/e2e-test.yml` にある。

- トリガーは、pull request（全ブランチ）と、`main` への push である。
- ジョブは `ubuntu-24.04` で動き、上限は15分である。
- 権限は `contents: read` だけである。

ステップは次の順に動く。

| 順序 | ステップ | 内容 | 上限 |
| --- | --- | --- | --- |
| 1 | mise の導入（`jdx/mise-action`） | mise を固定版で導入し、`--locked shellcheck` で shellcheck を導入する。名前を付けない `uses` である | 上限なし（job 全体の15分に従う） |
| 2 | `shellcheck` | `git ls-files` の `*.sh` を、導入した shellcheck で検査する | 3分 |
| 3 | `unit` | `sh tests/m09-execution-and-ci.sh unit` | 3分 |
| 4 | `test-ci` | `npm run test:ci` の後に、M08 の4シナリオを `sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000` で実行する | 10分 |
| 5 | `smoke` | `sh tests/m09-execution-and-ci.sh smoke` | 8分 |
| 6 | `contract` | `sh tests/m09-execution-and-ci.sh contract` | 5分 |
| 7 | `collect` | `sh scripts/e2e.sh collect`。失敗しても必ず実行する | - |
| 8 | アップロード | `e2e-logs/` を保存する。失敗時だけ実行する | - |
| 9 | `stop` | `npm run stop`。必ず実行する | - |

失敗したときは、実行結果のページの Artifacts から `e2e-logs-<実行ID>-<試行回数>` をダウンロードする。
保存期間は7日である。

収集ログは、保存の前に識別情報（ARN と12桁の数字）をマスクする。
マスクしても残るファイルは削除し、ファイル名だけを `scrub.txt` に記録する。
ログを共有する前に、`scrub.txt` と中身を確かめる。

## 所要時間の目安

CI の値は、CI の初回実行で実測した（PR #29、`ubuntu-24.04`、2026-11-07）。

| ステップ | M09 の初回（PR #25） | S26 の初回（PR #29） | 上限 | 上限の根拠 |
| --- | --- | --- | --- | --- |
| `unit` | 22秒 | 29秒 | 3分 | 実測の6倍以上。実の Docker を使わず（偽の `docker` で検査する）、起動の待ち上限に依存しない |
| `test-ci` | 37秒 | 57秒 | 10分 | 実測の10倍以上。起動は2回で、各回に WireMock の待ちと Squid の healthy 待ちがある（それぞれ上限は `SWSC_WAIT_SECONDS`、既定120秒） |
| `smoke` | 74秒 | 85秒 | 8分 | 実測の5倍以上。起動の WireMock の待ちと Squid の healthy 待ち（それぞれ上限120秒）を含む |
| `contract` | 32秒 | 37秒 | 5分 | 実測の8倍以上。MiniStack の待ち上限（`SWSC_CONTRACT_WAIT_SECONDS`、既定120秒）を含む |
| ジョブ全体 | 約2分46秒 | 212秒 | 15分 | 実測の4倍以上 |

`test-ci` の増分（約20秒）は、M08 の4シナリオによる。シナリオ部分の内訳は、
`normal` 1秒、`error-500-then-200` 1秒、`ratelimit-429` 6秒、`slow-5000` 1秒、合計9秒である。
残りは、4シナリオ用の起動と停止である。

どの上限も実測に対して十分な余裕があるため、初回の実測では上限を変えていない。

R01 の初回の CI（PR #38、`ubuntu-24.04`、2026-11-08）の実測は次のとおりである。時間は、ログの各 step の開始時刻の差から求めた概算である。

| ステップ | 実測 | 上限 |
| --- | ---: | ---: |
| `jdx/mise-action`（mise と shellcheck の導入） | 約10秒 | 上限なし |
| `shellcheck` | 約9秒 | 3分 |
| `unit` | 約80秒 | 3分 |
| `smoke` | 約77秒 | 8分 |
| `contract` | 約33秒 | 5分 |
| ジョブ全体 | 3分26秒 | 15分 |

どの上限も実測の半分を下回っているため、上限は変えていない。`unit` は、S26 の初回（22秒、29秒）より長い。差の原因は未確認である。上限の3分には余裕があるが、次の CI の実測が上限の半分（90秒）を超えたら、原因を調べる。
上限は、待ち上限で止まる失敗を、ジョブの上限より先にステップの上限で見つけるための値である。
実測が上限の半分を超えたら、原因を調べてから上限を見直す。

ローカルの実測は参考であり、CI の値ではない（ローカル実測、Linux aarch64 の EC2）。

| 検査 | 実測（参考） |
| --- | --- |
| 品質ゲート（`sh scripts/quality-gate.sh`） | 約450秒（shellcheck の追加前の値。最新の実測は下の表） |
| M07 の smoke | 約150秒 |
| M08 の smoke | 約70秒 |
| `test:ci` の4シナリオ | 約26秒 |

## 再現性

| 要因 | 内容 |
| --- | --- |
| イメージの版 | MiniStack は `1.5.37`、WireMock は `3.13.1`、alpine は `3.20` に固定する |
| Squid のイメージ | `ubuntu/squid:latest` を基底にする。`latest` のため、取得の時期で中身が変わりうる。実行ごとに、基底のダイジェストを収集物の `env.txt` に記録する。ゲート時点のダイジェストは `gate-results.md` にもある |
| ポートの空き | 8080 と 4566 はホストで使う。3128 は pause の中だけで使う。他のプロセスが使っていると起動が止まる |
| 並列実行 | 名前とポートが固定のため、同じホストで2つ同時に実行しない。入口のロックで排他する（前節） |
| 実行環境 | Colima（ローカル）と Linux（CI）で結果が変わりうる。G1 と G3 の一部は CI で再確認する |

## 本番向けの検査

本番向けの完成版は、上流に `direct` だけを指定して作る。
`mock` の宛先と、`SQUID_MOCK_` で始まる設定を含めてはならない。
次のコマンドで、完成版がこの条件を満たすかを検査する。

```sh
sh scripts/e2e.sh check-production .e2e/taskdef.json
```

検査は、不合格の項目の名前だけを表示する。値は表示しない。

この基盤は、本番へのデプロイを行わない。
完成版を本番に登録する工程は、この基盤の対象外である。その工程の責任者が、`check-production` の合格を確かめてから登録する。

## ゲートの結果

M09 の前提ゲート（G1 から G5）の結果を要約する。詳細と観測値は [前提ゲートの記録](../specs/M09-execution-and-ci/gate-results.md) にある。

| ゲート | 結果 | 決定 |
| --- | --- | --- |
| G4 完成版の生成 | 通過 | `python3` の標準ライブラリで実装する。`jq` は使わない |
| G5 Squid のエントリポイント | 通過 | 元のエントリポイントへ `exec` で引き渡す。引数は `-f /etc/squid/squid.conf -NYC` |
| G1 コンテナ名の解決 | 通過（一部は CI で再確認） | WireMock はコンテナ名で解決する。起動順は固定する |
| G3 pause 方式と送信元 ACL | 通過（一部は CI で再確認） | 期待どおりに動く。`squid.conf` は変更しない |
| G2 ソケットなしの MiniStack | 通過（一部は CI で再確認） | `1.5.37` に固定する。describe は完成版と一致した |

## shellcheck の導入と品質ゲート

品質ゲート（`sh scripts/quality-gate.sh`）とCIは、シェルスクリプトを shellcheck で検査する。
shellcheck の版は、mise で固定する。版を変えるときは、この節の手順を使う。

### 前提

- mise。ローカルの版は `2026.11.3` 以上が必要である（`mise.toml` の `min_version` は下限で、固定ではない）。CI だけが `version: 2026.11.3` で固定する。
- Node.js 22 以上と Docker は、従来どおり必要である。
- mise の導入は、公式の配布元から取得した実体と `SHASUMS256.txt` を `sha256sum -c` で照合してから、PATH の通る場所へ置く。
  パイプでシェルへつなぐ導入はしない。
- macOS では Homebrew の `brew install mise` を候補にする。この経路は未確認である（後の「未確認の項目」を参照）。

### 導入と版の固定

shellcheck の版は、リポジトリの2つのファイルで決まる。

| ファイル | 内容 |
| --- | --- |
| `mise.toml` | `min_version = "2026.11.3"` と、`[tools]` の `shellcheck = "0.11.0"` |
| `mise.lock` | shellcheck の4つの環境（linux-x64、linux-arm64、macos-x64、macos-arm64）の取得先の URL と SHA256 |

導入は次の1行で行う。`--locked` は `mise.lock` に従うことを意味し、記録のない版や取得物は入らない。

```sh
mise install --locked
```

`.shellcheckrc` は次の4項目だけを持つ。`disable=` は書かない。

```text
shell=sh
severity=style
external-sources=true
source-path=SCRIPTDIR
```

### 品質ゲートでの shellcheck

品質ゲートは、PATH 上の shellcheck を使わない。`mise which shellcheck` が返す実体を使う。
自動の導入は止める。次の3つの環境変数は、mise を呼ぶ行にだけ付ける。

- `MISE_EXEC_AUTO_INSTALL=false`
- `MISE_AUTO_INSTALL=false`
- `MISE_LOCKED=1`

ゲートは次の順に確かめる。どれかが合わない場合は `FAILED:` と導入手順を出して止まる。

1. `mise` が無い。
2. `mise current shellcheck` で期待する版が得られない。
3. `mise which shellcheck` で実体が得られない（未導入）。
4. `--version` の結果が期待する版と違う（版違い）。

失敗したときは、`mise install --locked` を実行してから、ゲートを再実行する。
検査の対象は `git ls-files` の `*.sh` である。対象が0件のときは成功にしない。

### CI の step

CI は、`unit` より前に次の2つの step を置く（ワークフロー `.github/workflows/e2e-test.yml`）。

- `jdx/mise-action`（タグ v5.2.7 のコミット SHA。先頭は `b44d12e` で、全体は `.github/workflows/e2e-test.yml` の `uses` 行にある）
  - `version: 2026.11.3`
  - `sha256` の値は文書に載せない。
    値は `.github/workflows/e2e-test.yml` の `sha256` と、
    `specs/R01-shellcheck/verification/phase-1-results.md` の2章を参照する。
  - `cache: false`、`env: false`
  - `install_args: --locked shellcheck`
- `shellcheck` step: `timeout-minutes: 3`。`mise which` の実体で、`git ls-files -z '*.sh'` の一覧を検査する。

`unit` の前に置くのは、検査が落ちたときに Docker を動かさないためである。

CI は `ubuntu-24.04`（x86_64）だけを前提とする。
`sha256` は linux-x64 の取得物の値である。
`sha256` は1つの値だけを受け付けるため、値を足さない。
別の環境（arm64 やほかの OS）で CI を回すときは、その環境の step を分けるか、`matrix` で環境ごとに値を切り替える。
その場合、`sha256` の値は、その環境の取得物の値に合わせる。
値が合わない場合、取得は検証で止まる。これは安全側の失敗である。

### mise.lock の再生成

shellcheck の版を上げるときは、次の手順で `mise.lock` を作り直す。

1. `mise.toml` の `shellcheck` の版を、完全な版（例: `0.11.0`）で書き換える。
2. 次のコマンドで、4つの環境の取得先と SHA256 を作り直す。

   ```sh
   mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64
   ```

3. 差分が、shellcheck の4つの環境の URL と SHA256 だけであることを確かめる。
4. 4つの SHA256 を、公式の GitHub リリースの資産の SHA256（API の `digest`）と照合し、結果を記録する。
5. `mise install --locked` を実行し、品質ゲートを実行する。指摘が増えるときは、後の「修正と除外の件数」の手順で先に解消する。

mise 本体の版を上げるときは、`min_version`、CI の `version`、`sha256` を同時に更新する。
`sha256` は、公式の `SHASUMS256.txt` から取る。
`sha256` の値も、`e2e-test.yml` の値と一緒に更新する。
`mise.toml` と `mise.lock` の差分は、コードと同じ重さでレビューする。

### 設定の自動信頼の限界

`jdx/mise-action` は、作業ディレクトリの mise の設定を自動で信頼する。
PR を作った人が `mise.toml` を書き換えると、CI はその内容を実行する。
`mise.toml` は、`[tasks]`、`[hooks]`、`[env]`、テンプレート関数で任意のコマンドを動かせるためである。

守りは次の3つである。

- `mise.toml` は、`min_version` と `[tools]` の `shellcheck` の1項目だけに保つ。
- PR で `[env]`、`[tasks]`、`[hooks]` を足すと、レビューで止める。
- CI の権限は `contents: read` だけで、利用者のシークレットは渡さない。`persist-credentials: false` を付ける。
  ただし、`jdx/mise-action` の `github_token` の入力は、既定で `${{ github.token }}`（GitHub の自動トークン）である。
  このため、PR の `mise.toml` のコードからは、読み取り専用で短命のトークンが見える。
  このトークンは、`persist_github_token` が既定の `false` の間は、この action の中だけで使われる。

`env: false` と `cache: false` は、取得物と環境変数の経路を減らすための設定である。
設定の信頼の問題は解消しない。`pull_request` はフォークからの PR でも同じ経路で動く。
この守りは、Secrets を使わず、読み取りだけの権限であることが前提である。
次の3つも守る。

- `pull_request_target` へ変えない。
- `permissions` を広げない。
- 差分を確かめるまで `mise trust` を実行しない。

mise 本体の照合は、同じリリースの `SHASUMS256.txt` だけに頼らない。
4 環境の値は `specs/R01-shellcheck/verification/phase-1-results.md` の 2 章に、
導入と失敗の確認の結果は 3 章に記録している。

### 修正と除外の件数

件数は、設定の有無で2つの基準を分けて書く。

| 基準 | m09 以外 | `tests/m09-execution-and-ci.sh` | 合計 |
| --- | ---: | ---: | ---: |
| 設定なし（`.shellcheckrc` が無い状態） | 44 | 112 | 156 |
| 最終の設定（`external-sources=true`、`source-path=SCRIPTDIR`） | 43 | 112 | 155 |

最終の設定では、`test-client/entrypoint.sh` の SC1091 が消える。このため、m09 以外は44件から43件になる。
m09 の112件は、設定が変わっても変わらない。

解消の内訳は、修正と除外に分けて書く。個々の行は書かない。

| 対象 | 修正 | 除外 | 除外の理由（コードごと） |
| --- | ---: | ---: | --- |
| m09 以外（43件） | 6 | 37 | SC2034、SC2329、SC2031、SC2030、SC2086 は、別のファイルや子のシェルが使う変数と関数、サブシェルの隔離が意図の箇所。SC1090 は `source=` の宣言と、自己参照の箇所の理由付き除外。SC2016 は子の `sh` が展開する意図。SC2154 は `trap` の文字列の中で代入する変数の誤検出 |
| m09（112件） | 1 | 111 | SC2016（39件）は、偽のコマンド本文や子のシェルの文字列。SC1090（23件）は `# shellcheck source=/dev/null` と理由。SC2031、SC2030 はサブシェルの隔離が意図。SC2329（9件）は `scripts/e2e-lib.sh` から呼ばれる関数。SC2012、SC2015 は、それぞれ1件ずつ理由を書いた。SC2086 の1件だけは修正した |
| 合計 | 7 | 148 | 設定なしの156件から、SC1091の1件が設定で消え、155件になる |

除外は指令の行で管理する。`disable` と `source=` の両方を `git grep -n 'shellcheck '` で見る。
1つの指令が複数の指摘を覆うため、指令の行数と指摘の件数は一致しない。
件数は `phase-2-results.md` と `phase-3-results.md` の表が正である。

### 実行時間

| 検査 | 実測 | 出所 |
| --- | --- | --- |
| 品質ゲート（`sh scripts/quality-gate.sh`） | 527秒 | フェーズ4の実測。shellcheck を追加した後の値 |
| shellcheck（20ファイル、ローカル） | 約74秒（m09 が約53秒、残り19ファイルが約22秒） | 計画時のメインの実測（Linux aarch64、2コア） |
| CI の `shellcheck` step | 約9秒（上限3分） | 初回 CI の実測（PR #38、`ubuntu-24.04`、2026-11-08） |

CI の上限（`shellcheck` step の3分）は、CI の実測の約9秒に対して十分な余裕がある。上限は変えていない。
初回 CI の実測が上限の半分を超えたら、原因を調べてから上限を見直す。

### 版違いの確認（未確認）

次の項目は、この環境では未確認である。利用者の端末で確かめる。

| 項目 | 状態 |
| --- | --- |
| 版違いの失敗（期待と違う版を入れた状態で、ゲートが `FAILED:` で止まる） | 未確認。利用者の端末で確かめる |
| macOS での mise の導入（Homebrew）と `mise install --locked` | 未確認。利用者の端末で確かめ、結果をこの節に書く |
| `mise-action` の `install_args` が `--locked` を重複させないこと | 初回 CI の前にソースで確かめた。結果は検証の記録にある |
