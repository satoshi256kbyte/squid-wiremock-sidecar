# エージェント向け開発ルール

このリポジトリは検証用の MVP である。仕組みを増やさず、小さく保つ。

## コミット前の確認

次を実行して、すべて通ることを確かめる。

```bash
mise install --locked
git ls-files -z '*.sh' | xargs -0 "$(mise which shellcheck)" -s sh -S style --
"$(mise which actionlint)" -shellcheck "$(mise which shellcheck)" .github/workflows/e2e-test.yml
"$(mise which gitleaks)" dir . --config .gitleaks.toml --redact --no-banner --exit-code 1
npm run lint:md    # 文書を変えたときだけ。markdownlint-cli2 を直接実行する
npm ci --prefix cdk && npm run typecheck --prefix cdk && npm run synth --prefix cdk && sh scripts/e2e.sh check-cdk   # cdk/ か雛形を変えたときだけ
npm run test:ci && sh scripts/e2e.sh test:ci normal slow-100 error-500-then-200 error-500 error-503 ratelimit-429 slow-5000
```

`npm run test:ci` は Docker を使う。実行できない場合は、成功と書かず、未実行の理由を報告する。
セキュリティに関わる変更（認証、権限、ネットワークの境界、CI）は、コミット前にレビューを受ける。

## 言語

- ドキュメントとソースコードのコメントは日本語で書く。
- `docs/` 配下のファイル名は、すべて日本語にする。ルート直下の `README.md`、`AGENTS.md`、`ARCHITECTURE.md` は英語のままにする。

## 文書の置き場

- 構成、技術スタック、公開範囲、設計判断は `ARCHITECTURE.md` に書く。
- テストの方式、実行方法、シナリオ、AWS での確認は `docs/テスト方式.md` に書く。
- 新しい文書を作る前に、上の2つと `docs/AWSへのデプロイ.md` に足せないかを考える。同じ内容を複数の文書に書かない。

## 小さく保つ

- 新しい検査や補助のスクリプトは、一般的なツール（shellcheck、actionlint、gitleaks）で代えられないときだけ作る。
- 検査のための検査（スクリプトの中身を読む検査）は作らない。
- 仕様は `specs/MVP/spec.md` の1ファイルだけにする。分割しない。

## 一時ファイルの後始末

作業中に作った一時ファイル、ワークツリー、検証用の Docker 資源は、作業が終わったら削除する。
自分が作ったものだけを、絶対パスで消す。
