# M07実装タスク

## 1. 進め方

`plan.md` 9章の11実装単位を、T701からT711に1対1で対応させる。品質ゲート実行をT712として追加する。
各タスクは、対応する検査が通ってから次へ進む。検査は先に失敗するケースを書いてから実装する。
リポジトリのファイルを書き換える検査は書かない（`plan.md` 10章）。

タスクと実装単位の対応は次のとおり。

| タスク | plan.md 9章の単位 |
| --- | --- |
| T701 | 1 リセット実験 |
| T702 | 2 マッピング |
| T703 | 3 検査入口の骨格 |
| T704 | 4 名前の解決 |
| T705 | 5 静的検査 |
| T706 | 6 リセットと確認 |
| T707 | 7 通し実行と対照実験 |
| T708 | 8 失敗経路 |
| T709 | 9 文書 |
| T710 | 10 品質ゲート（登録） |
| T711 | 11 最終確認 |
| T712 | 品質ゲート実行（追加） |

### 1.1 リセット実験のゲート

T701は最初に行うゲート付きタスクである。結果が出るまで、`plan.md` 5章の関数、パース方法、
`wiremock_reset`の呼び出し列を確定しない（`plan.md` 9章）。

ゲート条件は次のとおり。T701の完了報告が、この条件を満たすと明記できたときだけゲートを通過とする。

| 区分 | 条件 |
| --- | --- |
| 通過の条件1 | `reset-experiment.md`が`plan.md` 3.4の全節を含み、3.1の観測1から7が揃っている |
| 通過の条件2 | `plan.md` 3.3の値（件数と状態とジャーナルのフィールド名、`name`の有無、Q-704の反映結果）が揃っている |
| 通過の条件3 | `plan.md` 3.2の分岐が確定している（従来どおり） |
| 通過しない | `plan.md` 3.2の「代替でも戻らない」。コンテナ再起動は自分では採らず、作業を止めてユーザーに確認する |
| 通過しない | 観測が欠けている、または分岐が確定していない |

ゲートに依存するタスクは、T706、T707、T708、T709、T711、T712である。これらはゲート通過まで着手しない。
T710もT709に依存するため、ゲート通過まで着手しない。

ゲートに依存しないタスクはT702からT705である。ただし順序としてT701の後に置く。
T704とT705は`wiremock_reset`と`wiremock_verify_reset`を使わず、リセットの結果に左右される処理を書かない。

### 1.2 並列実行の可否

共有するファイルは次のとおり。

| ファイル | 編集するタスク |
| --- | --- |
| `tests/m07-scenario-isolation.sh` | T703、T704、T705、T706、T707、T708、T709 |
| `scripts/scenario-lib.sh` | T704、T705、T706 |
| `wiremock-scenarios/mappings/` 配下 | T702のみ（T701の実験は使い捨てコピーで行い、リポジトリは触らない） |
| `docs/シナリオ隔離.md`、`README.md` | T709のみ |
| `scripts/quality-gate.sh` | T710のみ |

`tests/m07-scenario-isolation.sh`を編集するT703からT709は、並列に実行しない。依存順に1つずつ進める。
T712までのすべての実通信を伴う検査は、Composeのポート3128と8080を共有するため、並列に実行しない。

並列にできるのはT702とT703だけである。編集するファイルが互いに異なり（マッピングと検査入口）、
どちらもT701の完了後に着手できる。T704はT702とT703の両方の完了を待つ。

## 2. タスク

### T701: リセット実験（ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-707、FR-709 |
| 触るファイル | `specs/M07-scenario-isolation/reset-experiment.md`（新規）。リポジトリのマッピングは書き換えない |
| 依存 | なし |
| 並列 | 不可（Composeのポートを使う。以降の全タスクのゲート） |
| 検査 | 1.1のゲート条件を満たす。リポジトリの`git status --short`が実験の前後で変わらない |

- 使い捨てコピーを`$KIROCREW_SCRATCH`配下に作り、`plan.md` 3.1のとおりに2ファイルと`name`を足す
- ポートの空き確認、プロジェクト名の明示、Colimaの`DOCKER_HOST`の設定を行う
- 手順1から7の観測と`plan.md` 3.3の値を`reset-experiment.md`に記録する
- Q-704は、コピー側の`zz-tmp.json`で確かめる
- 実験が終わったらプロジェクトを`down --remove-orphans`で回収し、コピーを削除する
- 実験と記録は同じセッションで完了する（scratchは回収されることがある）

