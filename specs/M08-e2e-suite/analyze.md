# M08 analyze結果

## 0. 結果の要約

| 項目 | 内容 |
| --- | --- |
| 判定 | 条件付き PASS |
| Critical | 0件 |
| High | 1件（A-01） |
| Medium | 5件（A-02、A-03、A-04、A-05、A-06） |
| Low | 7件（A-07からA-13） |
| implementをブロックするか | A-01は反映するまでブロックする。A-02からA-06は同時に反映する。Lowはブロックしない |

対象は`spec.md`、`clarify.md`、`plan.md`、`tasks.md`。文書は変更していない。形式は`specs/M07-scenario-isolation/analyze.md`にそろえた。

## 1. 要件カバレッジ

`spec.md`のFR-801からFR-814、NFR-801からNFR-808を、`plan.md` 11.1の対応表と`tasks.md` 4章の対応表に突き合わせた。

| 要件 | plan（11.1） | tasks（4章） | 検証 | 判定 |
| --- | --- | --- | --- | --- |
| FR-801 自動実行 | U5 | T805 | `unit`の続行と停止 | PASS |
| FR-802 正常 | U3、U7 | T803、T807 | `unit`の期待値表、`smoke`の周1 | PASS |
| FR-803 500後に成功 | U3、U7 | T803、T807 | 同上、`wait=1`の行の検査 | PASS |
| FR-804 タイムアウト | U1、U3、U7 | T801、T803、T807 | 同上。受信回数はQ-810待ち | 条件付き（A-01） |
| FR-805 429 | U3、U7 | T803、T807 | 同上、`capped=0`の3本 | PASS |
| FR-806 4つの情報源 | U3、U7 | T803、T807 | `unit`の抽出 | PASS |
| FR-807 リセット確認の失敗 | U5 | T805 | `unit`の停止、`smoke`の注入 | 条件付き（A-02） |
| FR-808 順序の独立 | U5、U7 | T805、T807 | `unit`の逆順 | PASS |
| FR-809 レポート | U4 | T804 | `unit`のレポート | 条件付き（A-02） |
| FR-810 失敗時の再現情報 | U4、U8 | T804、T808 | `unit`と`smoke`の注入 | PASS |
| FR-811 続行と終了コード | U5、U8 | T805、T808 | 同上 | PASS |
| FR-812 入口と引数 | U2、U7 | T802、T807 | `unit`の引数4種 | PASS |
| FR-813 後始末 | U6、U8 | T806、T808 | 失敗経路の回収 | PASS |
| FR-814 文書 | U9 | T809 | `unit`の文書検査、`npm run lint:md` | 条件付き（A-04） |
| NFR-801 閉域 | U1、U6、U7、U11 | T801、T806、T807、T811 | 検証方法が具体的でない | 条件付き（A-12） |
| NFR-802 変更範囲 | U3、U10、U11 | T803、T810、T811、T812 | `git diff` | 条件付き（A-12） |
| NFR-803 時間 | U1、U7 | T801、T807 | `elapsed=`の行 | PASS |
| NFR-804 POSIX sh | U2、U6 | T802、T806 | ゲートの`sh -n` | PASS |
| NFR-805 連続2回 | U7、U11 | T807、T811 | 周1と周2、2回起動 | PASS |
| NFR-806 並列禁止 | U2、U5 | T802、T805 | 直列の実装、文書 | PASS |
| NFR-807 識別情報 | U4、U8、U9 | T804、T808、T809 | `unit`の`grep` | PASS |
| NFR-808 再現の容易さ | U4、U7、U9 | T804、T807、T809 | 名前指定の1行レポート | PASS |

### 1.1 網羅の突き合わせ

FR 14件とNFR 8件は、plan 11.1とtasks 4章の両方で、1つ以上の単位とタスクに対応する。欠けはない。

- plan 11章の単位ごとの「要件」列とplan 11.1は一致する。
- tasks 4章と各タスクの「要件」欄は一致する。T812の`NFR-802`だけは4章にも載っている。
- plan 11章U1からU11は、tasks 1章の表でT801からT811に1対1で対応する。T812は追加で、plan 11章に対応する単位はない。
- `spec.md` 7章の完了条件10項目は、T811の突き合わせとtasks 5章で網羅される。

## 2. 矛盾の確認

4文書で、次の語と値を突き合わせた。

