# R01 フェーズ2 検証結果

フェーズ2（m09以外の19ファイルの44件。T-R0108〜T-R0119、T-R0151）の結果を記録する。
修正（T-R0108〜T-R0113）は実装サブエージェント（Claude Haiku 5.5）が2回のバッチ（B-1、B-2）で行い、差分の確認と検証はメインエージェントが行った。
実行環境はLinux aarch64の2コアのEC2（2026-11-07）である。AWSアカウント識別子、ARN、認証情報は記録しない。
shellcheckは、`mise install --locked`で入れたmise管理の実体（0.11.0）を`mise which shellcheck`で得て実行した。

## 1. 件数（T-R0108〜T-R0113）

| ファイル | 前 | 後 | バッチ |
| --- | ---: | ---: | --- |
| `test-client/entrypoint.sh` | 0 | 0 | B-1 |
| `scripts/e2e.sh` | 1 | 0 | B-1 |
| `tests/m02-routing-smoke.sh` | 1 | 0 | B-1 |
| `tests/m03-wiremock-scenarios.sh` | 1 | 0 | B-1 |
| `tests/m04-test-client.sh` | 1 | 0 | B-1 |
| `tests/m05-proxy-integration.sh` | 1 | 0 | B-1 |
| `scripts/e2e-lib.sh` | 7 | 0 | B-1 |
| `tests/s14-taskdef-contract.sh` | 8 | 0 | B-2 |
| `tests/m06-client-resilience.sh` | 4 | 0 | B-2 |
| `tests/m07-scenario-isolation.sh` | 3 | 0 | B-2 |
| `tests/m08-e2e-suite.sh` | 16 | 0 | B-2 |

m09以外の19ファイルを`shellcheck -s sh -S style`で数え直し、合計0件を確かめた。
`test-client/entrypoint.sh`のSC1091は、最終の`.shellcheckrc`（`external-sources=true`、`source-path=SCRIPTDIR`）では出ない。

## 2. 修正と除外（`plan.md` 4.6）

| コード | 修正 | 除外 | 内容 |
| --- | ---: | ---: | --- |
| SC2034 | 0 | 13 | `SWSC_ROOT`など。読み込み先や別のスクリプトが参照する変数で、参照元は`grep`で確かめた |
| SC2329 | 0 | 6 | `trap`の文字列や`check`の引数から名前で呼ぶ関数。参照が0件の関数は無かった |
| SC2031 | 0 | 6 | m08のサブシェルによる隔離が意図の箇所。サブシェルは外していない |
| SC2030 | 0 | 2 | 同上 |
| SC1090 | 1 | 3 | m06は`# shellcheck source=`の宣言で直した。m08の3件は自分自身を読む箇所で、宣言にするとshellcheckが120秒以上止まるため、理由付きの除外にした |
| SC2016 | 1 | 2 | s14は二重引用符へ直した。m06とm08は子のshが展開する意図 |
| SC2012 | 1 | 2 | `scripts/e2e-lib.sh`は`for`とグロブへ直した。m07とm08は`mktemp -d`の一時ディレクトリを診断表示するだけ |
| SC2086 | 0 | 2 | m06の台本と、m08の`set -- $E2E_ORDER`。どちらも固定の文字列を語に分ける意図 |
| SC2043 | 2 | 0 | m07とm08の要素が1つの`for`を、直接の記述へ直した |
| SC2154 | 0 | 1 | `trap`の文字列の中で代入して読む`_t`（誤検出） |
| SC1003 | 1 | 0 | s14の行。SC2016と同じ修正で解消した |

除外はすべて対象行の直前の`# shellcheck disable=SCxxxx # 理由`で、ファイル全体に効く先頭の除外は無い。
m08のSC1090は、`plan.md`の「読み込み先が決まるなら`source=`で宣言する」から外れる。理由は上のとおりで、フェーズ2のレビューで確かめる。

利用者の判断に上げる行は0件である（`phase-2-decisions.md`）。T-R0115は確認だけで終わり、T-R0151は省略した。

## 3. smokeとunit（T-R0116）

`scripts/e2e-lib.sh`は全smokeが読み込むため、M02〜M08のsmokeをすべて直列に実行した。

| 検査 | 結果 | 所要時間 |
| --- | --- | ---: |
| M02 smoke | passed | 14秒 |
| M03 smoke | passed | 17秒 |
| M04 smoke | passed | 13秒 |
| M05 smoke | passed | 12秒 |
| M06 smoke | 通し検査すべて通過 | 20秒 |
| M07 smoke | passed（60件） | 145秒 |
| M08 smoke | passed（30件） | 66秒 |
| M06 unit | 133件すべて通過 | 2秒 |
| M07 unit | 44件通過 | 3秒 |
| M08 unit | 19件通過 | 5秒 |
| S14 unit | 5件中5件通過 | 1秒未満 |
| M09 unit | 223件中223件通過 | 41秒 |