### T702: マッピング

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-701、FR-702、FR-703、FR-704、FR-705、NFR-701 |
| 触るファイル | `wiremock-scenarios/mappings/normal-case.json`、`error-429-case.json`、`delay-100ms-case.json`、`delay-5000ms-case.json`、`error-500-then-200-1.json`（新規）、`error-500-then-200-2.json`（新規） |
| 依存 | T701 |
| 並列 | T703と並列可（編集ファイルが異なる）。T704は本タスクの完了を待つ |
| 検査 | `sh tests/m03-wiremock-scenarios.sh`が通る。`git diff`で既存4ファイルの変更が`name`の1行追加だけである |

- 既存4ファイルのトップレベルに`name`を足す（`normal`、`ratelimit-429`、`slow-100`、`slow-5000`）
- 新規2ファイルは`plan.md` 4.2の表のとおりに作る。`scenarioName`と`name`は`error-500-then-200`
- 2ファイルとも`request.method`は`GET`、`request.urlPath`は`/api/error-500-then-200`
- `__files/`は既存の`error-500.json`と`success.json`を再利用し、新しい本文は足さない
- `error-500-case.json`と`error-503-case.json`には`name`を付けない
- 1ファイル1マッピングの規約を維持する
- 2ファイルの本文と`name`の値は`reset-experiment.md`の記録から作る

### T703: 検査入口の骨格

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-710 |
| 触るファイル | `tests/m07-scenario-isolation.sh`（新規） |
| 依存 | T701 |
| 並列 | T702と並列可（編集ファイルが異なる）。T704以降は検査ファイルを共有するため不可 |
| 検査 | `docker-compose`をPATHから外して`sh tests/m07-scenario-isolation.sh unit`を実行し、Composeを呼ばずに終了する |

- `unit`と`smoke`の引数でモードを切り替える。引数なしは`smoke`と同じ
- `unit`では`docker`、`docker-compose`を呼ばず、Composeの`trap`も登録しない
- 一時ファイルは`mktemp -d`配下に置き、`trap`で削除する
- 失敗時は落ちた検査名を標準エラーに出し、非ゼロで終了する
- `smoke`は`unit`が落ちたらComposeを起動しない枠だけを置く。中身はT707とT708で足す
- 最初は失敗するケースから作る

### T704: 名前の解決

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-701、FR-702、FR-705、NFR-704 |
| 触るファイル | `scripts/scenario-lib.sh`（新規）、`tests/m07-scenario-isolation.sh` |
| 依存 | T702、T703 |
| 並列 | 不可（検査ファイルを共有。T705、T706と`scenario-lib.sh`も共有） |
| 検査 | `sh tests/m07-scenario-isolation.sh unit`の名前の解決と重複のケースが通る |

- `scenario_path`と`scenario_names`を実装する。POSIX shのみを使い、読み込み時に副作用を持たせない
- JSON解析はホストの`python3`を使い、値はコマンドライン引数で渡す。シェル展開で組み立てたコードに埋め込まない
- 5名（`normal`、`error-500-then-200`、`ratelimit-429`、`slow-100`、`slow-5000`）の宛先を検査する
- 未定義の名前は標準エラーに`unknown scenario: <名前>`と一覧を出し、終了コード2とする
- 形式違反、大文字、空文字は未定義と同じ扱いにする。標準エラーに出す名前は制御文字を除く
- 同じ名前で異なる`method`または`urlPath`を持つスタブは、終了コード1で失敗する。既定シナリオへフォールバックしない

### T705: 静的検査

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-703 |
| 触るファイル | `scripts/scenario-lib.sh`、`tests/m07-scenario-isolation.sh` |
| 依存 | T704 |
| 並列 | 不可（`scenario-lib.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m07-scenario-isolation.sh unit`の状態グループと既存マッピングのケースが通る |

- `scenario_check_static`を実装する。不正なら理由を標準エラーへ出して1を返す
- `spec.md` 5.3の6検査（状態の網羅、遷移の到達性、宛先の一致、名前の一致、部分指定、パスの重複）を実装する
- 名前の形式の検査も含める
- 不正な一時ファイルを`mktemp -d`のコピーへ足し、6検査それぞれが拒否されることを確かめる
- 既存の4ファイルの`name`と、2ファイルの構成が`plan.md` 4章のとおりであることを検査する

### T706: リセットと確認

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-707、FR-708、FR-709 |
| 触るファイル | `scripts/scenario-lib.sh`、`tests/m07-scenario-isolation.sh` |
| 依存 | T705、T701のゲート通過 |
| 並列 | 不可（`scenario-lib.sh`と検査ファイルを共有。Composeのポートも使う） |
| 検査 | `sh tests/m07-scenario-isolation.sh smoke`のリセットと確認のケースが通る |