| 項目 | 結果 |
| --- | --- |
| 入口のパス`tests/m08-e2e-suite.sh` | 4文書で一致 |
| 引数`[unit\|smoke] [シナリオ名...]`、引数なしは`smoke` | 一致 |
| 終了コード0（全件合格）、1（失敗）、2（引数の誤り）、130、143 | 一致 |
| シナリオ名とパス（`normal`、`error-500-then-200`、`ratelimit-429`、`slow-5000`） | 一致。`scenario_path`の結果と`wiremock-scenarios/mappings/`の`name`も一致 |
| 既定の順（`slow-5000`が最後） | spec NFR-808、plan 3.2、clarifyで一致 |
| `RESPONSE_TIMEOUT_SECONDS=1`（タイムアウトのみ） | 一致。`retry-lib.sh`の検査（最小値1）を通る |
| 待機の秒数（500後が1、タイムアウトが1、429が`Retry-After: 2`の3回で6、合計約8） | spec NFR-803、plan 5.2と12章で一致。`error-429-case.json`は`Retry-After: 2` |
| 文書のパス`docs/E2Eテスト.md` | 一致。`README.md`の参照先も同じ |
| 品質ゲートの位置（M07の後、`s14`の前） | 一致。`scripts/quality-gate.sh`の74行の並びと合う |
| 総試行4、リトライ3（429） | 一致。`RETRY_MAX_ATTEMPTS_429`の既定3と合う |

食い違いは次のとおり。

| 項目 | 一方の記述 | もう一方の記述 |
| --- | --- | --- |
| 未実行の表記 | spec FR-807は`FAIL`（未実行）と`未実行`、FR-809は合否を`PASS`か`FAIL`に限る | plan 5.3とtasks T804は`NOT_RUN`を足し、失敗数に数えない（A-02） |
| `slow-5000`の`wiremock`の期待値 | plan 3.2は「記録されない」で`wiremock=-`を期待値にする | plan 3.4は`wiremock_count`を直後に読む。実測は`wiremock=0`になる（A-01） |
| spec.mdを変更できるタスク | tasks 1.4は`spec.md`の編集をT801のみとする | T808の最終項目は`spec.md`のFR-813を直す（A-07） |
| T810の編集対象 | tasks T810の「触るファイル」は`scripts/quality-gate.sh`のみ | 同じ節が、登録しない場合に`docs/E2Eテスト.md`へ書くとする（A-04） |
| 503の扱い | spec 2章は「503または遅延によるタイムアウト」 | spec FR-804は503を含めない（Q-802）。clarifyで決定済みだが2章が残っている（A-13） |

## 3. Q-810の分岐の整合（確認項目3）

plan 7.3とtasks T801の分岐を、4行とも突き合わせた。判定の条件、`wiremock`の扱い、待機の有無、`spec.md`の直し方は一致する。

| 分岐 | plan 7.3、7.4 | tasks T801 | 繋がり |
| --- | --- | --- | --- |
| 即時に記録 | `wiremock=1`、待機なし、「暫定」を外す | 同じ | T803で確定、T805は待機なし。FR-804と4章の表が一致 |
| 遅れて記録 | `wiremock=1`、1秒おきに読む（上限10秒）、FR-804に1文 | 同じ | T805の待機（T805の最終項目）に繋がる。時間の見積もりは8秒から約4秒増える（A-13） |
| 記録されない | 期待値の`wiremock`を`-`にする、FR-804と4章の表から外す | 同じ | 実測の側が`-`にならず不一致になる（A-01） |
| 揺れる、または1超 | 「記録されない」と同じ | 同じ | 同上 |

分岐の先のT803、T805、FR-804、4章の表、`docs/E2Eテスト.md`の表は、文言のうえでは繋がる。
欠けているのは、期待値を`-`にしたシナリオで、実測も`-`にする規則である（A-01）。

## 4. タスクの依存順（確認項目4）

- T801より前に、依存するタスクはない。T801の「依存」は「なし」で、T802以降の下書きも禁止されている（1.3）。
- 並列とした組はT809の文書本体とT806またはT808の1組だけである。編集するファイルは`docs/E2Eテスト.md`と
  `README.md`で、T806とT808の`tests/m08-e2e-suite.sh`と重ならない。文書はポートを使わない。
