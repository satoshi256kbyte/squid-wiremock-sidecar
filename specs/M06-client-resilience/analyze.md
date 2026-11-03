# M06 analyze結果

## 1. 要件カバレッジ

`spec.md`のFR-601からFR-611、NFR-601からNFR-605を、`tasks.md`のタスクと検証に突き合わせた。

| 要件 | 設計（plan.md） | タスク | 検証 | 判定 |
| --- | --- | --- | --- | --- |
| FR-601 500/503の指数バックオフ | 3.1、3.3 | T602、T606 | unit（待機列1,2,4）、entrypoint | PASS |
| FR-602 429の別ポリシー | 3.1、3.3 | T602、T606 | 429と500の混在 | PASS |
| FR-603 Retry-After | 3.1 | T603、T606 | `parse_retry_after`、切り詰め | 条件付き（A-01） |
| FR-604 429の既定待機 | 3.1 | T602、T606 | 値なしで既定待機、増加しない | PASS |
| FR-605 2種のタイムアウト | 3.4 | T607 | スタブの引数記録のみ | 条件付き（A-04） |
| FR-606 timeoutの終端結果 | 3.3、3.5 | T607 | rc=28、stdout空、sleep 0回 | PASS |
| FR-607 設定検証 | 3.1、3.2 | T604、T605 | 7変数、検査順、通信前停止 | PASS |
| FR-608 試行ごとの診断ログ | 3.5 | T608 | 標準エラーの形式 | PASS |
| FR-609 最終結果3値 | 3.3、3.5 | T606、T608 | 3値の固定 | 条件付き（A-08） |
| FR-610 対象外は1回で返す | 3.3 | T602、T606 | 200、301、404、501、502、504 | PASS |
| FR-611 上限到達で終了コード0 | 3.3 | T606 | 回数0を含む | PASS |
| NFR-601 M04出力契約 | 3.5 | T605、T610 | M04スモーク、stdout純度 | PASS |
| NFR-602 直接通信しない | 3.2、3.4 | T605 | `proxy_not_configured`のみ | 条件付き（A-09） |
| NFR-603 M01〜M03不変 | 5 | T609、T613 | `git diff --stat` | PASS |
| NFR-604 標準出力2行のみ | 3.5 | T608 | 全ケースでCLIENT_DIAG不在 | PASS |
| NFR-605 実通信なしの検証 | 4、6 | T601、T609、T611 | unit、smoke | 不整合（A-02） |

`spec.md` 7章の完了条件12項目は、すべて少なくとも1つのタスクと検査に対応する。
ただし「接続タイムアウトとレスポンスタイムアウトが動作し」は、スタブの引数確認だけで実通信の検証がない（A-04）。

## 2. 矛盾の確認

`spec.md`、`clarify.md`、`plan.md`、`tasks.md`の間で、次の食い違いを確認した。
上記以外の記述（環境変数名、既定値、終了コード、`CLIENT_ERROR`の識別子、検査順、カウンター独立）は一致している。

| 項目 | spec.md | plan.md / tasks.md |
| --- | --- | --- |
| 検査ファイル | NFR-605は`tests/m06-retry-unit.sh`と`tests/m06-retry-entrypoint.sh` | `tests/m06-client-resilience.sh`の1つ |
| 7桁以上の`Retry-After` | FR-603の字面では秒数形式に一致し、上限超過として切り詰め対象 | 不在扱い（既定待機を使う） |
| 総試行回数 | 4章は「最大N+1回」 | 3.3は5xxと429のカウンターが独立で、混在時はN+1を超える |

## 3. スコープ確認（Issue #6）

Issue #6の対象は、最大リトライ回数、指数バックオフ、500/503と429の違い、`Retry-After`、2種のタイムアウト、診断ログ、
環境変数設定、境界値の単体検証、Spec Kit成果物である。M06の計画は次の変更を含み、いずれもIssueの範囲内と判定した。

