# S14 開発Composeの公開ポート制限の仕様

## 1. 目的

開発用`docker-compose.yml`が、SquidとWireMockのポートを全インターフェースへ公開している状態を解消する。
共有ホストや外部から到達できる開発環境で、第三者がプロキシやWireMock管理APIへ接続できないようにする。

要件の出典はIssue #14とする。この指摘はM04のセキュリティレビューで見つかったもので、M01とM02から引き継いだ
状態である。M04の変更が原因ではないため、M04とは別のSpecとして扱う。

## 2. 現状（リポジトリの確認結果）

| 対象 | 現状 |
| --- | --- |
| `docker-compose.yml`のsquid | `ports: - "3128:3128"`。ホストのIPを指定しておらず、全インターフェースへ公開される |
| `docker-compose.yml`のwiremock | `ports: - "8080:8080"`。同じく全インターフェースへ公開される。`/__admin`配下の管理APIも同じポートで到達できる |
| `docker-compose.yml`のtest-client | `ports`なし。`HTTP_PROXY`は`http://squid:3128`で、Composeネットワーク`sidecar`の内側から接続する |
| `squid-config/squid.conf` | `http_port 3128`。`acl all src all`を宣言するが、`http_access`は宛先ドメインだけで判定する |
| `squid-config/whitelist.txt` | `api.example.com`と`api-staging.example.com`の2件 |
| `tests/m02-routing-smoke.sh`ほか | 既定で`http://127.0.0.1:8080`と`http://127.0.0.1:3128`のホスト公開ポートへ接続する |
| `docs/シナリオ隔離.md` | Composeがポート3128と8080を固定で公開すると記載している |
| `README.md` | Squidは`localhost:3128`、WireMockは`localhost:8080`と記載している。トラブルシューティングは`docs/troubleshooting.md`を参照とするが、そのファイルは存在しない |

Squidの`http_access allow api_domains`は送信元を見ない。許可ドメインの宛先なら、どの送信元からでも
転送される。WireMockの管理APIは認証を持たない。

## 3. 対象範囲

- `docker-compose.yml`のホスト公開ポート（Squidの3128、WireMockの8080）の公開範囲
- WireMock管理APIの公開範囲
- Squidの送信元アクセス制御（`squid-config/squid.conf`の送信元ACL）
- ローカル開発手順（`README.md`、`docs/ポート公開範囲.md`）とトラブルシューティング
- M02の閉域ルーティングsmoke test（`tests/m02-routing-smoke.sh`）と、公開範囲を検査するsmoke test（`tests/s14-compose-port-binding.sh`）
- M01からM04の通信契約への影響の記録
- 変更対象に対応するセキュリティレビューと品質ゲート（`scripts/quality-gate.sh`）の実施

## 4. 機能要件