- T809の文書検査（`unit`のケース追加）は同じ検査ファイルを編集するため、直列にしている。これは正しい。
- T809の「所要時間の目安」はT807の実測に依存し、1.4で空けておくとしている。順序の矛盾はない。
- T810は文書の「登録しない場合」の記述でT809のファイルを再び編集する（A-04）。T809の後なので衝突はしない。
- T803とT804の直列化は過剰ではない。同じファイルを編集する。

## 5. 後始末とコミット対象の条件（確認項目5）

tasks 1.2は「すべてのタスクに適用する」と明記しており、T801からT812のすべてに及ぶ。各タスクの受け入れ条件の欄には繰り返していない。

| 条件 | 判定 |
| --- | --- |
| `docker-compose ps -a -q`が空 | 適用される。ただしT801は別プロジェクト名で動かすため、そのままでは検出できない（A-05） |
| 一時ディレクトリの削除、`$KIROCREW_SCRATCH`のコピーの削除、`/tmp`を使わない | 適用される |
| 失敗経路でも終了コードを保つ | 適用される |
| `git add`の名指し、`git commit`、`git push`、PRの禁止 | 適用される |
| `$KIROCREW_SCRATCH`の写しがコミット対象に無いことを`git status --short`で確かめる | 条件として弱い（A-09） |

## 6. 既存実装との整合（確認項目6）

planは行番号を書いていない。行番号はclarifyに集中しているので、clarifyの参照も含めて現物を確かめた。

| 参照 | 結果 |
| --- | --- |
| `scripts/scenario-lib.sh`の`scenario_path`、`wiremock_reset`、`wiremock_verify_reset` | 実在。183行、199行、212行。`scenario_path`は未定義の名前で2、宛先の食い違いで1 |
| `wiremock_count`が`scenario-lib.sh`に無く、M06とM07にある | 正しい。M06は449行、M07は346行 |
| `tests/m07-scenario-isolation.sh`の`smoke_run`、`smoke_child_signal`、`M07_NESTED` | 実在。438行、512行、248行以降 |
| `tests/m06-client-resilience.sh`の`run_smoke`（468行）、559〜565行の`slow-5000`の実機確認 | 実在 |
| `test-client/retry-lib.sh`の`apply_config_defaults`、125〜133行の既定値 | 実在。`RETRY_MAX_ATTEMPTS_429`の既定は3 |
| `test-client/entrypoint.sh`の診断ログの形式（32〜38行、55〜59行、78行、95〜96行） | 実在。plan 3.4と3.5の文字列と一致 |
| `scripts/quality-gate.sh`の74行、75行、80行 | 実在。M07の後ろが`s14`で、`[ -f ]`の読み飛ばしもある |
| `README.md`の「Testing Scenarios」と87行の参照行、`docs/シナリオ隔離.md` | 実在 |
| plan 7.1がコピーする`Dockerfile` | 存在しない。リポジトリにあるのは`Dockerfile.test-client`のみ（A-06） |
| plan 3.3の「`wiremock_count`は同じ形」 | 形は同じだが、M06は`$wiremock_url`、M07は`$smoke_wiremock_url`を使う（A-11） |
| plan 6.1の`docker-compose logs ... --tail 100`を「M07と同じ」とする点 | M07は`--tail`なし（A-11） |

## 7. スコープ確認（確認項目7）

要件の出典はIssue #8で、clarifyで本文との矛盾なしと確認済みである。

| 変更または作業 | 判定 | 根拠 |
| --- | --- | --- |
| `tests/m08-e2e-suite.sh`、`docs/E2Eテスト.md`の新規 | 範囲内 | FR-812、FR-814 |
| `README.md`の1行、`scripts/quality-gate.sh`の1語 | 範囲内 | FR-814、Q-805 |
| `q810-experiment.md`の新規とQ-810の実験（E1からE5） | 範囲内 | FR-804の期待値を決めるために必要。E2とE5は補助だが、手動で1回のみ |
| 連続2回（周2）、名前指定、アサーション失敗、リセット確認失敗、`INT`、`TERM` | 範囲内 | NFR-805、NFR-808、FR-811、FR-813 |
| Compose起動失敗の子プロセス検査 | 範囲内（任意） | FR-813に列挙がない。M07との揃えで、費用は小さい（A-10） |
| T806の「ポート3128と8080が空でなければ起動せず報告する」 | plan外（A-10） | planはU1の実験にだけポート確認を置く |
| T812（品質ゲートの実行） | 範囲内 | plan 11章にないが、コミット前の確認として妥当 |
| T810とT812の重複 | 許容 | T810は登録の判断、T812は最終ゲート。目的が異なる |