| 変更 | 判定 | 根拠 |
| --- | --- | --- |
| `test-client/retry-lib.sh`（新規）と`entrypoint.sh`の変更 | 範囲内 | 単体テスト要件を満たす関数分離 |
| `Dockerfile.test-client`のCOPY追加 | 範囲内 | `retry-lib.sh`をコンテナへ入れるために必須 |
| `tests/m04-test-client.sh`の1行追加 | 範囲内 | 既定でリトライ有効にした結果、約7秒遅れるのを避ける最小変更。検査行は不変 |
| `invalid_config`と終了コード78 | 範囲内 | 「環境変数で設定できる」の不正値の扱い |
| WireMock呼び出し数のスモーク | 範囲内 | `POST /__admin/requests/count`の読み取りのみ。M03は不変 |

拡張とみなす項目はない。次の対象外は計画に混入していない。

- 503の`Retry-After`、HTTP日付、ジッター、サーキットブレーカー、タイムアウトのリトライ
- Squid、WireMock、Composeの設定変更、WireMockシナリオによるリトライ成功の再現

A-04で追加する`/api/slow-5000`のスモークは、Issueの「遅延応答のタイムアウト」に対応し、M03のマッピングを変えない。

## 4. 指摘事項

| ID | 重大度 | 場所 | 内容 |
| --- | --- | --- | --- |
| A-01 | High（解決済み） | plan.md 3.1「Retry-Afterの解析」、4.1、7章末行。tasks.md T603、T606、3章論点2。spec.md FR-603、7章 | 7桁以上の`Retry-After`の扱い |
| A-02 | High（解決済み） | spec.md NFR-605。clarify.md 論点8の構成表。plan.md 6章末尾。tasks.md 3章論点1 | 検査ファイル構成の不一致 |
| A-03 | Medium | plan.md 6章表。tasks.md T601、T611。`scripts/quality-gate.sh` | 品質ゲートが`smoke`を実行しない |
| A-04 | Medium | plan.md 4.2、4.3。tasks.md T607、T611。spec.md 7章 | タイムアウトの実通信検証がない |
| A-05 | Medium | plan.md 7章3行目。tasks.md T611 | alpineのbusybox上で解析を確認する手順がない |
| A-06 | Medium | spec.md FR-603、FR-606、FR-611、4章、7章の「要確認」 | 利用者未確認の5判断が残っている |
| A-07 | Low | spec.md 4章「総試行回数は最大N+1回」 | 5xxと429が混在すると成り立たない |
| A-08 | Low | plan.md 3.5の形式表 | `result=success`の行の例がない |
| A-09 | Low | plan.md 4.2のcurlオプション行。tasks.md T607 | `--proxy`と`--noproxy ''`の維持を検査しない |
| A-10 | Low | tests/m04-test-client.sh 65行目。tasks.md T608 | M04の文字列検査は`entrypoint.sh`だけを見る |

### A-01 7桁以上のRetry-After（High、解決済み）

解決: `spec.md` FR-603と7章の境界値、`plan.md` 3.1「Retry-Afterの解析」と4.1と7章、`tasks.md` T603、T606、3章に反映した。

`spec.md` FR-603は、秒数形式`^[0-9]+$`ならその秒数を待機に使い、上限超過は`RETRY_MAX_WAIT_SECONDS`へ切り詰めると定める。
7桁以上の数字列は`^[0-9]+$`に一致するので、字面どおりなら「上限超過」であり「不在」ではない。
`plan.md`は7桁以上を不在扱いにしており、FR-603と食い違う。根拠は「`spec.md` 7章が並べているため」だが、
7章の項目は境界値の列挙であり、扱いを定めてはいない。

不在扱いにすると、サーバーが「非常に長く待て」と指示しているのに2秒で再試行する。
レート制限の意図に反し、Retry-Afterの尊重（Issue #6の対象）を損なう。
6桁の制限は設定値の規則であり、HTTPヘッダーには適用しない。

決定は次のとおり。`spec.md`に明記する。