| ID | 要件 |
| --- | --- |
| FR-001 | `docker-compose.yml`のSquidのホスト公開を`127.0.0.1:3128:3128`の形式で、ホストのループバックだけに限定する。ホストIPは固定し、環境変数での切り替えと`::1`の公開は採用しない（Q-001） |
| FR-002 | `docker-compose.yml`のWireMockのホスト公開を`127.0.0.1:8080:8080`の形式で、ホストのループバックだけに限定する。環境変数での切り替えと`::1`の公開は採用しない（Q-001） |
| FR-003 | WireMock管理API（`/__admin`配下）が、ホストの外部ネットワークから到達できない。ホストのループバック以外のアドレスへ接続すると失敗することを、検査で確かめる。検査は`docker-compose config`の静的検査と`docker-compose ps`の確認を必須とし、非ループバックIPv4アドレスへの実接続の拒否確認は環境に応じて行う（Q-005） |
| FR-004 | 許可ネットワークは採用しない。採用しない理由を`docs/ポート公開範囲.md`に記録し、別マシンや別コンテナから使う場合の代替（SSHポートフォワードなど利用者側の手段）を案内する（Q-002） |
| FR-005 | `squid-config/squid.conf`に送信元ACL`acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`を加え、`http_access allow api_domains`を`http_access allow local_src api_domains`へ置き換える。許可範囲はループバックとRFC1918の3範囲とし、範囲外の送信元からの要求が拒否されることを確かめる。`http_access deny all`、`cache deny all`、`cache_peer`の各行は変えない（Q-003） |
| FR-006 | Test ClientからSquidへの通信（`http://squid:3128`）と、SquidからWireMockへの転送（`cache_peer wiremock parent 8080`）は、Composeネットワーク内で完結しているため、ホスト公開の変更後も成功する |
| FR-007 | M02の閉域ルーティングsmoke test（`tests/m02-routing-smoke.sh`）が、変更後も成功する。許可ドメインの要求がWireMockに届き、許可外ドメインが拒否されることを含む |
| FR-008 | 公開範囲を確かめる検査を追加する。`docker-compose config`の出力で、SquidとWireMockの公開ポートにホストIPが付いていることを静的に確かめる（Docker不要の`unit`相当）。起動後は、`docker-compose ps`の公開ポート表示が`127.0.0.1:3128->3128/tcp`と`127.0.0.1:8080->8080/tcp`であり、`0.0.0.0`と`::`を含まないことを確かめる。ホストの非ループバックIPv4アドレスを取得できる場合は、そのアドレスの3128番と8080番への接続が失敗することも確かめる。取得できない場合は理由を出力してスキップし、失敗にしない。検査の入口は`tests/s14-compose-port-binding.sh`（`static`と`live`の2モード）とする。`squid -k parse`の出力はWARNINGを失敗にせず、ERRORとFATALを失敗にする（Q-005、Q-006、Q-008） |
| FR-009 | 既存のM01からM04の通信契約への影響を、記録として残す。M01のポート契約（旧FR-003、公開ポートは3128と8080）、M02のルーティング契約、M03のマッピング契約、M04のTest Client通信契約ごとに、影響の有無と根拠を表にする |
| FR-010 | 開発手順を更新する。`README.md`のSystem Componentsと`docs/`に、ホストからの接続先が`127.0.0.1`だけであること、他のホストや別マシンのコンテナからは接続できないことを書く。`README.md`のSystem Componentsにある`localhost:3128`と`localhost:8080`を`127.0.0.1:3128`と`127.0.0.1:8080`へ直し、新規文書`docs/ポート公開範囲.md`へリンクする。ECSモデルを説明する`localhost`の記述は変えない。`docs/シナリオ隔離.md`の固定公開の記述には、公開先が`127.0.0.1`であることを足す（Q-004、Q-007） |
| FR-011 | トラブルシューティングを更新する。公開範囲の制限が原因で起きる症状（別マシンや別コンテナからの接続拒否、`localhost`が`::1`へ解決される場合の接続失敗、`default-address-pools`でRFC1918外のサブネットを使う環境での拒否など）と対処を書く。書き込み先は新規文書`docs/ポート公開範囲.md`の「症状と対処」の節とする。`docs/troubleshooting.md`は作らず、M10へ統合の引き継ぎ項目として記録する（Q-004） |
| FR-012 | 変更対象に対応するセキュリティレビューを実施し、結果を記録する。確認項目は、公開範囲、管理APIの到達性、Squidの送信元制御、文書やログへの識別情報の混入とする |
| FR-013 | コミット前に、`scripts/quality-gate.sh`をすべて成功させる。`tests/s14-compose-port-binding.sh`を、同スクリプトのCompose関連の`for test in ...`の一覧の末尾に登録する（Q-006）。M01からM07の既存検査が引き続き通ることを含む。M02の検査は変更しない |

## 5. 非機能要件