拡張とみなす項目はない。対象外（CI、`pnpm test`、実AWS、503の`Retry-After`、動的ポート）は、計画に混入していない。

## 8. 指摘事項

| ID | 重大度 | 場所 | 内容 |
| --- | --- | --- | --- |
| A-01 | High | plan.md 3.2、3.4、5.1手順4。tasks.md T803、T805。spec.md FR-804 | 受信回数の検証を外す分岐で、期待値が`wiremock=-`、実測が`wiremock=0`になり、文字列の比較が必ず不一致になる |
| A-02 | Medium | spec.md FR-807、FR-809。plan.md 5.3。tasks.md T804 | 未実行の表記（`FAIL（未実行）`、`未実行`、`NOT_RUN`）と、合否を`PASS`か`FAIL`に限る要件の食い違い |
| A-03 | Medium | plan.md 3.3、5.1手順3。tasks.md T805 | クライアント実行で`TEST_API_PATH`を渡す記述がない |
| A-04 | Medium | tasks.md T810、1.4。plan.md 10章 | 登録しない場合に`docs/E2Eテスト.md`へ書くが、T810の編集対象とファイル共有表にない |
| A-05 | Medium | tasks.md 1.2、T801 | T801の実験は`-p m08-q810`で動かすのに、残存の確認が`-p`なしの`docker-compose ps -a -q` |
| A-06 | Medium | plan.md 7.1 | 複製対象に存在しない`Dockerfile`が含まれる |
| A-07 | Low | tasks.md T808最終項目、1.4 | T808が`spec.md`と`plan.md`を直すとあるが、ファイル共有表は`spec.md`をT801のみとする |
| A-08 | Low | tasks.md T802 | 検査入口が`$KIROCREW_SCRATCH`に一時ディレクトリを置くと読める |
| A-09 | Low | tasks.md 1.2 | `git status --short`では`$KIROCREW_SCRATCH`の写しの有無が分からない |
| A-10 | Low | tasks.md T806。plan.md 6.3。spec.md FR-813 | T806のポート確認がplan外。Compose起動失敗の検査がFR-813の列挙にない |
| A-11 | Low | plan.md 3.3、6.1、6.2 | `wiremock_count`の変数名、`cd`、`--tail 100`の「M07と同じ」が実装と異なる |
| A-12 | Low | tasks.md T807、T811。spec.md NFR-801、NFR-802 | NFR-801の確認方法が曖昧。`git diff --name-only`は新規の未追跡ファイルを出さない |
| A-13 | Low | spec.md 2章、clarify.md Q-810、plan.md 7.3 | 文書間の細部の差（503の記述、観測の間隔、分岐の空白、時間の見積もり） |

### A-01 受信回数の検証を外す分岐の実測値（High）

plan 3.2の表は、「記録されない」と「揺れる」の場合、`slow-5000`の期待値を`... wiremock=- ...`にする。
一方、plan 3.4は`wiremock`の実測を「`wiremock_count <パス>`をクライアント実行の直後に読む」と定め、
読み取れない場合だけ`-`にする。WireMockが応答しているのに記録されない場合、`wiremock_count`は成功して`0`を返す。
実測は`wiremock=0`になり、期待値`wiremock=-`と等しくならず、`slow-5000`は必ず`FAIL`になる。
`unit`は`wiremock_count`をスタブにするため、スタブが`-`を返す設計なら見逃す。

2つの分岐（記録されない、揺れる）でスイートが常に失敗する。実機で初めて分かる欠陥になる。

修正案。

1. `plan.md` 3.4の表の最後に、次の段落を足す。

   `期待値の wiremock が - のシナリオでは、wiremock_count を呼ばず、実測も wiremock=- とする。`
   `期待値が数値のシナリオだけ、wiremock_count の結果を使う。`