| 規則 | 内容 |
| --- | --- |
| 判定 | 前後の空白とCRを除いた値が`^[0-9]+$`なら秒数形式。桁数は問わない |
| 正規化 | 先頭の0をすべて除く。すべて0なら0。除いた後の桁数で判定する |
| 6桁以内 | その値を使う。`RETRY_MAX_WAIT_SECONDS`を超えれば切り詰める（`capped=1`） |
| 7桁以上 | 上限超過として扱い、待機は`RETRY_MAX_WAIT_SECONDS`、`capped=1`。`RETRY_MAX_WAIT_SECONDS`は6桁以内なので、常に上限を超える |
| 算術 | 桁数の比較だけで判定し、`$(( ))`に渡さない。桁あふれを起こさない |
| 診断ログ | サーバー指定値は`retry_after=1000000`に飽和して出す。長大な値をそのまま出さない |
| 不在扱いのまま | 空、負数、小数、HTTP日付、数字以外を含む値、ヘッダーなし |

`parse_retry_after`は7桁以上のとき`1000000`を出力して0を返す。`resolve_429_wait`は変更不要で、
`1000000`が上限（最大999999）を超えるため切り詰めフラグ1を返す。
`0000005`のように先頭の0で7桁以上に見える値は、正規化後の`5`として扱う。

### A-02 検査ファイルの構成（High、解決済み）

解決: `spec.md` NFR-605、`clarify.md` 論点8の構成表、`plan.md` 2章と6章、`tasks.md` 3章と4章の完了条件に反映した。

`spec.md` NFR-605は2ファイル（`tests/m06-retry-unit.sh`、`tests/m06-retry-entrypoint.sh`）を名指しする。
`clarify.md`論点8の構成表も2ファイルである。`plan.md` 6章と`tasks.md`全体は`tests/m06-client-resilience.sh`の1つを前提とし、
`tasks.md` T601からT613はその1ファイルに依存している。成果物の間で契約が割れており、`spec.md`は要件の根拠なので放置できない。

決定は1ファイル（`tests/m06-client-resilience.sh`）に統一する。理由は次のとおり。

- M02からM05は、マイルストーンごとに1つの`tests/m0N-*.sh`を持ち、`scripts/quality-gate.sh`が`tests/m0*.sh`を1つずつ実行する
- 引数`unit`、`smoke`でComposeの有無を分けられ、ライフサイクルの規則を1か所に置ける
- Issue #6のスコープ判断（Spec Kit成果物とテストの最小構成）に合う
- 2ファイルにすると、T601からT608の並列不可の規則は同じままで、入口ファイルが増えるだけで得るものがない

変更が必要なファイルは次のとおり（`analyze`では編集しない）。

| ファイル | 変更内容 |
| --- | --- |
| `specs/M06-client-resilience/spec.md` | NFR-605の検査ファイル名を1ファイルに直す |
| `specs/M06-client-resilience/clarify.md` | 論点8の構成表の2行を1行に直す（決定の記録を実装と揃える） |
| `specs/M06-client-resilience/plan.md` | 6章末尾の未決の段落を、解決済みの記述に置き換える |
| `specs/M06-client-resilience/tasks.md` | 3章の論点1を解決済みに直す。完了条件の最終項目を直す |

実装側のファイルは`tests/m06-client-resilience.sh`のみで、`plan.md` 2章の変更ファイル一覧は変わらない。

### A-03 品質ゲートがsmokeを実行しない（Medium）

`scripts/quality-gate.sh`は`tests/m0*.sh`を引数なしの`sh "$test"`で実行する。
`plan.md` 6章は引数なしを`unit`（Compose不要）にしているため、ゲートでは`smoke`が一度も走らない。
`spec.md` 7章の「`retry-lib.sh`の存在確認がComposeスモークテストに含まれる」は、手動のT611とT612でしか確認されない。
M02からM05は引数なしで全検査を行うので、M06だけ慣習から外れる。

決定は、引数なしを`smoke`（`unit`を含む全検査）にし、Composeを使わない実行は`unit`を明示する。
`scripts/quality-gate.sh`は変更しない。`unit`の「`docker-compose`をPATHから外しても通る」という前提はそのまま保つ。

### A-04 タイムアウトの実通信検証（Medium）

FR-605とFR-606は、スタブの`curl`が終了コード28を返す前提でしか検証されない。
`--max-time`が実際にSquid経由の遅延応答を打ち切ることは、どの検査でも確認されない。
M03には`/api/slow-5000`（固定遅延5000ミリ秒）があり、M03のマッピングを変えずに使える。

