# M09 analyze結果

## 0. 結果の要約

| 項目 | 内容 |
| --- | --- |
| 判定 | 条件付き PASS |
| Critical | 0件 |
| High | 3件（A-01、A-02、A-03） |
| Medium | 10件（A-04からA-13） |
| Low | 11件（A-14からA-24） |
| implementをブロックするか | A-01からA-03は反映するまでブロックする。A-04からA-13は同時に反映する。Lowはブロックしない |

対象は`spec.md`、`clarify.md`、`plan.md`、`tasks.md`。文書は変更していない。
形式は`specs/M08-e2e-suite/analyze.md`と`specs/S14-compose-port-binding/analyze.md`にそろえた。
Dockerは起動していない。既存実装の参照は、`docker-compose.yml`、`squid-config/`、`tests/*.sh`、
`scripts/quality-gate.sh`、`AGENTS.md`、`.github/`、`.dockerignore`を読んで確かめた。

## 1. 要件カバレッジ

`spec.md`のFR-901からFR-921（21件）、NFR-901からNFR-911（11件）を、
`plan.md` 8.1の対応表と`tasks.md` 4章の対応表に突き合わせた。

| 要件 | plan（8.1） | tasks（4章） | 判定 |
| --- | --- | --- | --- |
| FR-901 入口 | U2、U8 | T907、T913 | PASS |
| FR-902 テンプレート | U1、U3、U7 | T905、T906、T908、T912 | PASS |
| FR-903 完成版の生成 | U3、U8 | T908、T913 | PASS |
| FR-904 MiniStack契約 | U1、U6 | T905、T906、T911 | PASS |
| FR-905 ダミー認証情報 | U2、U6 | T907、T911 | PASS（A-16） |
| FR-906 pause方式 | U1、U7、U9 | T904、T912、T914 | PASS |
| FR-907 通信検証3項目 | U9 | T904、T914 | 条件付き（A-11） |
| FR-908 上流の切り替え | U5、U9 | T910、T914 | PASS |
| FR-909 本番向けの検査 | U4、U5、U9 | T909、T910、T914 | PASS |
| FR-910 別タスクのWireMock | U1、U7、U9 | T903、T906、T912、T914 | PASS |
| FR-911 stopとclean | U7、U8、U9 | T912、T913、T914 | 条件付き（A-02） |
| FR-912 前提検査 | U2、U8、U9 | T907、T913、T914 | 条件付き（A-02） |
| FR-913 トリガー | U10 | T915 | 条件付き（A-07） |
| FR-914 ジョブの手順 | U10 | T915 | PASS |
| FR-915 失敗時も後処理 | U8、U10 | T913、T915 | 条件付き（A-03） |
| FR-916 アーティファクト | U8、U10 | T913、T915 | PASS |
| FR-917 タイムアウト | U10、U14 | T915、T924 | PASS |
| FR-918 識別情報の検査 | U6、U8、U10 | T911、T913、T915 | 条件付き（A-06） |
| FR-919 文書 | U11、U14 | T916、T924 | PASS |
| FR-920 composeを呼ばない | U2、U8、U13 | T907、T913、T918 | 条件付き（A-09） |
| FR-921 collect | U8 | T913 | PASS |
| NFR-901 閉域 | U6、U10、U13 | T911、T915、T918 | PASS（A-23） |
| NFR-902 認証情報 | U2、U6、U10 | T907、T911、T915 | 条件付き（A-01） |
| NFR-903 検証内容の不変 | U7、U9、U13 | T912、T914、T918 | PASS |
| NFR-904 実行時間 | U10、U12、U14 | T915、T917、T924 | PASS |
| NFR-905 再現性 | U3、U8、U11 | T908、T913、T916 | 条件付き（A-08） |
| NFR-906 ソケットを渡さない | U6、U7、U9 | T911、T912、T914 | PASS |
| NFR-907 ループバックのみ | U7、U9 | T912、T914 | PASS |
| NFR-908 冪等性 | U8、U9 | T913、T914 | 条件付き（A-02） |
| NFR-909 イメージの固定 | U1、U2、U3 | T902、T905、T907、T908 | 条件付き（A-05） |
| NFR-910 並列実行 | U10 | T915 | 条件付き（A-07） |
| NFR-911 POSIX shと標準アクション | U1、U3、U10、U13 | T901、T908、T915、T918 | PASS |

### 1.1 網羅の突き合わせ

- FR 21件とNFR 11件は、planの8.1とtasksの4章の両方で、1つ以上の単位とタスクに対応する。欠けはない。
- 8.1の単位とtasks 4章のタスクは、U1がT901からT906、U2からU13がT907からT918、U14がT924で一致する。
  32件すべてで、対応先のU/Tが実在し、内容も一致した。
- plan 8章の単位ごとの「要件」列と8.1は一致する。tasksの各タスクの「要件」欄と4章は、次の差だけがある（A-15）。
  T902はFR-908、T905はFR-905とNFR-906を持つが、4章ではそれぞれT910、T914、T907とT911、T911からT914に載る。
  どれも4章に他の対応先があり、欠けにはならない。
- plan 4章のG1からG5は、tasksのT903、T905、T904、T901、T902に1対1で対応する。
- plan 4.1の19行の分類は、前提ゲート7、実装中8、CI初回4（2と3は重複）で合計が合う。clarifyの表の行数も19行。
- `spec.md` 7章の完了条件は、T918とtasks 5章で突き合わされる。

## 2. 番号・名前・値の一貫性

4文書で次を突き合わせた。

| 項目 | 結果 |
| --- | --- |
| 接頭辞`swsc-`、ラベル`swsc.managed=true`、`swsc-net`、`swsc-wiremock`、`swsc-ministack`、`swsc-pause`、`swsc-squid` | 一致 |
| `.e2e/`、`e2e-logs/`、`gate-results.md`（planとtasksのみ） | 一致。specは`gate-results.md`を持たないが矛盾ではない |
| `scripts/e2e.sh`、`scripts/e2e-*`、`ecs/squid/`、`ecs/task-definition.template.json` | spec、clarifyは`scripts/e2e.sh`まで。plan、tasksは詳細まで一致 |
| 環境変数`SQUID_UPSTREAM`、`SQUID_MOCK_HOST`、`SQUID_MOCK_PORT` | 一致。ポートの範囲は、specが数字だけ、planが1から65535 |
| ポート3128、4566、8080、`127.0.0.1`公開 | 一致 |
| タイムアウト15分、10分、120秒 | 一致。planとtasksにunitステップの3分が加わる（spec未記載。矛盾ではない） |
| コマンド名`unit`、`smoke`、`collect`、`check-production`、`test:ci`、`--profile production` | 一致 |
| アーティファクト名`e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}`、`retention-days: 7` | 一致 |
| イメージの固定（MiniStackはタグ固定、`alpine:3.20`、`wiremock/wiremock:3.13.1`、`ubuntu/squid:latest`据え置き） | 一致 |
| 終了コード（check-productionは0、1、2。130、143） | 一致 |
| ラベルの値、ダミー認証情報の値（`test`）、リージョン（`ap-northeast-1`） | 一致 |

食い違いは次のとおり。