2. `plan.md` 3.3の`run_one`の説明（「クライアント実行、実測、比較、結果の記録」）に、上の規則を1語で足す。
3. `plan.md` 5.1の手順4を「`wiremock_count`で受信回数を読む。ただし期待値が`-`のシナリオでは読まない」に直す。
4. `tasks.md` T803の`scenario_spec`の項目に「期待値の`wiremock`が`-`のとき、`parse_client`は`wiremock_count`を呼ばず`-`を出す」を足す。
5. `tasks.md` T803の`unit`の項目に「期待値が`wiremock=-`のシナリオで、`wiremock_count`が0を返しても`PASS`になる」ケースを足す。
6. `tasks.md` T801の分岐表の「記録されない」と「揺れる」の「後続への影響」に、上の規則を1文足す。

### A-02 未実行の表記（Medium）

`spec.md` FR-807は、確認に失敗したシナリオを`FAIL`（未実行）、残りを`未実行`と記録する。
FR-809は合否を`PASS`か`FAIL`に限り、最後の行に合格数と失敗数を出すとする。
`plan.md` 5.3は`NOT_RUN`を足し、失敗数に数えない。`FAIL`（未実行）の1件は、レポートの行でどう表すかが書かれていない。
最後の行の例にも未実行数がなく、5.3の「合計は実行対象の数に等しい」を例の行から確かめられない。

修正案。

1. `spec.md` FR-809の「合否（`PASS`または`FAIL`）」に「リセット確認の失敗で実行しなかったシナリオは`NOT_RUN`」を足す。
2. `plan.md` 5.3に、リセット確認に失敗したシナリオの行は`result`を`FAIL`、`actual`を`not_run`と書く旨を足す。
3. `plan.md` 5.3の最後の行の例に`not_run=0`を足し、合計の式を`passed + failed + not_run`にそろえる。
4. `tasks.md` T804に、上の形式の`unit`ケース（`FAIL`の未実行の行と、`NOT_RUN`の行を含むレポート）を足す。

### A-03 クライアント実行のパスの渡し方（Medium）

`docker-compose.yml`の`environment`に`TEST_API_PATH`はない。パスは`-e TEST_API_PATH=<パス>`で渡す必要がある（M06の`smoke`も同じ）。
`plan.md` 3.3の`run_client`と5.1の手順3は、「上書き設定を`-e 名前=値`で渡す」とだけ書く。パスは上書き設定の列にない。
実装者が列の値だけを渡すと、4シナリオとも既定の`/api/users/123`を叩き、3シナリオが失敗する。
7.2の実験の例には書いてあるが、実装の記述にはない。

修正案。

1. `plan.md` 5.1の手順3を「`-e TEST_API_PATH=<scenario_pathの結果>`と、上書き設定を`-e 名前=値`で渡す」に直す。
2. `tasks.md` T805の`run_client`の項目に同じ内容を足し、`unit`のスタブで`-e TEST_API_PATH=`の引数が渡ることを確かめる。

### A-04 T810の編集対象（Medium）

`tasks.md` T810は、登録しない場合に`docs/E2Eテスト.md`へ手動実行を書くとする。
しかし「触るファイル」は`scripts/quality-gate.sh`のみで、1.4の表も`docs/E2Eテスト.md`をT809のみとする。
`plan.md` 10章も同じ記述を持つ。T809の`unit`の文書検査が、登録しない場合の節を求めるかも決まっていない。

修正案。

1. `tasks.md` T810の「触るファイル」を「`scripts/quality-gate.sh`（登録する場合）、`docs/E2Eテスト.md`（登録しない場合）」に直す。
2. `tasks.md` 1.4の`docs/E2Eテスト.md`の行を「T809、T810（登録しない場合）」に直す。
3. T809の`unit`の文書検査は、品質ゲートの節を必須にしない。

### A-05 T801の残存確認（Medium）

T801は`docker-compose -p m08-q810`で動かし、使い捨てコピーで回収する。1.2の「`docker-compose ps -a -q`が空」は、
プロジェクト名もディレクトリも指定していないため、実験のコンテナを見ない。残っていても検出できない。

修正案。`tasks.md` 1.2の「後始末」に、T801の確認として
`docker-compose -p m08-q810 ps -a -q`が空であること（`down`の後、コピーを消す前）を足す。

### A-06 存在しない`Dockerfile`（Medium）

`plan.md` 7.1は、複製対象に`Dockerfile`と`Dockerfile.test-client`を挙げる。リポジトリには`Dockerfile.test-client`しかない。
`docker-compose.yml`の`build`も`Dockerfile.test-client`を指す。複製の手順がそのまま失敗する。