`smoke`に次を追加する。`RESPONSE_TIMEOUT_SECONDS=1`で`/api/slow-5000`を呼び、
標準エラーに`CLIENT_ERROR=timeout`、標準出力が空、終了コード28であることを確認する。所要は約1秒で、リトライは発生しない。

### A-05 busybox上の解析確認（Medium）

`plan.md` 7章は「スモークでもalpine上で同じ解析が通ることを確認する」を対策にしているが、`tasks.md` T611にその手順がない。
`parse_retry_after`は`awk`、先頭0の除去は`sed`に依存し、単体検査はホストのGNU/BSD版で走る。
`smoke`に、コンテナ内で`retry-lib.sh`を読み込み、CR付きの`Retry-After`と7桁以上の値を`parse_retry_after`に渡す検査を追加する。

### A-06 利用者未確認の判断（Medium）

`spec.md`に「要確認」が付いた判断が残っている。

| 判断 | 場所 |
| --- | --- |
| リトライを既定で有効にする | 4章 |
| タイムアウトの`CLIENT_ERROR`を`timeout`にする | FR-606 |
| 上限到達後も終了コード0 | FR-611 |
| M04スモークに`RETRY_BACKOFF_BASE_SECONDS=0`を足す | 2章、7章 |
| `Retry-After`の上限への切り詰め | FR-603、7章 |

いずれも`clarify.md`の推奨既定どおりで進められ、互換性への影響は`clarify.md`に記録済みである。
実装は止めず、推奨既定で進める。PRの説明にこの5判断を列挙し、レビューで確認を受ける。

### A-07 総試行回数（Low）

`spec.md` 4章は「総試行回数は最大N+1回」とするが、5xxと429のカウンターは独立なので、混在時の最大は
`N_5xx + N_429 + 1`回になる。`plan.md` 3.3は独立カウンターで正しい。`spec.md`の記述を種別ごとの上限と明記する。

### A-08 成功時の最終結果行（Low）

`plan.md` 3.5の形式表に`result=success`の行がない。FR-609とT608は3値の固定を要求するので、例を足す。
`CLIENT_DIAG result=success attempts=1 status=200`とする。

### A-09 プロキシ強制オプションの維持（Low）

NFR-602の根拠は`--noproxy ''`と`--proxy "$HTTP_PROXY"`の維持である。リトライ化でcurlの呼び出しを組み替えるため、
退行しやすい。T607のスタブ引数記録の検査に、この2つを足す。

### A-10 M04の文字列検査（Low）

`tests/m04-test-client.sh`は`entrypoint.sh`に`wiremock`や`:8080`が含まれないことを検査する。
新規の`retry-lib.sh`は検査対象外である。リトライの実装とコメントに、これらの文字列を入れない。T608の確認項目に1行足す。

## 5. 判定

Criticalはない。HighはA-01とA-02の2件で、いずれも文書の食い違いであり、実装の設計変更は伴わない。

| 区分 | 件数 | implementをブロックするか |
| --- | --- | --- |
| Critical | 0 | なし |
| High | 2（A-01、A-02） | 文書へ反映するまでブロックする。反映後は解消 |
| Medium | 4（A-03からA-06） | ブロックしない。A-03からA-05は同時に反映する。A-06はPRで周知する |
| Low | 4（A-07からA-10） | ブロックしない。同時に反映する |

判定は条件付きPASSである。次節の修正を`spec.md`、`plan.md`、`tasks.md`、`clarify.md`に反映すれば、`implement`へ進める。

## implement 前に反映する修正

### spec.md

1. NFR-605の本文を次に置き換える。

   次の文を、置き換え後の本文とする。

   - リトライの待機時間計算と対象判定を、実通信なしで検証できる。
   - 関数の単体検査とスタブ`curl`/`sleep`によるentrypoint検査は、`tests/m06-client-resilience.sh`の`unit`モードで行う。
   - Composeスモークは同ファイルの`smoke`モードで行う（clarify決定、analyzeで1ファイルに統一）。
   - 本番スクリプトにテスト専用の分岐を持ち込まず、POSIX shで書く。