- `wiremock_reset`と`wiremock_verify_reset`を、`reset-experiment.md`の値で固定した管理APIの呼び出し列とフィールド名で実装する
- 主経路は`POST /__admin/reset`の1回。T701で戻らなかった項目だけ、個別エンドポイントを同じ関数の中で続けて呼ぶ
- コンテナの再起動は含めない
- 確認は、マッピング件数（`mappings/*.json`のファイル数、`.gitkeep`を除く）、ジャーナル件数0、全シナリオ状態`Started`の3項目
- 読み取れない、または不一致なら、項目名と期待値と実測値を標準エラーへ出して1を返す
- 呼び出し側は`set -e`で止め、続行しない
- 確認が落ちることを、検査内のサブシェルで状態を汚してから確かめる。本番のスクリプトに注入用の分岐は入れない

### T707: 通し実行と対照実験

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-702、FR-703、FR-704、FR-705、FR-706、NFR-705 |
| 触るファイル | `tests/m07-scenario-isolation.sh` |
| 依存 | T706 |
| 並列 | 不可（検査ファイルを共有。Composeのポートも使う） |
| 検査 | `sh tests/m07-scenario-isolation.sh smoke`の`plan.md` 6.2の検査1から7と9が通る |

- `smoke`のライフサイクルをM06の`run_smoke`と同じ方式で組む（`down --remove-orphans`、`up -d --build squid wiremock`、readiness待機、`EXIT`の`trap`）
- 管理APIの`name`と`request.urlPath`が、`scenario_path`の結果と一致することを確かめる
- 対照実験として、リセットなしで`error-500-then-200`を2回呼ぶと2回目が初回から200になり、リセットを挟むと500に戻ることを示す
- M06のTest Clientを`TEST_API_PATH=/api/error-500-then-200`で実行し、`CLIENT_STATUS=200`、最終結果`success`、総試行2回を確認する
- リセットを挟んでもう一度実行し、同じ結果になることを確認する（FR-706）
- 4シナリオ（`normal`、`ratelimit-429`、`slow-100`、`slow-5000`）の応答と、Squid経由の到達を確かめる
- `ratelimit-429`で、診断ログの待機2秒と`wiremock_count`による呼び出し回数を確かめる
- 手順3から7を同じ起動で2周し、結果が同じであることを確かめる（NFR-705）

### T708: 失敗経路

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-708、FR-710 |
| 触るファイル | `tests/m07-scenario-isolation.sh` |
| 依存 | T707 |
| 並列 | 不可（検査ファイルを共有。Composeのポートも使う） |
| 検査 | `sh tests/m07-scenario-isolation.sh smoke`の失敗経路のケース（`plan.md` 6.3）が通る |

- 検査内のサブシェルで本物の検査入口を子として起動し、アサーション失敗、`INT`、`TERM`を注入する
- アサーション失敗は終了コードが元の非ゼロを保つこと、`INT`は130、`TERM`は143になることを確かめる。値は実機で観測して確定する
- どの経路でも`docker-compose ps -a -q`が空であること、一時ディレクトリが残らないことを確かめる
- 子の一時ディレクトリは`mktemp -d`で親が名前を知れる場所に作らせ、後から存在を調べる
- 子は`sleep`を前景で待たず、短い間隔のポーリングにしてシグナルに速く反応させる
- 検査全体に上限時間を設ける
- 後始末の中のリセットが失敗しても、Composeの回収を妨げないことを確かめる
- 親の`trap`でも子のコンテナと一時ディレクトリを回収する
- アサーション失敗の子の標準エラーに`cleanup: reset attempted`の記録があること
- `INT`と`TERM`の観測値が130と143と異なる場合は、観測値で`spec.md` FR-710、`plan.md` 6.2、6.3を直す

### T709: 文書

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-711、FR-712、NFR-703、NFR-706 |
| 触るファイル | `docs/シナリオ隔離.md`（新規）、`README.md`、`tests/m07-scenario-isolation.sh` |
| 依存 | T708、T701のゲート通過 |
| 並列 | 不可（検査ファイルを共有。文書だけなら他と編集ファイルは重ならないが、追加手順の検査が検査ファイルを編集する） |
| 検査 | `sh tests/m07-scenario-isolation.sh unit`の追加手順のケースが通る。`unit`で並列禁止の節と識別情報パターンの不在を確かめる。`README.md`の「Testing Scenarios」から文書へのリンクが実在する |

