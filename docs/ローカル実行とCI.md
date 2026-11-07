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

旧基盤は `docker-compose.yml` である。現行の手順ではない。
ファイルの削除は、Compose 削除の作業（T2630）と同時に行う。

- 新基盤と旧基盤を同時に起動しない。どちらも 8080 のポートを使い、起動が止まる。
- M08 の4シナリオは、新基盤の `sh tests/m08-e2e-suite.sh smoke` と `sh scripts/e2e.sh test:ci <シナリオ名...>` で実行する。

## CIの見方

ワークフローは `.github/workflows/e2e-test.yml` にある。

- トリガーは、pull request（全ブランチ）と、`main` への push である。
- ジョブは `ubuntu-24.04` で動き、上限は15分である。
- 権限は `contents: read` だけである。

ステップは次の順に動く。

| 順序 | ステップ | 内容 | 上限 |
| --- | --- | --- | --- |
| 1 | `unit` | `sh tests/m09-execution-and-ci.sh unit` | 3分 |
| 2 | `test-ci` | `npm run test:ci` の後に、M08 の4シナリオを `sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000` で実行する | 10分 |
| 3 | `smoke` | `sh tests/m09-execution-and-ci.sh smoke` | 8分（仮値） |
| 4 | `contract` | `sh tests/m09-execution-and-ci.sh contract` | 5分（仮値） |
| 5 | `collect` | `sh scripts/e2e.sh collect`。失敗しても必ず実行する | - |
| 6 | アップロード | `e2e-logs/` を保存する。失敗時だけ実行する | - |
| 7 | `stop` | `npm run stop`。必ず実行する | - |

失敗したときは、実行結果のページの Artifacts から `e2e-logs-<実行ID>-<試行回数>` をダウンロードする。
保存期間は7日である。

収集ログは、保存の前に識別情報（ARN と12桁の数字）をマスクする。
マスクしても残るファイルは削除し、ファイル名だけを `scrub.txt` に記録する。
ログを共有する前に、`scrub.txt` と中身を確かめる。

## 所要時間の目安

CI の値は、CI の初回実行で実測する。ここには、まだ書かない。
上の表の上限は、実測の前に置いた仮の値である。実測の結果で見直す。
ジョブの上限は15分である。`test:ci` の上限は10分である。

ローカルの実測は参考であり、CI の値ではない（ローカル実測、Linux aarch64 の EC2）。

| 検査 | 実測（参考） |
| --- | --- |
| 品質ゲート（`sh scripts/quality-gate.sh`） | 約445秒 |
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