2. FR-603の「HTTP日付、負数、空、小数は存在しないものとして扱い、FR-604の既定待機を使う。」を次に置き換える。

   `HTTP日付、負数、空、小数、数字以外を含む値は存在しないものとして扱い、FR-604の既定待機を使う。先頭の0を除いた桁数が7桁以上の数字列は秒数形式に一致するため上限超過として扱い、`RETRY_MAX_WAIT_SECONDS`へ切り詰める（診断ログのサーバー指定値は`1000000`に飽和して出す）。`

3. 7章の境界値の項目を次に置き換える。

   `リトライ回数0と1、待機上限、`Retry-After`の0秒と上限超過、7桁以上（上限へ切り詰め）、空文字・形式不正（既定待機）の境界値が単体レベルで検証されている`

4. 7章の「接続タイムアウトとレスポンスタイムアウトが動作し」の項目末尾に「（遅延応答`/api/slow-5000`で実通信も確認する）」を追記する。

5. 4章の「最大リトライ回数Nは初回試行に加えてN回再試行する意味で、総試行回数は最大N+1回とする。」の後に次を追記する。

   `500/503と429が混在する場合は、各カウンターが独立なので、総試行回数は最大で`N_5xx + N_429 + 1`回になる。`

### plan.md

1. 2章の変更ファイル表で、`tests/m06-client-resilience.sh`の変更内容を「新規。M06の検査入口。引数なしは`smoke`と同じ全検査、`unit`はCompose不要」に直す。
2. 3.1「Retry-Afterの解析」の最後の2項目と末尾の段落（「7桁以上を不在扱いにするのは…`analyze`で`spec.md`と照合する。」）を、次に置き換える。
   - 採用した値が`^[0-9]+$`なら、先頭の0を除去する。除去後が7桁以上なら`1000000`を出力して0を返す
   - 6桁以内なら除去後の値を出力して0を返す。桁数の比較だけで判定し、算術に渡さない
   - 空、負数、小数、HTTP日付、数字以外を含む値、ヘッダーなしは不在と同じ扱いにして終了コード1を返す
   - 末尾の段落: 「7桁以上は秒数形式に一致するため、不在扱いにせず上限超過として扱う（`spec.md` FR-603、`analyze` A-01）。`resolve_429_wait`は`1000000`が上限を超えるので切り詰めフラグ1を返す」
3. 3.5の形式表に、最終結果の行として`CLIENT_DIAG result=success attempts=1 status=200`を追加する。
4. 4.1の表で、`parse_retry_after`（不在扱い）の「7桁以上」を削除し、次の行を追加する。

   `parse_retry_after`（飽和）: 999999は999999、1000000と20桁の数字列は1000000、`0000005`は5、`0000000`は0

5. 4.2の「curlオプション」の行を「記録した引数に`--connect-timeout`、`--max-time`が設定値で入り、`--noproxy ''`と`--proxy`が維持されている」に直す。
6. 4.3の表に次の2行を追加する。

   | 検査 | 場所 | 内容 |
   | --- | --- | --- |
   | タイムアウトの実通信 | `tests/m06-client-resilience.sh`のスモークモード | `RESPONSE_TIMEOUT_SECONDS=1`で`/api/slow-5000`を呼び、`CLIENT_ERROR=timeout`、標準出力が空、終了コード28を確認する |
   | busybox上の解析 | 同上 | コンテナ内で`retry-lib.sh`を読み込み、CR付きの`Retry-After`と7桁以上の値を`parse_retry_after`に渡して期待値を確認する |

7. 6章の表を次に直す。

   | 引数 | 内容 | Compose |
   | --- | --- | --- |
   | `unit` | 単体検査（4.1）とentrypoint検査（4.2） | 起動しない。`docker`、`docker-compose`を呼ばない |
   | なし、または`smoke` | `unit`に加えて4.3のM06分を実行する | 起動する |

   続く規則の1項目目の「`unit`では」は変えない。表の下に「品質ゲートは引数なしで実行するため、`smoke`が実行される」を足す。