| ID | 要件 |
| --- | --- |
| NFR-001 | M04のTest Client通信契約を変えない。Test Clientのコードと環境変数（`HTTP_PROXY`、`HTTPS_PROXY`、`NO_PROXY`、`TEST_API_BASE_URL`）を変更しない |
| NFR-002 | サービス名（`test-client`、`squid`、`wiremock`）、コンテナ内のポート（3128、8080）、ネットワーク名（`sidecar`）、マウント（`:ro`を含む）を変えない |
| NFR-003 | `squid-config/whitelist.txt`の許可ドメインと、`cache deny all`などM07までのSquid設定の意図を変えない |
| NFR-004 | 本番ECSのSecurity GroupやIAM設計に変更を持ち込まない。HTTPSのSSL Bumpを導入しない |
| NFR-005 | 検査と文書の追加で、新しい実行時依存を足さない。既存のシェルスクリプトの方式（POSIX sh、`trap`による後始末）に合わせる |
| NFR-006 | 文書、ログ、検査出力に、AWSアカウントID、ARN、認証情報、実在のホスト名やIPアドレスを含めない。例にはダミー値（`api.example.com`、`<ACCOUNT_ID>`など）を使う |
| NFR-007 | 変更後の検査を連続で2回実行しても、同じ結果になる |
| NFR-008 | 文書はmarkdownlint（`.markdownlint.json`）に通る形式で書く |

## 6. 契約への影響の見込み

実際の記録はFR-009で作る。現時点の見込みは次のとおり。見込みはplan以降の実機確認で確定する。

| 契約 | 影響の見込み |
| --- | --- |
| M01 公開ポート | 公開ポート番号（3128、8080）は変わらない。公開先がループバックへ狭まる。M01の「公開ポートは3128と8080」という記述との整合を確認する |
| M02 ルーティング | Squid、WireMock間の転送はComposeネットワーク内で完結する。ホストからの接続先が`127.0.0.1`であれば、smoke testの既定値のまま通る見込み |
| M03 マッピング | 変更なし。ただしM03の検査は`http://127.0.0.1:8080`の管理APIを使うため、ループバック公開でも到達できることを確かめる |
| M04 Test Client | 変更なし。Test Clientは`squid:3128`へネットワーク内で接続し、ホスト公開に依存しない |
| M05からM07 | 検査が既定で`127.0.0.1`を使うため影響しない見込み。環境変数`WIREMOCK_URL`、`PROXY_URL`で`localhost`以外を指定する利用者がいないかを確かめる |

## 7. 対象外

- M04のTest Client通信契約の変更
- 本番ECSのSecurity GroupやIAM設計
- HTTPSのSSL Bump
- WireMock管理APIへの認証の追加（ネットワーク到達性の制限で対処する。認証が必要になった場合は別Issueで扱う）
- ホストのファイアウォール設定や、Docker Desktop、Colimaの設定の変更
- 許可ドメインの追加や、`whitelist.txt`の変更

## 8. 完了条件

- [ ] SquidとWireMockのホスト公開が`127.0.0.1:3128`と`127.0.0.1:8080`へ限定されている。許可ネットワークを採用しない理由が`docs/ポート公開範囲.md`に記録されている
- [ ] WireMock管理APIが、ループバック以外のアドレスから到達できないことを検査で確認している
- [ ] Squidの送信元ACL（`127.0.0.0/8`とRFC1918の3範囲）が入り、範囲外の要求の拒否が確認され、根拠が記録されている
- [ ] M02の閉域ルーティングsmoke testが成功する
- [ ] `tests/s14-compose-port-binding.sh`が追加され、`scripts/quality-gate.sh`に登録されている
- [ ] M01からM04の通信契約への影響が、契約ごとに記録されている
- [ ] 開発手順（`README.md`、`docs/ポート公開範囲.md`、`docs/シナリオ隔離.md`）が更新されている
- [ ] `docs/ポート公開範囲.md`の「症状と対処」が書かれ、M10への引き継ぎが記録されている
- [ ] セキュリティレビューの結果が記録され、重大な指摘が残っていない
- [ ] `scripts/quality-gate.sh`が、コミット前にすべて成功している
- [ ] 文書、ログ、検査出力に識別情報が含まれていない