- `docs/シナリオ隔離.md`に、シナリオ一覧、追加手順、隔離の手順、並列禁止の理由、後始末を書く
- 追加手順は、置き場所（`wiremock-scenarios/mappings/`と`__files/`）、必須項目、状態を持つ場合の書き方、検証方法を含める
- 追加手順のファイル反映の記述は、`reset-experiment.md`の値（Q-704の反映結果）に従う
- 隔離の手順は、`reset-experiment.md`の値で固定した`wiremock_reset`の呼び出し列と、確認の3項目に従う
- 並列禁止の理由は、`spec.md` 4章の表（シナリオ状態、ジャーナル、リセット、ポートとコンテナ）に従う
- `README.md`の「Testing Scenarios」に、`docs/シナリオ隔離.md`への参照を1行足す
- 追加手順の検査は、`wiremock-scenarios/`を`mktemp -d`へコピーし、文書の手順どおりに1ファイルを足す。
  そのうえで、解決と静的検査が通ることを確かめる
- 文書と出力に、アカウントIDや認証情報を含めず、ダミー値（`api.example.com`など）だけを使う
- 相対リンクの実在と、`markdownlint`の指摘が0件であることを確かめる

### T710: 品質ゲート登録

| 項目 | 内容 |
| --- | --- |
| 要件 | （要件IDなし。`plan.md` 7.3） |
| 依存 | T709 |
| 並列 | 不可（本タスクの検査が、全タスクの成果を含むゲートを実行するため、T709の後に単独で実施） |
| 検査 | `grep -n 'm07-scenario-isolation' scripts/quality-gate.sh`で検査リストの行が見える。`git diff scripts/quality-gate.sh`が1箇所の変更だけである |

- 検査リスト（`plan.md`の時点では74行目）に`tests/m07-scenario-isolation.sh`を足す。位置はM06の後ろ
- 行番号は着手時に現物で確認する。列挙の形式は既存の行に合わせる
- `scripts/scenario-lib.sh`は`scripts/*.sh`の構文検査の対象に入るため、別の登録はしない
- ゲートの実行そのものはT712で行う

### T711: 最終確認

| 項目 | 内容 |
| --- | --- |
| 要件 | `spec.md` 7章の完了条件すべて |
| 触るファイル | なし（確認のみ。失敗があれば原因のタスクへ戻って直す） |
| 依存 | T710 |
| 並列 | 不可（Composeのポートとコンテナ名を共有するため、検査を順に実行する） |
| 検査 | 下記のコマンドが順にすべて成功する |

- `sh tests/m07-scenario-isolation.sh unit`（Composeなし）
- `sh tests/m07-scenario-isolation.sh`（引数なし、`smoke`と同じ）
- `sh tests/m03-wiremock-scenarios.sh`
- `sh tests/m06-client-resilience.sh`
- `spec.md` 7章の各項目に対応する検査があることを突き合わせる
- `docker-compose.yml`、`squid-config/`、`test-client/`に差分がないことを`git diff --stat`で確認する
- `smoke`の出力に識別情報のパターンが現れないことを確認する
- 実行後に`docker-compose ps -a -q`が空であること、`git status`にM07の想定外の変更がないことを確かめる

### T712: 品質ゲート実行

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-702、M07全体（コミット前の最終ゲート） |
| 触るファイル | なし（確認のみ） |
| 依存 | T711 |
| 並列 | 不可（全タスクの完了後に単独で実施） |
| 検査 | `sh scripts/quality-gate.sh`が成功する |

- コミットの前に実行する。失敗した場合は原因のタスクへ戻って直し、再度実行する
- 実行結果を記録する
- `docker-compose.yml`、Squid、Test Clientに差分がないこと（NFR-702）を`git diff --stat`で確認する

## 3. analyze で確定した論点

analyzeで次の3点を確定した。

| 論点 | 決定 |
| --- | --- |
| 1. T701とT702の順序 | 順序は変えない。T701は$KIROCREW_SCRATCH配下の使い捨てコピーで行い、リポジトリは触らない |
| 2. T701の結果の記録先 | `specs/M07-scenario-isolation/reset-experiment.md`に日本語で記録し、仕様と一緒にコミットする |
| 3. 要件IDの網羅 | FR-701からFR-712とNFR-701からNFR-706は、すべてタスクと検証に対応する。FR-712とNFR-706の検証はA-04で足す |

## 4. 完了条件

- [ ] T701のゲート条件（1.1）を満たし、分岐が記録されている
- [ ] T702からT712を完了している
- [ ] `sh tests/m07-scenario-isolation.sh unit`がComposeなしで通る
- [ ] `sh tests/m07-scenario-isolation.sh smoke`が通り、引数なしでも通る
- [ ] `scripts/quality-gate.sh`に`tests/m07-scenario-isolation.sh`が登録されている
- [ ] `docs/シナリオ隔離.md`があり、`README.md`の「Testing Scenarios」から参照されている
- [ ] `sh scripts/quality-gate.sh`が成功している
- [ ] `spec.md`、`plan.md`、`tasks.md`、`clarify.md`が`analyze.md`の修正どおりに直されている