すべて終了コード0である。実行後の管理対象（`swsc.managed=true`）のコンテナの残りは0件である。
M07 smokeのログ末尾の`cleanup: reset failed (ignored)`は、停止後の後始末でリセットを試みたときの設計どおりの出力である（M08の`plan.md`）。

S14とM09 unitは、最初の実行で引数の付け忘れと背景での起動により実行されなかった。前面で実行し直した結果を上に記録した。

## 4. 必須レビュー（T-R0117）

2つのレビューを、1スキルに1つのサブエージェント（Claude Sonnet 5.5、effort medium、memoryとlessonsは渡さない）で、直列に行った。
対象は`sh scripts/review-snapshot.sh`で作ったスナップショットで、主対象は変更10ファイルと追加2文書である。

| レビュー | Critical | High | Medium | Low | NITS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `evidence-code-review` | 0 | 0 | 0 | 0 | 2 |
| `security-review` | 0 | 0 | 0 | 0 | 0 |

`evidence-code-review`のNITSは、除外理由の文言の誤り2件である。どちらも直した。

| 場所 | 誤り | 直した内容 |
| --- | --- | --- |
| `tests/m06-client-resilience.sh`のSC2086 | `ep_obs`の呼び出しを「上の」と書いたが、呼び出しは下にある | 「呼び出し元の`ep_obs`の引数」へ直した |
| `tests/m08-e2e-suite.sh`のSC1090,SC2031（3か所） | 「同じ部分シェルの中で変えたPATH」と書いたが、ここは親のPATHを読むだけである | 「PATHの変更は`unit_run_client_args`のサブシェルで隔離済みで、ここは親のPATHを読む」へ直した |

直した後に、2ファイルのshellcheckが0件で、M06 unit（133件）とM08 unit（19件）が通ることを確かめた。
コメントだけの変更のため、security-reviewはこの修正の後のスナップショットで1回だけ行った。

レビューで確かめた主な点は次のとおりである。

| 確認 | 結果 |
| --- | --- |
| 直した7件の挙動 | 変わらない。`ls \| head`とグロブは同じ名前順で、一致0件の分岐も同じ |
| 除外理由の事実 | 変数と関数の参照元が実在する（上のNITSを除く） |
| m08のSC1090の除外（`plan.md`からの逸脱） | 自己参照で解析しても得るものが無く、行ごとの除外のため妥当 |
| 除外の位置 | すべて対象行の直前で、ファイル先頭の除外は無い |
| 語分割とグロブ | 除外した行の入力は固定の文字列か`mktemp -d`の一時ディレクトリで、外部入力を通らない |
| S14の契約検査 | Squidを公開しない、`:ro`、許可ドメインの固定の検査力は変わらない |
| trapとロック | trapの文字列と後始末の順序は変わらない |

レビューの判定不能な範囲は、レビュアー自身によるshellcheckとテストの実行、m08の`source=`で止まる事象の再現である。

## 5. 品質ゲート（T-R0118）

レビューの修正の後に、`sh scripts/quality-gate.sh`を1回だけ実行した。所要時間は約450秒である。

| ゲート | 結果 |
| --- | --- |
| `git diff --check`（作業ツリー、ステージ、`origin/main...HEAD`） | 指摘なし |
| `npm run -s lint:md` | 0件 |
| `sh -n` | 18件すべて成功 |
| M02〜M05 smoke | すべてpassed |
| M06〜M08のunitとsmoke | すべて通過 |
| S14 unit | 5件中5件通過 |
| M09 unitとsmoke | unitは223件中223件、smokeは11件中11件通過（smokeは115秒） |
| 総合 | `quality-gate: passed` |

ゲートの後に、次も確かめた。

| 確認 | 結果 |
| --- | --- |
| m09以外の19ファイルの`shellcheck -s sh -S style` | 合計0件 |
| 検証の記録の識別情報（12桁の数字、`arn:aws`） | 0件 |
| 管理対象（`swsc.managed=true`）のコンテナの残り | 0件 |

この時点のゲートはshellcheckをまだ実行しない。ゲートへの組み込みはフェーズ4で行う。
smokeが作った`.e2e/`（`.gitignore`の対象）は、ゲートの後に削除した。