| 項目 | 一方の記述 | もう一方の記述 |
| --- | --- | --- |
| 識別情報の検査と処理 | spec FR-918は該当ファイルを削除して失敗を記録する | plan 3.7はマスクして再検査し、残ったものだけ削除する（A-06） |
| G3のCI確認 | plan 4.3は一時ブランチの最小workflowで確認する | tasks T904は一時ブランチもworkflowも作らない（A-04） |
| clarify Q-904の手順表 | unitステップがない | spec FR-914とplan 3.9はある（A-14） |
| clarifyの`python3`（またはjq） | 「または」が残る | spec 12章の4、NFR-911は`python3`に確定（A-14） |
| clarify Q-917の`cache_peer_access`の置換 | 行のホスト名を置換する | plan 3.4は`name=wiremock`で2行を書き換えない（A-14） |

## 3. ゲートG1からG5の確認

| 確認項目 | 結果 |
| --- | --- |
| 実行順 | plan 4.2（G4、G5、G1、G3、G2）、plan U1、tasks 1.3、T901からT905の依存が一致する |
| 分岐 | G1からG5の分岐表がplan 4.3とtasksで一致する。G3の「CIでは失敗」だけ扱いが違う（A-04） |
| 記録先 | `gate-results.md`の1か所。5つの節（環境、手順、観測、分岐の決定、後続への影響）が両文書で一致する |
| T906の通過判定 | 条件1から4と「通過しない」の行が揃う。条件4の`.e2e/`の扱いに誤りがある（A-10） |
| ゲート前に着手できるタスク | T907はT906に依存し、`package.json`と`.gitignore`の下書きも禁止されている。ゲート前に着手できるタスクはない |
| G2が利用者の端末で行う前提 | T905は手順の提示で止まり、貼り付けを待つ。設計は矛盾しないが、サブエージェントでは待てない（A-05） |
| G2の候補タグ | 選び方が未定義（A-05） |
| G5の決定を書く先 | planの3.4手順4を直すと書くが、直すタスクがない（A-15） |

## 4. タスクの依存順と並列

- T901からT924の依存は、tasks 3章の表と各タスクの「依存」欄で一致する。循環はない。
- 欠けた依存はない。T917はT914とT916に依存し、T916がT915に依存するため、T915も間接的に含まれる。
- 並列可としたのはT916の文書本体とT914またはT915の組だけである。T914とT915は`tests/m09`を編集せず（T914）、
  編集する（T915）が、T916の文書本体が触る`docs/`、`README.md`、`AGENTS.md`とは重ならない。ファイルの重なりはない。
- 共有ファイルの表（tasks 1.4）には漏れがある。T909は`scripts/e2e.sh`を触るが、表の編集者に載っていない（A-15）。
- T914とT915の順序が決まっていない。どちらも`tests/m09`を編集するため、直列の順を明記する（A-20）。
- 受け入れ条件の多くは、`unit`の名前付きケースと`sh -n`、`py_compile`、`grep`で機械的に確かめられる。
  例外はA-01（`smoke`を誰が実行するか）とA-11（検証の中身が未定義）である。

## 5. 方針との整合

| 方針 | 結果 |
| --- | --- |
| docker-composeを呼ばない（FR-920） | 設計は整合。ただし検査の`grep`が`docker compose`（空白形式）を拾わない（A-09） |
| 既存検査（M02〜M08、S14）と`docker-compose.yml`を変えない | 整合。plan 2.3と14章、T918の差分確認が揃う |
| MiniStackにDockerソケットを渡さない、run-taskを使わない | 整合。plan 3.3、3.5、5.1「引数の安全」、T912が固定する |
| ダミー認証情報のみ、既定へフォールバックしない | 整合。`swsc_aws`が検査し、設定ファイルを`/dev/null`にする。`AWS_SESSION_TOKEN`は未検査（A-16） |
| リポジトリ内に`.aws/config`を作らない | 整合 |
| Secretsを使わない | 整合。planの`unit`が`secrets.`の不在を検査する |
| 入力値を`run:`へ直接展開しない | 整合。`github.run_id`と`run_attempt`はアーティファクト名にだけ使う |
| 本番にmockを残さない（FR-909） | 4層が両文書で一致する |

## 6. 既存実装の参照の確認

| 参照 | 結果 |
| --- | --- |
| `squid-config/squid.conf`の8行（`acl local_src`）、10行（`cache_peer`）、13行（`never_direct`）、15、16行（`http_access`）、23、24行（ログ） | 実在し、clarifyの行番号と一致 |
| `tests/s14-compose-port-binding.sh`の429から444行の固定行検査 | 実在。`grep -Fxq`で`local_src`、`http_access allow local_src api_domains`、`http_access deny all`、`cache deny all`を検査する |
| S14の識別情報の検査（`README.md`と`scripts/quality-gate.sh`が対象） | 実在（459行から）。パターンは12桁の数字、ARNの接頭辞、`AKIA`、`aws_secret`。planは認識している |
| 派生設計とS14の整合 | 整合。`squid.conf`は読むだけで、派生はコンテナ内の`.src`から行う。S14の行は変わらない |
| S14の`local_src`とpause方式の送信元 | 整合。共有名前空間ではClientの送信元が`127.0.0.1`になり、`127.0.0.0/8`に入る。実機確認はG3 |
| `docker-compose.yml`のClientの7から9行、depends_on、healthcheck、Squidの26行、tmpfs、WireMockの45、47行 | 実在。clarifyの行番号に1行のずれがある（A-14） |
| `scripts/quality-gate.sh`の68行（条件）、74行（検査リスト） | 実在 |
| `scripts/scenario-lib.sh`の`wiremock_reset`、`wiremock_verify_reset`、`WIREMOCK_URL`の既定（200行、214行） | 実在 |
| `wiremock_count` | `scenario-lib.sh`になく、`tests/m06`の449行などにある。planは受信数の取得方法を決めていない（A-11） |
| `tests/m08-e2e-suite.sh`の586、589行（`docker-compose run`）、749、813、905、1024行 | 実在。1076行も一致 |
| `docs/requirements.md`の17、33行 | 実在 |
| `.github/` | `CODEOWNERS`のみ。`workflows/`はない（clarifyと一致） |
| `.dockerignore` | 実在。`node_modules`、`.e2e/`、`e2e-logs/`を含まない（A-18） |
| `Dockerfile.test-client` | 実在。`alpine:3.20`、`curl`、`test-client/`の2ファイルをCOPYする |
| 既存の`package.json` | scriptsは`lint:md`のみ。planの6つの追加と衝突しない |
| `AGENTS.md`の末尾の「Ministackを追加した場合は表へ追加する」 | 実在 |

## 7. セキュリティと運用

| 観点 | 結果 |
| --- | --- |
| CIの権限 | `permissions: contents: read`、`persist-credentials: false`、`ubuntu-24.04`、2つの公式アクションだけ。問題なし。アクションのタグが可変な点はR-10に記録済み（A-22） |
| アーティファクトの識別情報 | 検査の設計はある。処理の定義に食い違いがある（A-06） |
| 後始末 | `trap`、冪等な`stop`、ラベルと接頭辞の両方で絞る設計は妥当。失敗経路の順序に曖昧がある（A-03） |
| `swsc-`以外に触らない | 設計は妥当。1.2の検査コマンドに部分一致の問題がある（A-19） |
| Colimaの`mktemp -d` | 整合。マウントするものは`.e2e/`に置き、`mktemp -d`はマウントしない偽の置き場だけに使う（plan 6.4） |
| ポート衝突 | 設計に矛盾がある（A-02） |
| 同時実行 | 固定名、固定ポートのため禁止し、文書に残す。CIの`concurrency`に例外がある（A-07） |
| ダミー認証情報の置き場 | CIはworkflowの`env`。ローカルは利用者の端末。エージェントのシェルでは設定できず、検証の実行主体が決まっていない（A-01） |