8. 6章末尾の段落（「spec.mdのNFR-605は検査ファイル名を…決める。」）を次に置き換える。

   `NFR-605の検査ファイルは、analyzeの決定により`tests/m06-client-resilience.sh`の1つに統一した。spec.mdのNFR-605も同じ記述に直す。`

9. 7章の最終行（7桁以上の`Retry-After`）を次に置き換える。

   `| 7桁以上の`Retry-After`の扱いがspec.mdと食い違う | 上限超過として切り詰める方式に統一し、桁数の比較だけで判定する。単体検査とbusyboxの検査に入れる |`
10. 8章の11行目（M06スモーク）の内容に「タイムアウトの実通信、busybox上の解析」を追記する。

### tasks.md

1. 1章の冒頭の対応表は変更しない。T601の説明で、「`unit`（既定）と`smoke`の引数でモードを切り替える」を「`unit`と`smoke`の引数でモードを切り替える。引数なしは`smoke`と同じ」に直す。検査の列は`docker-compose`をPATHから外して`unit`を指定した実行のままにする。
2. T603の最後の項目を次に置き換える。
   - 7桁以上は上限超過として`1000000`を出力して0を返す。`0000005`は5、`0000000`は0、20桁の数字列は1000000とする
   - 不在扱い（終了コード1）の列挙から「7桁以上」を外す
3. T603の有効値の項目に、999999（6桁の最大）を加える。
4. T606の429の検査に「`Retry-After`が7桁以上で、待機が上限に切り詰められ`capped=1`」を加える。
5. T607の最後の項目を「スタブが記録した引数に、2つのタイムアウトオプションが設定値で入り、`--noproxy ''`と`--proxy`が維持されていることを確認する」に直す。
6. T608に「`retry-lib.sh`と`entrypoint.sh`に`wiremock`と`:8080`の文字列がないことを確認する」と「`result=success`の行を出す」を加える。
7. T611に次の項目を加える。
   - `/api/slow-5000`に`RESPONSE_TIMEOUT_SECONDS=1`を指定し、`CLIENT_ERROR=timeout`、標準出力が空、終了コード28を確認する
   - コンテナ内で`retry-lib.sh`を読み込み、CR付きと7桁以上の`Retry-After`を`parse_retry_after`に渡して期待値を確認する
   - 検査欄の最後に「引数なしの`sh tests/m06-client-resilience.sh`も通る」を足す
8. T612の検査欄の4コマンドのうち、1つ目は`sh tests/m06-client-resilience.sh unit`、2つ目は引数なしの`sh tests/m06-client-resilience.sh`にする。
9. T613の依存から「、および「analyze で確定する論点」の解消」を削除する。
10. 3章「analyze で確定する論点」の表と、続く段落を次の記述に置き換える。

    `analyzeで次の2点を確定した。`

    | 論点 | 決定 |
    | --- | --- |
    | 1. NFR-605の検査ファイル構成 | `tests/m06-client-resilience.sh`の1ファイルに統一。`spec.md`のNFR-605を直す |
    | 2. 7桁以上の`Retry-After` | 上限超過として`RETRY_MAX_WAIT_SECONDS`へ切り詰める。`spec.md`のFR-603に明記する |

11. 4章の最後の完了条件「「analyze で確定する論点」の2点が`analyze`で解消されている」を削除する。代わりに「`spec.md`、`plan.md`、`clarify.md`が`analyze.md`の修正どおりに直されている」を置く。

### clarify.md

1. 論点8の構成表で、`tests/m06-retry-unit.sh`と`tests/m06-retry-entrypoint.sh`の2行を、次の1行に置き換える。

   | ファイル | 役割 |
   | --- | --- |
   | `tests/m06-client-resilience.sh` | `unit`で関数の単体検査とスタブのentrypoint検査、`smoke`でComposeスモーク。実通信は`smoke`だけ |

2. 論点2の補足にある「M06専用のスモークテスト（`tests/m06-*.sh`）は別ファイルとし」を、
   「M06専用のスモークは`tests/m06-client-resilience.sh`の`smoke`モードとし、M04のテストとは分ける」に直す。