修正案。`plan.md` 7.1の複製対象から`Dockerfile`を除く。

### A-07 T808の文書変更（Low）

T808の最終項目は、観測値が130と143と異なる場合に`spec.md`のFR-813と`plan.md` 3.1、6.1を直すとする。
一方、`tasks.md` 1.4は`spec.md`の編集をT801のみとする。

修正案。1.4の`spec.md`の行を「T801、T808（観測値が異なる場合のFR-813のみ）」に直し、`plan.md`の行を足す。

### A-08 一時ディレクトリの置き場（Low）

T802は一時ディレクトリを「`$KIROCREW_SCRATCH`配下に置く」とする。コミットされる検査入口に、このセッション固有の環境変数を書く意味に読める。
M07と同じく`mktemp -d`だけを使い、置き場は実行環境の`TMPDIR`に任せるのが正しい。

修正案。T802を「`mktemp -d`で作る（置き場は実行環境の`TMPDIR`に任せ、スクリプトは`KIROCREW_SCRATCH`を参照しない）」に直す。

### A-09 コミット対象の確認（Low）

`$KIROCREW_SCRATCH`はリポジトリの外にあるため、`git status --short`に写しは出ない。この確認は常に通り、意味を持たない。

修正案。1.2を「`ls "$KIROCREW_SCRATCH"`で、作業で作ったコピーとログが残っていないこと」と、
「`git status --short`で想定外の追跡対象外ファイルがないこと」の2つに分ける。

### A-10 plan外の項目（Low）

T806の「ポート3128と8080が空いていない場合は、起動せず報告する」は、planの4.2と6.1にない。
開始前の`down --remove-orphans`と`up`の失敗が、すでに同じ状況を検出する。M07にも同じ確認はない。
Compose起動失敗の子プロセスの検査（6.3）は、`spec.md` FR-813の列挙（成功、アサーション失敗、`INT`、`TERM`）にもない。
後者は`cleanup`の分岐を確かめる実益があるため、残してよい。

修正案。T806のポート確認の項目を削るか、planに追加する。Compose起動失敗は、FR-813の列挙に「Composeの起動失敗」を足して明示する。

### A-11 既存の定義との細部（Low）

- `wiremock_count`は、M06が`$wiremock_url`、M07が`$smoke_wiremock_url`を使う。複製するときに、M08側でどの名前を使うかを決める。
  `scenario-lib.sh`の関数は`WIREMOCK_URL`を直接読む。
- M07は`cd "$ROOT"`（19行）で、`wiremock_verify_reset`の既定のディレクトリ`wiremock-scenarios/mappings`を相対で解決する。
  planに`cd`の記述がない。
- plan 5.4は、コンテナのログを`--tail 100`で出し「M07と同じ」とする。M07は`--tail`を付けていない。

修正案。plan 3.3に`cd "$ROOT"`と`smoke_wiremock_url`を使う旨を足し、5.4の「M07と同じ」を「M07に`--tail 100`を足した形」に直す。

### A-12 検証方法が曖昧な要件（Low）

- NFR-801（外部へ出ない）は、T807に「確かめる」とあるが方法がない。`smoke`の通信先が`api.example.com`とComposeの閉じたネットワークだけであることは、
  `docker-compose.yml`と`squid-config/`が不変であること（T811の`git diff`）で足りる、と明記する。
- NFR-802とplan 2章の`git diff --name-only`は、新規の未追跡ファイルを出さない。新規3ファイルの確認は`git status --short`で行う。

修正案。T807にNFR-801の根拠を1行足し、T811の変更ファイルの確認を`git status --short`と`git diff --name-only`の併用にする。

### A-13 文書間の細部（Low）

- `spec.md` 2章の「503または遅延によるタイムアウト」は、FR-804とQ-802（503は含めない）に合わせて「遅延によるタイムアウト」に直す。
- clarifyのQ-810の確認手順（直後と6秒後）は、planの7.2（1秒おきに10秒）に置き換わっている。planが優先する。
- plan 7.3の判定は、E1とE4とE3の組み合わせの一部（例: 遅れて記録され、E3の最後の確認が通る）を扱わない。
  このときは「結果が揺れる」と同じに扱い、受信回数の検証を外す、と一文足す。