## 8. AGENTS.mdとの整合

| 項目 | 結果 |
| --- | --- |
| Spec Kitの順序 | specify、clarify、plan、tasks、analyzeの成果物が揃う。T906がimplement中にspec.mdを直すため、再確認の規則が必要（A-13） |
| 品質ゲート表への追加 | T916が`AGENTS.md`に行を足す。AGENTS.mdの末尾の記述と整合 |
| 必須2レビューの直列 | T919、T920が直列。依存も一致 |
| サブエージェントの条件 | tasksが`include_memory`、`include_lessons`、`include_project`、effort、モデルに触れていない（A-12） |
| 再レビューの範囲 | 範囲が広がった場合に2レビューを再実行する規則がない（A-12） |
| 任意レビュー | plan 10章は`aws-well-architected-review-lite`を実行するとするが、tasksにタスクがない（A-12） |
| 重い検査はメインエージェントが実行 | 整合。ただしメインエージェントも`smoke`を実行できない（A-01） |

## 9. 指摘事項

| ID | 重大度 | 場所 | 内容 |
| --- | --- | --- | --- |
| A-01 | High | tasks.md 1.1、T914、T917、T918、T921。plan.md 5.3、10章、R-14。spec.md NFR-902 | `smoke`と品質ゲートがダミー認証情報を要するが、エージェントのシェルでは設定できず、受け入れ条件を満たす主体がいない |
| A-02 | High | plan.md 3.8、5.2の7、6.4。tasks.md T907、T914。spec.md FR-912、NFR-908 | 8080を使う自分のコンテナと旧基盤を区別する規則がなく、`start`の冪等性と旧基盤検出の検査が成り立たない |
| A-03 | High | plan.md 3.8、6.3。spec.md FR-915 | `start`の失敗時の`stop`が`collect`より先に走りうる。起動失敗のログが残らない |
| A-04 | Medium | plan.md 4.1、4.3のG3。tasks.md T904 | G3のCI確認の方法が、planは一時workflow、tasksは本番workflowの初回実行で食い違う |
| A-05 | Medium | tasks.md T905。plan.md 4.3のG2。spec.md 1.2 | G2の候補タグの選び方が未定義。サブエージェントが貼り付けを待てない |
| A-06 | Medium | spec.md FR-918。plan.md 3.7。tasks.md T913 | マスクと削除の規則が食い違う。`scrub.txt`の再実行時の扱いが未定義 |
| A-07 | Medium | spec.md NFR-910、Q-902。plan.md 3.9、10章。tasks.md T924 | `main`のpushが取り消されないという前提がGitHubの`concurrency`の挙動と合わない |
| A-08 | Medium | plan.md 3.9、R-04。spec.md NFR-905、7章 | `smoke`だけの検査がCIで走らず、`ubuntu/squid:latest`の変化と「同じ検証」の記述が検知できない |
| A-09 | Medium | spec.md FR-920。plan.md 5.1。tasks.md T913 | `docker-compose`の文字列検査が`docker compose`を拾わず、メッセージの文字列とも衝突する |
| A-10 | Medium | tasks.md 1.2、1.3、T906。plan.md 2.2 | ゲート中は`.e2e/`が`.gitignore`にないため、「無視対象」を前提にした検査が成り立たない |
| A-11 | Medium | plan.md 3.8の`test`3項目。spec.md FR-907 | WireMockの受信数の取得方法と、許可外ドメインの具体値が未定義 |
| A-12 | Medium | tasks.md T919、T920。plan.md 10章。AGENTS.md | 必須レビューの実行条件、再レビューの範囲、任意レビューがtasksに落ちていない |
| A-13 | Medium | tasks.md T906。plan.md 12章 | implement中のspec.md変更に、再確認の規則がない |
| A-14 | Low | clarify.md | 後から確定した事項との差が残っている（5件） |
| A-15 | Low | tasks.md 1.4、T902、T905 | 共有ファイルの表の漏れ。G5の決定をplanへ書くタスクがない |
| A-16 | Low | tasks.md T905。spec.md FR-905 | G2の手順の順序、セッショントークンの検査 |
| A-17 | Low | plan.md 2.1、3.1、3.3、3.5 | MiniStackの起動の担当が重複。`local`と`direct`の組み合わせが未定義 |
| A-18 | Low | plan.md 3.4、2.3。`.dockerignore` | Clientイメージのビルド文脈が未定義 |
| A-19 | Low | tasks.md 1.2 | `--filter name=`は部分一致のため、他のプロジェクトを拾いうる |
| A-20 | Low | tasks.md T914、T915、T917、T918 | 順序と文言の細部 |
| A-21 | Low | plan.md 5.2の8、3.3 | `INT`の検査の落とし穴。使い捨てコンテナの命名 |
| A-22 | Low | plan.md R-05、R-10 | 可変タグ、Docker Hubのレート制限 |
| A-23 | Low | spec.md NFR-901。plan.md 5.1 | 外部通信の制限を確かめる検査がない |
| A-24 | Low | plan.md 5.1の文書、tasks.md T916、T922 | 識別情報の検査が自分の文書に反応しうる |

### A-01 `smoke`と品質ゲートを実行する主体がいない（High）

| 項目 | 内容 |
| --- | --- |
| 場所 | tasks.md 1.1の末尾、T914、T917、T918、T921。plan.md 5.3、10章の末尾、R-14。spec.md NFR-902 |
| 根拠 | NFR-902は、ダミー認証情報（`test`）の環境変数を利用者が自分の端末で設定し、エージェントのシェルでは設定しないと定める。FR-905は、未設定なら`aws`を呼ばず非ゼロで終了する。`smoke`の1（`start`）が契約検証を含むため、`smoke`のほぼ全項目が環境変数に依存する |
| 影響 | T914の受け入れ条件「`smoke`の1から10がすべて通る」、T918の「すべて成功」、T921の「ゲートが成功」を、エージェントは満たせない。T914は「該当部分を未検証として報告」とするだけで、そこからの手順がない。AGENTS.mdの実行ルール4は、環境上の理由で実行できないゲートを成功と断定することを禁じ、品質ゲートの通過までコミットを禁じる。`smoke`を品質ゲートに登録すると（5.3）、エージェントがゲートを通せない |
| 対応案 | G2（T905）と同じ手順に揃える。1) T914、T918の`smoke`、T921の品質ゲートは、エージェントが手順を提示して止まり、利用者が自分の端末で実行して結果を貼り付ける。結果は`specs/M09-execution-and-ci/smoke-results.md`などに記録し、貼り付けの前提（12桁の数字とARNを含めない）を書く。2) 品質ゲートに登録するのは`unit`だけにするか、`smoke`は環境変数が未設定のとき「未検証」を明示して失敗する（成功にしない）規則をtasks 1.1に書く。3) NFR-902を緩める案（コマンド単位で`test`を渡す）は、利用者の判断が要るため、選択肢として残す |

### A-02 8080を使う自分のコンテナと旧基盤の区別（High）

