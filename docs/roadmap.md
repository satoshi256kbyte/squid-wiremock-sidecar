# ECS サイドカープロキシ E2E テスト基盤の完成ロードマップ

この文書は、実装を完了するまでのIssue単位の順番と優先度を定義する。
GitHub Issueのタイトルにある`Mxx`をロードマップID、`P0`から`P2`を優先度として扱う。

## 進め方

各Issueを一つのSpec Kit実行単位として、次の順序で進める。

1. `specify`で`specs/Mxx-<name>/spec.md`を作成する
2. `clarify`で未決事項と出力契約を解消する
3. `plan`で実装方針と検証境界を定める
4. `tasks`でIssue内の実装作業を分解する
5. `analyze`で要件、設計、タスクの対応を確認する
6. CriticalまたはHighの指摘を解消してから`implement`を実施する

プロジェクト全体の`spec.md`、`plan.md`、`tasks.md`、`analyze.md`は全体設計の基準とする。
各IssueのSpec Kit成果物は、全体設計を実装単位へ具体化する成果物として
Issueごとに分けて保存する。

## Issue一覧

| 順番 | 優先度 | Issue | 実装単位 | 依存 |
|------:|:------:|-------|----------|------|
| 01 | P0 | [M01 #1](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/1) | Compose実行基盤と3サービスの起動契約 | なし |
| 02 | P0 | [M02 #2](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/2) | Squidサイドカーの閉域ルーティング | M01 |
| 03 | P0 | [M03 #3](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/3) | WireMockシナリオのコード化 | M01 |
| 04 | P0 | [M04 #4](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/4) | プロキシ経由のTest Client | M01、M02、M03 |
| 05 | P0 | [M05 #5](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/5) | 閉域通信の統合検証 | M02、M03、M04 |
| 06 | P1 | [M06 #6](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/6) | リトライとタイムアウト | M04、M05 |
| 07 | P1 | [M07 #7](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/7) | シナリオ切り替えとテスト隔離 | M03、M05、M06 |
| 08 | P1 | [M08 #8](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/8) | 代表4シナリオのE2Eテスト | M05、M06、M07 |
| 09 | P1 | [M09 #9](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/9) | ローカル実行コマンドとGitHub Actions CI | M01、M08 |
| 10 | P2 | [M10 #10](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/10) | セットアップとトラブルシューティング文書 | M09 |
| 11 | P2 | [M11 #11](https://github.com/satoshi256kbyte/squid-wiremock-sidecar/issues/11) | ローカル・CI最終受入検証 | M08、M09、M10 |

Issue本文には、目的、Spec Kitの保存先、対象範囲、完了条件、対象外を記載している。
実装時はIssue本文をそのタスクの出力契約として扱う。

## フェーズと完了条件

### Phase 1: 閉域通信の基盤

対象はM01からM05とする。

- 3サービスをComposeで起動できる
- Test ClientからSquidを経由してWireMockへ通信できる
- 許可対象外の外部通信を成功させない
- SquidとWireMockのログで通信経路を確認できる
- 正常系と異常系のWireMock定義を外部JSONで管理できる

### Phase 2: 耐障害性とE2Eテスト

対象はM06からM08とする。

- 500、503、429を定義されたポリシーで扱える
- レスポンス遅延をタイムアウトとして判定できる
- シナリオ間でWireMockの状態が漏れない
- 正常系、リトライ、タイムアウト、レート制限の4シナリオが通る

### Phase 3: CI、文書、受入

対象はM09からM11とする。

- ローカルとGitHub Actionsで同じ入口からテストできる
- 失敗時のログを取得できる
- セットアップとトラブルシューティングを文書だけで再現できる
- ローカルとCIの最終受入結果を確認できる

## Issueの完了ルール

各Issueは、次の条件を満たしてから完了とする。

- 個別Spec Kitの`specify`から`implement`まで完了している
- Issue本文のAcceptance Criteriaをすべて確認している
- 該当するテスト、lint、設定検証を実行している
- 次のIssueが使う契約を文書化している
- 対象外と残課題をIssueまたは関連文書に残している

原則として、依存先IssueのAcceptance Criteriaが完了するまで後続Issueを開始しない。
M01完了後のM02とM03は設計上独立しているが、ロードマップ上は番号順に進める。

## 完成時の判定

M11で次を確認できれば、初期スコープの完成とする。

- `npm run start`からE2Eテスト、`npm run stop`までが再現できる
- Test Client、Squid、WireMockの3層経路が検証できる
- 外部APIへの実通信なしで4つの代表シナリオが通る
- ローカルとGitHub Actionsの両方で同じ受入条件を満たす
- HTTPSのSSL Bumpと実ECSデプロイを対象外として明示している

HTTPS対応や実ECS環境へのデプロイは、初期スコープ完了後に
別のロードマップとして起票する。