- 「遅れる」の分岐では、待機がシナリオごとに最大約4秒増える。NFR-803の見積もり（約8秒）は、分岐の確定後にdocsへ反映する。
- `scenario_path`は宛先の食い違いで終了コード1を返すことがある。plan 3.1は2だけを扱う。1は`unit`の検査で別に落ちるため、
  入口では引数の誤りとしてではなく失敗（1）として扱う、と一文足す。

## 9. 判定

Criticalはない。HighはA-01の1件で、設計の方針は変わらない。実機確認の分岐の一部で、期待値と実測値の比較が成り立たない欠陥である。

| 区分 | 件数 | implementをブロックするか |
| --- | --- | --- |
| Critical | 0 | なし |
| High | 1（A-01） | 文書へ反映するまでブロックする。反映後は解消 |
| Medium | 5（A-02からA-06） | 同時に反映する。A-06はT801の最初の手順を止めるため、T801の前に直す |
| Low | 7（A-07からA-13） | ブロックしない。同時に反映する |

判定は条件付きPASSである。A-01を含む次の修正を`spec.md`、`plan.md`、`tasks.md`に反映すれば、`implement`へ進める。
この反映は、T801の結果で分岐が決まった後にもう一度`analyze`で整合を確かめる（plan 7.4）。

## implement 前に反映する修正

### spec.md

1. FR-809の合否の記述に`NOT_RUN`を足す（A-02）。
2. 2章の「503または遅延によるタイムアウト」を「遅延によるタイムアウト」に直す（A-13）。

### plan.md

1. 3.3の`run_one`と`run_client`に、`-e TEST_API_PATH=<パス>`の受け渡しと、`cd "$ROOT"`、`smoke_wiremock_url`を足す（A-03、A-11）。
2. 3.4に、期待値の`wiremock`が`-`のシナリオでは`wiremock_count`を呼ばず実測も`-`にする規則を足す（A-01）。
3. 5.1の手順3と手順4を、A-03とA-01のとおり直す。
4. 5.3に`FAIL`の未実行の行の形式と、最後の行の`not_run=`を足す（A-02）。
5. 5.4の「M07と同じ」を直す（A-11）。
6. 7.1の複製対象から`Dockerfile`を除く（A-06）。
7. 7.3に、組み合わせが分岐に当たらない場合の一文を足す（A-13）。

### tasks.md

1. 1.2の後始末に、T801の確認（`-p m08-q810`）を足す。`$KIROCREW_SCRATCH`と`git status`の確認を分ける（A-05、A-09）。
2. 1.4の共有ファイルの表を直す（A-04、A-07）。
3. T802の一時ディレクトリの記述を直す（A-08）。
4. T803に、`wiremock=-`のときの規則と`unit`ケースを足す。T801の分岐表の該当2行にも一文足す（A-01）。
5. T804に、未実行の行の`unit`ケースを足す（A-02）。
6. T805に`-e TEST_API_PATH=`の受け渡しと`unit`のスタブ確認を足す（A-03）。
7. T806のポート確認の項目を削る（A-10）。
8. T807にNFR-801の根拠を足し、T811の変更ファイルの確認を直す（A-12）。
9. T810の「触るファイル」を直す（A-04）。

### clarify.md

変更は要らない。Q-810の確認手順がplanに置き換わっていることは、planを正とする（A-13）。

## 修正の記録

A-01からA-06を、次の箇所に反映した。

| ID | 反映した箇所 |
| --- | --- |
| A-01 | `plan.md` 3.3（`run_one`）、3.4（`wiremock`が`-`の規則）、5.1手順4。`tasks.md` T801の分岐表、T803の規則と`unit`ケース |
| A-02 | `spec.md` FR-807、FR-809。`plan.md` 5.3（`FAIL`の`not_run`行、`not_run=`、合計の式）。`tasks.md` T804の`unit`ケース |
| A-03 | `plan.md` 3.3（`run_client`）、5.1手順3。`tasks.md` T805の`-e TEST_API_PATH=`とスタブ確認 |
| A-04 | `tasks.md` T810の触るファイルと登録しない場合の記述、1.4のファイル共有表 |
| A-05 | `tasks.md` 1.2の後始末（`docker-compose -p m08-q810 ps -a -q`） |
| A-06 | `plan.md` 7.1（複製対象から`Dockerfile`を除外） |