| 項目 | 内容 |
| --- | --- |
| 場所 | plan.md 3.8（`start`の順序）、5.2の6と7、6.4。tasks.md T907、T914。spec.md FR-912、NFR-908 |
| 根拠 | 1) T907とplan 5.1は、ポート8080と4566の使用中の検出を前提検査に含める。一方、3.8の`start`は「既存の`swsc-`の停止」の後に「ポートの空き確認」を置く。`test:ci`は「前提検査、start」の順で、前提検査の時点では前回の`swsc-wiremock`が8080を持っている。2) 5.2の7は、旧基盤が8080を使う状態を`swsc-`の接頭辞とラベルを付けた使い捨てコンテナで作り、`start`が止まることを確かめる。しかし`start`は最初に`swsc-`のコンテナを停止して回収するため、そのコンテナは消え、8080が空き、`start`は成功する。6.4は旧基盤の検出を「ポートを使うコンテナの名前を読む」とするが、名前の規則がない |
| 影響 | 1) 前提検査に8080の確認を置くと、`start`を2回続けた時（smoke 5）と、`start`の後の`test:ci`が、自分のコンテナのために失敗する。2) smoke 7は、設計どおりに実装すると必ず失敗する（`start`が成功してしまう）。名前による旧基盤の検出は、プロジェクト名が任意のため（`m05`、`pr99-review`など）、実装しても取りこぼす |
| 対応案 | 1) 前提検査（`e2e-lib.sh`）からポートの確認を外し、`start`の「停止の後」だけに置く。`test:ci`は前提検査の後に`start`を呼ぶため、同じ順になる。tasks T907とplan 5.1の「前提検査」の行を直す。2) 旧基盤の名前による検出をやめ、「`swsc-`以外が8080か4566を使用中」と定義する。メッセージに旧基盤の可能性を書く。FR-912の文言は「旧基盤が使用中の場合も、ポートの使用中として検出して止まる」に直す。3) smoke 7は、`swsc-`の接頭辞を付けない名前（例 `m09-smoke-port-holder`）の使い捨てコンテナで8080を塞ぎ、検査用の`trap`が名前を指定して必ず回収する。plan 5.2末尾の「接頭辞とラベルを付ける」の段落と、tasks T914の7を同じ内容に直す。1.2の「他のプロジェクトのコンテナは作らない」は、「検査が名前を指定して作り、回収するコンテナは除く」と書く |

### A-03 `start`失敗時の`stop`と`collect`の順序（High）

| 項目 | 内容 |
| --- | --- |
| 場所 | plan.md 3.8の擬似コードと「`trap`」の段落、6.3の表。spec.md FR-915 |
| 根拠 | FR-915は「収集は、コンテナの削除より前に行う」と定める。6.3は`start`が非ゼロで終わる場合に`EXIT`で`stop`を呼ぶとし、`test:ci`の`EXIT`は`collect`と`stop`と書く。3.8の擬似コードは`start`を同じシェルの関数のように呼ぶ。`start`の失敗時の`trap`が`test:ci`の中でも有効だと、`stop`が`collect`より先に走る。擬似コードは`start; rc=$?`と書くが、スクリプトが`set -e`を使う場合（M08などの流儀）、`start`の失敗で即時に終了し、`collect`に届かない |
| 影響 | 最も起こりやすい失敗（Squidの設定の派生や起動の失敗、MiniStackの登録の失敗）で、コンテナのログが消えた後に収集が走り、`missing.txt`だけのアーティファクトになる。FR-916の目的（失敗時のログの取得）を損なう。smoke 6は`e2e-logs/`が作られることだけを確かめ、中身を見ない |
| 対応案 | 1) `start`の本体（`start_main`）にはtrapを持たせず、操作として単独で呼ばれたときだけ、入口のラッパーが失敗時の`stop`を行う。`test:ci`は`start_main`を呼び、擬似コードは`start_main \|\| rc=$?`の形にする。2) `unit`に、偽の`start_main`が失敗したときに`collect`が`stop`より前に呼ばれる呼び出し順のケースを足す。3) smoke 6に、起動を途中で失敗させた場合の`e2e-logs/containers/`の存在の確認を足す（偽ではなく、不正な`SQUID_UPSTREAM`を使うなど、本番に分岐を持ち込まない方法で） |

### A-04 G3のCI確認の方法（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | plan.md 4.1の2と3行目、4.3のG3末尾の段落。tasks.md T904 |
| 根拠 | plan 4.3は、CIの確認を「ゲート用の一時ブランチにだけ置く最小のworkflow」で行い、確認後に破棄するとする。tasks T904は「ゲート用の一時ブランチやworkflowは作らない」と明記し、T924の本番workflowの初回実行で確かめるとする。一時ブランチのpushはcommit、push、PR作成の禁止（tasks 1.2）に反するため、tasksのほうが制約に合う |
| 影響 | Linuxでの名前解決（G1）、送信元ACL（G3）が、ほぼ全実装の後（T924）まで未確認になる。T924で覆ると、T910、T912、T903、T904の決定に戻る手戻りになる。planの記述に従う実装者は、禁止されたpushを行う |
| 対応案 | planの4.3のG3末尾の段落を削り、「CIでの確認はT924で行う」に統一する。T924に、G1またはG3の分岐が覆った場合に、`gate-results.md`、T910、T912へ戻って直し、`unit`と`smoke`を再実行する手順を足す。リスクR-03にも手戻りの可能性を書く |

### A-05 G2の候補タグとサブエージェントの停止（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | tasks.md T905、1.3。plan.md 4.3のG2。spec.md 1.2、NFR-909 |
| 根拠 | spec 1.2は、MiniStackの動作を確認した版を記録していない。T905の手順は`<固定する候補のタグ>`を「公式の版から選ぶ」とするだけで、選び方（最新の安定版、どの一覧を見るか、`latest`の禁止）がない。また、T905は手順を提示して利用者の貼り付けを待つが、AGENTS.mdはSpec Kitの工程をサブエージェントで実行するため、サブエージェントはユーザーを待てない |
| 影響 | 候補タグが実行者ごとに変わり、NFR-909の「実機検証に使った版に合わせる」が検証できない。サブエージェントが止まれず、貼り付けなしでT906へ進む恐れがある |
| 対応案 | 1) 候補タグの選び方を書く（例 MiniStackの公式リリースの最新の安定版を、リリースの一覧で確認し、タグがイメージレジストリに存在することを確かめる。`latest`と日付だけのタグは候補にしない）。2) T901からT904とT905の準備までを1つの実行、利用者の貼り付けを挟み、T906を別の実行にする区切りを、tasks 1.3に書く。T905の完了は、メインエージェントが貼り付けを受け取った時点とする |

### A-06 識別情報の処理の食い違い（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | spec.md FR-918。plan.md 3.7の最後の2項目。tasks.md T913、T905 |
| 根拠 | FR-918は、該当行のあるファイルを削除して失敗を記録すると定める。plan 3.7とT913は、コピーの上でマスクして再検査し、残ったファイルだけを削除して`scrub.txt`に記録する。specの12章の5は検査の正規表現だけを直し、マスクはG2の結果で決めるとするが、FR-918にはマスクの記述がない。さらに、単独の`collect`は「削除または記録があれば終了コード1」とするが、`test:ci`の内側で作った`scrub.txt`が残っていると、workflowの2回目の`collect`が毎回1を返すかどうかが決まっていない |
| 影響 | 実装者がspecとplanのどちらに従うかで、MiniStackのログが毎回削除されるか、マスクされるかが変わる。2回目の`collect`の終了コードが不定だと、testが成功したジョブをCIが失敗にする恐れがある（`collect`は`if: always()`のステップで、終了コードがジョブの結果になる） |
| 対応案 | 1) FR-918を「マスクして再検査し、残ったものを削除する」に直す（または、マスクをG2の結果で入れるかどうかの分岐としてspecに書く）。2) `scrub.txt`は各回の`collect`の先頭で作り直し、その回の削除または記録だけを終了コード1の条件にする、と書く。3) `unit`に「2回続けた`collect`の2回目が、削除対象なしなら0を返す」ケースを足す |