## 9. 未確認事項

Q-001からQ-008は`clarify.md`で解消した。決定の根拠と却下した案は`clarify.md`を参照する。

| ID | 状態 | 内容 |
| --- | --- | --- |
| Q-001 | 解消済み | 公開をループバックに限定する方法。`127.0.0.1:3128:3128`のようにホストIPを固定するか、環境変数（例: `BIND_ADDRESS`、既定は`127.0.0.1`）で切り替えられるようにするか。IPv6の`::1`を許可するか。また、Colimaなど仮想マシン経由のDocker環境で、ホストの`127.0.0.1`への公開が期待どおりに働くかを実機で確認する 決定: ホストIPを`127.0.0.1`に固定する。環境変数での切り替えと`::1`は採用しない。 |
| Q-002 | 解消済み | 許可ネットワークを採用するか。採用する場合、アドレス範囲の指定方法（環境変数、Composeのオーバーライドファイル）と、検査方法を決める。採用しない場合は、FR-004を「採用しない理由の記録」に縮める 決定: 許可ネットワークは採用しない。FR-004は採用しない理由の記録とする。 |
| Q-003 | 解消済み | Squidの`http_access`に送信元の条件を足すか。足す場合、許可するのはComposeネットワーク`sidecar`のサブネットだけか、ホストからDockerのゲートウェイ経由で来る接続も含めるか。サブネットはDockerが動的に割り当てるため、固定の範囲を書けない場合の代替案も決める 決定: 送信元ACLを足す。許可範囲は`127.0.0.0/8`とRFC1918の3範囲とする。 |
| Q-004 | 解消済み | トラブルシューティングの書き込み先。`README.md`が参照する`docs/troubleshooting.md`は存在せず、M10（セットアップとトラブルシューティング文書）が扱う予定である。S14で新規作成するか、`docs/シナリオ隔離.md`のような既存文書に節を足すか、M10へ引き継ぐ項目として記録するか 決定: 新規文書`docs/ポート公開範囲.md`に書く。`docs/troubleshooting.md`はM10へ引き継ぐ。 |
| Q-005 | 解消済み | 「外部ネットワークから到達できない」ことの検査方法。ホストの非ループバックアドレス（`ifconfig`などで得られるLANアドレス）への接続拒否を使うと、実行環境によってアドレスが変わる。検査が環境に依存しない形（`docker-compose config`の静的検査、`docker port`や`docker inspect`の結果による確認）で足りるか、実接続の検査を加えるか 決定: 静的検査と`docker-compose ps`の確認を必須にし、実接続の拒否確認は環境に応じて行う。 |
| Q-006 | 解消済み | 公開範囲の検査を、既存の`tests/m02-routing-smoke.sh`へ足すか、`tests/s14-compose-port-binding.sh`のような新しい検査入口に分けるか。品質ゲートへの登録位置も決める 決定: 新規入口`tests/s14-compose-port-binding.sh`を作り、品質ゲートの一覧へ登録する。 |
| Q-007 | 解消済み | `README.md`の`localhost:3128`と`localhost:8080`の表記を`127.0.0.1`へ直すか。`localhost`が`::1`に解決される環境で、ループバック公開が`127.0.0.1`だけの場合に接続が失敗しうるため、表記を揃えるかを決める 決定: `README.md`のSystem Componentsだけ`127.0.0.1`へ直す。ECSモデルの`localhost`は残す。 |
| Q-008 | 解消済み | `ubuntu/squid:latest`のイメージで、Squidが`acl all src all`を宣言する設定が既定のACLと衝突しないかを実機で確認する。送信元ACLの追加が既存の`squid -k parse`の検査を通ることも確かめる 決定: `acl all src all`は変更しない。`squid -k parse`のWARNINGは失敗にせず、ERRORとFATALを失敗にする。 |

Q-002は利用者が承認した既定（許可ネットワークを採用しない）で進める（2026-11-03）。