### A-07 `concurrency`と`main`のpush（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | spec.md NFR-910、Q-902。plan.md 3.9、10章（確認項目19）。tasks.md T924 |
| 根拠 | 設計は、グループを`${{ github.workflow }}-${{ github.ref }}`、`cancel-in-progress`をPRのときだけ`true`とし、`main`へのpushは取り消さないとする。GitHub Actionsの`concurrency`は、`cancel-in-progress: false`でも、同じグループで実行中のものが1件あり、さらに待機中の実行が来ると、古い待機中の実行を取り消す（実行中は1件、待機は最新の1件だけ残る）。公式文書で確認が必要な点だが、`main`へ短時間に3回pushすると、2回目の実行が取り消されうる |
| 影響 | 「`main`へのpushは取り消さない」が成り立たない。T924の確認項目19（`main`のpushが取り消されないこと）が、実装どおりでは失敗しうる |
| 対応案 | `main`のpushだけグループをコミットごとにする（例 `group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref \|\| github.sha }}`）。ランナーは実行ごとに別のVMで、ポートの衝突は起きない。計画段階で`concurrency`の仕様を公式文書で確認し、結果をplan 3.9に書く。確認できなければ「`main`のpushでも古い待機中の実行は取り消されうる」を制約として書き、T924の確認項目を直す |

### A-08 CIで走らない検査（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | plan.md 3.9の「`smoke`の位置」、R-04。spec.md NFR-905、7章、FR-909の層4 |
| 根拠 | CIは`unit`と`test:ci`だけを実行し、`smoke`はローカルと品質ゲートに限る。`smoke`だけにある検査は、不正な`SQUID_UPSTREAM`でSquidが非ゼロで終了すること、起動ログの`upstream=`、`direct`の`squid -k parse`、二重実行の冪等性、`INT`と`TERM`、ポート衝突、識別情報の検査である。R-04は`ubuntu/squid:latest`の更新を「`smoke`の起動ログで検知する」とするが、`latest`の更新はCIのクリーン環境で最初に現れる。NFR-905は「ローカルとCIで同じ検証が実行される」と書き、7章は「GitHub Actionsのクリーン環境で同じ検証が通る」と書く |
| 影響 | `latest`の更新でSquidの`direct`設定が壊れても、CIは気づかない。スペックの記述と実際の検証範囲が食い違う |
| 対応案 | 1) CIの時間に余裕があれば（T924の実測で判断）、`smoke`の中でDockerと`aws`だけで済む項目（3、4、5）を、`test:ci`の後に追加の1ステップで実行する。2) 追加しない場合は、NFR-905と7章の文言を「`test:ci`とunitが同じ」に直し、CIで走らない検査を`docs/ローカル実行とCI.md`の検証範囲の節に列挙する。R-04の対策文も実際の検知経路に直す |

### A-09 FR-920の文字列検査（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | spec.md FR-920。plan.md 5.1の「FR-920」の行。tasks.md T907、T913 |
| 根拠 | 検査は`scripts/e2e*.sh`、`ecs/`、workflowに`docker-compose`の文字列がないことを`grep`で確かめる。1) Docker Compose v2の`docker compose`（空白）は一致しない。2) FR-912の旧基盤の検出メッセージやコメントに、文字列`docker-compose`を書くと検査自体が失敗する。3) 検査対象のファイルに`tests/m09-execution-and-ci.sh`は含まれず、`unit`が偽の`docker-compose`を置く記述との区別も要る |
| 影響 | `docker compose`の呼び出しがすり抜ける。または、説明のための文字列で検査が失敗し、実装者が文字列を消す回避に走る |
| 対応案 | 検査を「コマンドとして呼ぶ形」に定義する（行頭または`;`、`&&`、`\|`、`$(`の直後の`docker-compose`と`docker compose`）。コメントとメッセージでの言及は旧基盤という語を使う。対象は`scripts/e2e*.sh`、`ecs/`、`.github/workflows/e2e-test.yml`、`package.json`とする。偽の置き場は`tests/`なので対象外と書く |

### A-10 ゲート中の`.e2e/`（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | tasks.md 1.2、1.3（通過の条件4）、T906の検査。plan.md 2.2 |
| 根拠 | `.gitignore`への`.e2e/`の追加はT907（U2）の作業で、T906より後である。tasks 1.3はT907の下書きの先行も禁じる。しかし条件4は「`git status --short`に`.e2e/`（無視対象）以外の変化が無い」と書き、1.2は`.e2e/`が`.gitignore`に入っていることの確認を求める。また、`specs/M09-execution-and-ci/`全体が現在は未追跡で、`git status --short`は常にこのディレクトリを表示する |
| 影響 | ゲートの間、`.e2e/gate/`が未追跡として表示され、条件4の文言どおりには判定できない。実験後に`.e2e/gate/`を削除しても、空の`.e2e/`が残る |
| 対応案 | 条件4を「作業開始前の`git status --short`との差が、`specs/M09-execution-and-ci/`の文書だけであること。実験後に`.e2e/`ごと削除されていること」に直す。1.2の`.gitignore`の確認は、T907以降のタスクに限ると書く |

### A-11 通信検証の中身（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | plan.md 3.8の`test`3項目。spec.md FR-907。tasks.md T914 |
| 根拠 | 1) 項目1は「WireMockの受信が1」、項目2は「受信総数が0のまま」を期待値とする。しかし`wiremock_count`は`scripts/scenario-lib.sh`になく、`tests/m06-client-resilience.sh`（449行）と`tests/m07-scenario-isolation.sh`に別々に定義されている。planは再利用するのが`wiremock_reset`と`wiremock_verify_reset`だけと書き（2.3）、受信数の取得方法（管理APIのどのパス、`python3`か`curl`か）を決めていない。2) 項目2の許可外ドメインの具体値と、リクエストのパスが書かれていない。`Dockerfile.test-client`のClientは`TEST_API_BASE_URL`の上書きで宛先を変えるが、項目2のためにどの値を渡すかが不明 |
| 影響 | 実装者ごとに検証の中身が変わる。NFR-903（検証の中身は変えない）とFR-907の確認の対象が曖昧になる |
| 対応案 | 受信数は`GET /__admin/requests`の`meta.total`を`python3`で読む、と`e2e-lib.sh`の関数名とともにplan 3.8へ書く。許可外ドメインは`whitelist.txt`にないダミーのドメイン（例 `blocked.example.net`）とし、項目1と項目2で使うパスとTEST変数を表にする |

### A-12 必須レビューのタスク（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | tasks.md T919、T920。plan.md 10章。AGENTS.md「サブエージェントの実行条件」「レビューの進め方」 |
| 根拠 | 1) AGENTS.mdは、`include_memory=false`、`include_lessons=false`、`include_project=true`、effort `medium`、ファイル変更禁止、Git操作禁止を必須とする。T919とT920は、1サブエージェント、`SKILL.md`の読み取り、重い検査の禁止を書くが、これらの設定を書いていない。2) AGENTS.mdは、変更範囲が広がった場合に必須の2レビューをすべて再実行する。T919は「T918の該当部分を再実行」、T920は「T919の修正が入った場合はスナップショットを作り直す」とだけ書く。3) plan 10章は、CI/CDとネットワークを変更するため`aws-well-architected-review-lite`も実行すると書くが、tasksにタスクがない。4) AGENTS.mdはレビューのモデルをClaude Sonnet 5.5と推奨するが、tasksに記載がない |
| 影響 | 実装者が条件を省略する。T920で実質的な修正が入った場合に、T919の再実行の要否が決まらない。任意レビューの実行が漏れる |
| 対応案 | T919、T920に、AGENTS.mdの設定表への参照と、必須値を明記する。T920の修正が範囲を広げた場合は、T919とT920をスナップショットから再実行する、と書く。任意レビューを、T920の後のタスク（T920の2）として足すか、実行しない判断をplan 10章に書く。モデルの記載は「AGENTS.mdの推奨に従い、利用可能な一覧から解決する」とする |

### A-13 implement中のspec.md変更（Medium）

| 項目 | 内容 |
| --- | --- |
| 場所 | tasks.md T906、1.4。plan.md 12章の1と2 |
| 根拠 | T906は、G1とG2の結果によって、FR-910、Q-915、FR-904、FR-902、NFR-906を直す（利用者の判断を含む）。G2の分岐の(A)から(C)は、FR-904の緩和やNFR-906の緩和を含む。Spec Kitの規則は、analyzeの指摘を解消してからimplementに進むと定める。implement中にspecが変わる場合の、clarifyとanalyzeの再実行の要否が決まっていない |
| 影響 | spec、plan、tasksの整合が、ゲートの後に再確認されないまま実装が進む。利用者の判断で要件が緩むと、レビュー（T919、T920）が緩んだ要件を基準にしてしまう |
| 対応案 | T906に「`spec.md`を直した場合は、直した箇所の範囲でanalyzeの確認（番号と値の突き合わせ）を行い、`gate-results.md`に記録する。NFR-906の緩和など安全側の要件を緩める場合は、実装に進む前に利用者の明示的な承認を記録する」を足す |

### A-14 clarifyの更新漏れ（Low）

| 場所 | 内容 | 対応案 |
| --- | --- | --- |
| clarify.md Q-904の手順表 | `unit`のステップがない（spec FR-914、plan 3.9にはある） | 手順表に`unit`の行を足す |
| clarify.md Q-905、反映事項13 | 検査の正規表現が単純な12桁の数字（spec、planは前後が英数字と`-`でないもの） | 正規表現を揃える |
| clarify.md 反映事項11、20、実機確認の表の6 | `python3`（またはjq） | `python3`に確定した旨を足す |
| clarify.md Q-917のmock | `cache_peer_access`の行も置換する（planは`name=wiremock`で不要） | planの決定に揃える |
| clarify.md 前提の表（`docker-compose.yml`） | 行番号が1行ずれる。depends_onは11から15行、Squidのvolumesは29から31行 | 行番号を直す |

### A-15 tasks 1.4の表の漏れ（Low）

- 共有ファイルの表で、`scripts/e2e.sh`の編集者にT909が載っていない（T909の「触るファイル」にはある）。
- `plan.md`の編集者の行がない。T906は分岐に該当する場合に直すと書き、G5の決定（plan 3.4の手順4）を書くタスクも定まっていない。
  T902かT906のどちらかに明記する。
- tasks 1.4の`ecs/squid/`の行にある「T913の修正を除く」は、T913が`ecs/squid/`を触らないため、意味が通らない。
- 4章で、T902はFR-908、T905はFR-905とNFR-906を持つが、4章の行にそれらが載っていない。

### A-16 G2の手順とセッショントークン（Low）

- T905の手順1は、`docker run -d`の後に`time docker pull`を置く。`docker run`が先にイメージを取得するため、取得時間が測れない。
  `docker pull`を先にする。
- `swsc_aws`とFR-905は、`AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`だけを検査する。
  `AWS_SESSION_TOKEN`と`AWS_PROFILE`が設定されていると、実AWSの認証情報が経路に残る恐れがある。
  `AWS_SESSION_TOKEN`は`unset`するか、設定されていれば止める。

### A-17 MiniStackの起動の担当と`local`プロファイル（Low）

- plan 2.1は`e2e-contract.sh`をMiniStackの起動の担当とし、3.3の起動順の表は`swsc-ministack`を2番目に置く（ランナーの表）。
  3.5の手順1もコンテナの起動を含む。担当をどちらか1つにする。
- plan 3.1は、`local`プロファイルのときだけ`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`を足すと書く。
  `--profile local --upstream direct`にモックの宛先が指定された場合の動作（拒否か無視か）が決まっていない。

### A-18 Clientイメージのビルド文脈（Low）

plan 3.4は、Squidのビルド文脈を`.e2e/context/squid/`に限る。Clientのビルドは「既存のDockerfileからそのまま」とだけ書く。
`Dockerfile.test-client`は`test-client/`を相対パスでCOPYするため、文脈はリポジトリのルートになる。
`.dockerignore`は`node_modules`、`.e2e/`、`e2e-logs/`を除外しておらず、plan 2.3は`.dockerignore`を変更しない。
イメージには`COPY`したファイルだけが入るので、中身の漏れはない。ローカルで`node_modules`と`.e2e/run/*.env`がデーモンに送られる。
Clientのビルド文脈を`.e2e/context/client/`に作る（`test-client/`の2ファイルとDockerfileだけ）と、Squidと揃う。

### A-19 `swsc-`の検査コマンドの部分一致（Low）

tasks 1.2の`docker network ls --filter name=swsc- -q`は、名前の部分一致（正規表現）で絞る。
`foo-swsc-bar`のような他のプロジェクトのネットワークが残っていても、検査が失敗する。
コンテナの検査は`--format '{{.Names}}'`の出力に`^swsc-`を`grep`する書き方になっているため、ネットワークも同じ書き方に揃える。

### A-20 順序と文言の細部（Low）

- T914とT915はどちらも`tests/m09`を編集する。順序をT914、T915の直列と明記する。
- T917の「触るファイル」は「登録する場合だけ」とするが、`unit`は必ず登録する。`smoke`を登録しない場合の文言に直す。
- T918の最後の項目は「`analyze`の入力になる」と書くが、analyzeはimplementより前の工程である。
  実装後の整合確認という意味に直す。
- plan 3.8の擬似コードは`set -e`の下で動かない（A-03）。`|| rc=$?`の形に直す。
- 起動待機の上限120秒が、待機ごとか、`start`全体かが書かれていない。MiniStack、WireMock、Squidの3つの待機があるため、
  最悪で360秒になる。待機ごとの上限と明記し、`start`全体の上限の要否をT924の実測で判断する。

### A-21 `INT`の検査と使い捨てコンテナの命名（Low）

- smoke 8は、子として本物の入口を起動して`INT`を送る。POSIXの非対話シェルでは、`&`で起動した子は`SIGINT`を無視する。
  M07の`smoke_child_signal`がこの問題を扱っているため、同じ方式を再利用すると書く。
- 3.3の待受の確認（`nc -z`の使い捨てコンテナ）と、smoke 3、4の使い捨てのSquidに、`swsc-`の接頭辞とラベル、`--rm`を付けると書く。
  付けないと、中断時に`stop`で回収できない。

### A-22 可変タグとレート制限（Low）

- 公式アクションのメジャーバージョンのタグと、MiniStackのタグは可変である（R-05、R-10に記録済み）。
  `security-review`で指摘される前提で、コミットSHAまたはイメージのダイジェストへの固定を利用者に確認する選択肢を残す。
- CIでは`ubuntu/squid`、`alpine`、`wiremock/wiremock`、`ministackorg/ministack`の4つをDocker Hubから取得する。
  Docker Hubのレート制限による失敗が、リスクの表にない。T924の初回実測で確認し、R-16に追記する。

### A-23 外部通信の制限の検査（Low）

NFR-901は、CIが外部へ出る通信をチェックアウト、アクション、イメージの取得に限ると定める。
planの`unit`と`smoke`には、実AWSへの接続を試みないこと（`--endpoint-url`を毎回明示する以外の検査）が含まれていない。
`swsc_aws`の呼び出しにエンドポイントが付くことは偽の`aws`で確かめられる。
`aws`の直接呼び出しが1か所だけという`grep`と合わせて、NFR-901の確認方法をT918に1行で書く。

### A-24 識別情報の検査と文書の自己検査（Low）

- 文書の`unit`は12桁の数字とARNの接頭辞を検査する。`docs/ローカル実行とCI.md`は、この検査を説明するために同じ文字列を書きたくなる。
  説明は語で書き、パターンを文書に書かないと決める。
- T922の最終の`grep`は、コミット対象の全ファイルを対象にし、検査コードの正規表現の記述を除くと書く。
  `specs/M09-execution-and-ci/`のspec、clarify、plan、tasks（本ファイルを含む）にARNの接頭辞の文字列がある。
  除外の対象を「`tests/m09-execution-and-ci.sh`と`specs/M09-execution-and-ci/`の説明」と具体的に書く。

## 10. 確認範囲（指摘がなかった観点を含む）

| 観点 | 結果 |
| --- | --- |
| 1 要件の対応 | FR 21件、NFR 11件が、planとtasksの両方で対応し、対応先のU/Tが実在し、内容も一致した。指摘なし |
| 2 番号・名前・値 | 名前、環境変数、ポート、タイムアウト、コマンド名、イメージの固定は一致した。食い違いはA-06、A-14 |
| 3 ゲート | 順序、分岐、記録先は一致した。指摘はA-04、A-05、A-10、A-15 |
| 4 依存と並列 | 循環と欠けはない。並列は1組だけで、ファイルの重なりはない。指摘はA-15、A-20 |
| 5 方針 | Compose、ソケット、認証情報、Secrets、入力値の方針は設計上整合した。指摘はA-09、A-16 |
| 6 既存実装の参照 | 行番号、関数、設定は実在した。S14の固定行検査と派生設計は整合した。指摘はA-11、A-14、A-18 |
| 7 セキュリティ・運用 | CIの権限、後始末、Colimaの制約は整合した。指摘はA-02、A-03、A-06、A-07、A-19 |
| 8 AGENTS.md | Spec Kitの順序、ゲート表、2レビューの直列は整合した。指摘はA-12、A-13 |

## 11. 判定

条件付き PASS。

- Criticalはない。要件の欠けと、循環した依存もない。
- A-01からA-03（High）は、実装がそのままでは破綻する。A-01は検証の実行主体がなく、A-02は検査が必ず失敗し、
  A-03は失敗時のログが消える。反映するまでimplementに進まない。
- A-04からA-13（Medium）は、A-01からA-03と同時に反映する。
- A-14からA-24（Low）は、反映してもしなくても、implementのブロックにはならない。

## implement 前に反映する修正

### spec.md

- FR-912: 旧基盤の検出を、「`swsc-`以外が8080か4566を使用中」に直す（A-02）。
- FR-918: マスクと再検査、削除の順を書く（A-06）。
- NFR-905、7章: CIで走る検証の範囲に、文言を合わせる（A-08）。
- NFR-910、Q-902: `main`のpushの取り消しの記述を直す（A-07）。

### plan.md

- 3.8: `start`と前提検査の順序（ポートの確認は停止の後）、`start_main`と`trap`の構造、擬似コードの`set -e`（A-02、A-03、A-20）。
- 3.8: `test`の受信数の取得方法と、許可外ドメインの具体値（A-11）。
- 3.7: `scrub.txt`の回ごとの作り直し（A-06）。
- 3.9、10章: `concurrency`のグループ（A-07）、`smoke`の一部のCI実行の要否（A-08）。
- 4.3のG3: 一時workflowの段落を削る（A-04）。
- 5.1: FR-920の検査の定義（A-09）。
- 5.2の7と末尾の段落、6.4: 旧基盤の模擬の方法（A-02）。
- 10章: 任意レビューの扱い（A-12）。

### tasks.md

- 1.1、T914、T917、T918、T921: `smoke`と品質ゲートの実行主体（A-01）。
- T905、1.3: 候補タグの選び方と、実行の区切り（A-05）。
- T906、1.3、1.2: 条件4の`.e2e/`、spec変更時の再確認（A-10、A-13）。
- T907: 前提検査からポートの確認を外す（A-02）。
- T913: `start_main`、`collect`の順序、`scrub.txt`、FR-920の検査（A-03、A-06、A-09）。
- T914: smoke 6と7の内容（A-02、A-03）。
- T919、T920: AGENTS.mdの設定と再レビュー（A-12）。
- T924: G1とG3が覆った場合の手戻り、`concurrency`の確認項目（A-04、A-07）。
- 1.4: 共有ファイルの表（A-15）。

### clarify.md

- A-14の5件を反映する（任意）。

## 12. 反映状況（High 3件、Medium 10件）

A-01からA-13は、指摘が示す場所を読んで事実を確かめたうえで、すべて反映した。不反映のものはない。
Low（A-14からA-24）は対象外とした。ただし、反映の過程で次の4件は同時に解消した。

| ID | 同時に解消した内容 |
| --- | --- |
| A-15 の一部 | tasks 1.4 の表に、T909 の`scripts/e2e.sh`、`plan.md`の編集者（T906）、`ecs/squid/`の「T913の修正を除く」の削除を反映した |
| A-19 | tasks 1.2 のネットワークの検査を、`docker network ls --format`の出力への`^swsc-`の検査に直した |
| A-20 の一部 | T914、T915 の直列の順、T917 の文言、T918 の最後の項目の文言を直した |
| A-16 の一部 | T905 の手順を`docker pull`の後に`docker run`へ並べ替えた |

その他の Low は、反映していない。

### 12.1 反映先

| ID | 事実の確認 | 反映先 |
| --- | --- | --- |
| A-01 | 事実。`smoke`の1が`start`経由でMiniStackの登録を含み、前提検査が認証情報を要求していた | 検査を`unit`、`smoke`、`contract`の3層に分けた。spec: FR-901、FR-903、FR-904、FR-905、FR-906、FR-912、FR-922（新設）、NFR-902、NFR-905、4章の表、5.2、7章、Q-901、Q-909。plan: 1章の表、2.1、2.2、3.3、3.5、3.8（前提検査の表）、5.1、5.2、5.3、5.4（新設）、8章（U2、U6、U8、U9、U12、U13）、8.1、9章、10章、12章（番号9）、13章（R-14）。tasks: 1.1、1.4、T907、T911、T912、T913、T914、T917、T918、T921、T925（新設）、3章、4章、5章 |
| A-02 | 事実。`test:ci`は前提検査で8080を確認する順で、自分の`swsc-wiremock`が残っていた。smoke 7は`start`の最初の停止で回収される | ポート確認を`start_main`と`contract`の停止の後に移した。旧基盤の名前による検出をやめ、「`swsc-`以外が使用中」と定義した。smoke 7は`swsc-`の接頭辞を付けない名前のコンテナで行い、検査の`trap`が名前を指定して回収する。spec: FR-912。plan: 3.8（前提検査の表）、5.1（ポートの確認）、5.2（5、6、7）、6.4。tasks: 1.2（例外）、T907、T913、T914 |
| A-03 | 事実。`start`の`trap`が`test:ci`の中でも有効だと、`stop`が`collect`より先に走る。擬似コードは`set -e`の下で動かない | `start_main`は`trap`を持たず、`start`操作のラッパーだけが失敗時に`stop`する。`test:ci`は`start_main \|\| rc=$?`で受け、`collect`、`stop`の順にした。呼び出し順の`unit`ケースと、smoke 11（起動の途中で失敗させ、`e2e-logs/containers/swsc-squid.log`を確認）を足した。spec: FR-915、4章。plan: 3.8、5.1（`test:ci`の順序）、5.2（11）、6.3。tasks: T913、T914、5章 |
| A-04 | 事実。plan 4.3 は一時ブランチの最小workflowを置き、tasks T904 は作らないとしていた | plan 4.3 の G3 末尾を、「CIでの確認はU14（T924）で行う」に統一した。T924 に、G1またはG3が覆った場合の手戻りの手順を足し、R-03 にも書いた |
| A-05 | 事実。候補タグの選び方が無く、サブエージェントは貼り付けを待てない | plan 4.3 の G2 に選び方（最新の安定版、レジストリでの存在確認、`latest`と日付だけのタグの禁止、根拠の記録）を足した。tasks 1.3 に実行1と実行2の区切りを書き、T905 に選び方を書いた |
| A-06 | 事実。FR-918 は削除、plan 3.7 とT913 はマスクして残りを削除と書いていた | FR-918 をマスクして再検査し、残ったものを削除する規則に直した。`scrub.txt`は`collect`の実行ごとに作り直し、その回の削除または記録があるときだけ終了コード1にする。plan 3.7、5.1（収集）、tasks T913 に、続けて2回実行した`collect`の2回目が0を返す`unit`ケースを足した |
| A-07 | 事実。GitHub の公式文書（Control the concurrency of workflows and jobs）に、同じグループでは`cancel-in-progress: false`でも待機中の古い実行が置き換わる（`queue: single`が既定）とある | 下の12.2 に記す。spec: FR-913、NFR-910、Q-902。plan: 3.9（取り消しの行、`concurrency`のコード）、10章（確認項目19）。tasks: T915、T924 |
| A-08 | 事実。CIは`smoke`を実行せず、`latest`の更新をCIが検知できなかった | 対応案1に従い、CIで`unit`、`test:ci`、`smoke`、`contract`の順に実行する（FR-914）。`smoke`と`contract`のステップのタイムアウト（8分、5分）は仮値とし、T924 の実測で見直す。plan: 3.9、R-04、R-16。tasks: T915、T924 |
| A-09 | 事実。plan 5.1 の FR-920 の検査は`docker-compose`の文字列検査で、`docker compose`（空白）を拾わなかった | FR-920 の検査を、コマンドとして呼ぶ形（行頭、または`;`、`&&`、`\|`、`$(`の直後）の`docker-compose`と`docker compose`にした。対象は`scripts/e2e*.sh`、`ecs/`、workflow、`package.json`。`tests/`は対象外。メッセージでは「旧基盤」と書く。spec: FR-920。plan: 5.1。tasks: T913、T915 |
| A-10 | 事実。`.gitignore`への`.e2e/`の追加はT907の作業で、T906の前である | 条件4を、作業開始前の`git status --short`との差が文書だけで、`.e2e/`ごと削除されていることに直した。1.2 の`.gitignore`の確認を T907 以降に限った。plan: U1 の検査。tasks: 1.2、1.3、T906 |
| A-11 | 事実。`wiremock_count`は`scripts/scenario-lib.sh`に無く、M06 と M07 に別々にある | 受信数は`GET /__admin/requests`の`meta.total`を`python3`で読む関数`swsc_wiremock_total`とした。許可外ドメインは`blocked.example.net`とし、`TEST_API_BASE_URL`の上書きで渡す。3項目の要求と期待値の表にした。spec: FR-907。plan: 3.8 |
| A-12 | 事実。T919、T920 に AGENTS.md の設定が無く、任意レビューのタスクが無かった | T919、T920 に必須値（1スキル1サブエージェント、`include_memory=false`、`include_lessons=false`、`include_project=true`、effort `medium`、ファイル変更禁止、Git操作禁止、モデルは AGENTS.md の推奨）を書いた。範囲が広がった場合の2レビューの再実行を書いた。任意レビューを T926（新設）に置いた。plan: 10章 |
| A-13 | 事実。T906 は spec.md を直すが、再確認の規則が無かった | T906 に、直した箇所の範囲での analyze の確認と`gate-results.md`への記録、安全側の要件を緩める場合の利用者の明示的な承認を足した。plan: 12章の導入にも同じ規則を書いた |

### 12.2 A-07 の選択

「`main`のpushは取り消さない」をそのまま保つため、要件を弱めず、`main`のpushのグループをコミットごとに分ける案を選んだ。

| 項目 | 内容 |
| --- | --- |
| グループ | `${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref \|\| github.sha }}` |
| PR | ref 単位のグループで、`cancel-in-progress: true`。新しい実行が古い実行を取り消す |
| `main`のpush | `github.sha`を含むため、コミットごとに別のグループになる。待機中の実行の置き換えが起きず、互いに取り消さない |
| ポートの衝突 | ランナーは実行ごとに別のVMのため起きない |
| 確認 | T924 の確認項目19で、同じPRの2回目のpushによる取り消しと、`main`への短時間の複数pushを確かめる |

### 12.3 追加した番号

| 種類 | 番号 | 内容 |
| --- | --- | --- |
| FR | FR-922 | 検査の3層（`unit`、`smoke`、`contract`）、実行主体、品質ゲートへの登録の範囲 |
| NFR | なし | 追加なし |
| タスク | T925 | `contract`の実行と結果の記録（利用者の端末。エージェントは実行しない） |
| タスク | T926 | 任意レビュー`aws-well-architected-review-lite` |
| plan 節 | 5.4 | `contract`の検査（C1からC6） |
| smoke 項目 | 11 | 起動の途中で失敗させた`test:ci`で、`collect`が`stop`より先に走ることの確認 |
| 新規ファイル | `contract-results.md` | 利用者の端末での`contract`の実行結果の記録（識別情報を含めない） |

追加後の件数は、FR 22件、NFR 11件、タスク26件（T901からT926）である。
