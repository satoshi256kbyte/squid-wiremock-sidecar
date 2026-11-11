# エージェント向け開発ルール

このリポジトリは検証用の MVP である。仕組みを増やさず、小さく保つ。

## コミット前の確認

次の4つを実行して、すべて通ることを確かめる。

```bash
mise install --locked
git ls-files -z '*.sh' | xargs -0 "$(mise which shellcheck)" -s sh -S style --
"$(mise which actionlint)" -shellcheck "$(mise which shellcheck)" .github/workflows/e2e-test.yml
"$(mise which gitleaks)" dir . --config .gitleaks.toml --redact --no-banner --exit-code 1
npm run lint:md    # 文書を変えたときだけ。markdownlint-cli2 を直接実行する
npm run test:ci && sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000
```

`npm run test:ci` は Docker を使う。実行できない場合は、成功と書かず、未実行の理由を報告する。
セキュリティに関わる変更（認証、権限、ネットワークの境界、CI）は、コミット前にレビューを受ける。

## 言語

- ドキュメントとソースコードのコメントは日本語で書く。
- `docs/` 配下の新しいファイル名は日本語にする。

## 小さく保つ

- 新しい検査や補助のスクリプトは、一般的なツール（shellcheck、actionlint、gitleaks）で代えられないときだけ作る。
- 検査のための検査（スクリプトの中身を読む検査）は作らない。
- 仕様は `specs/MVP/spec.md` の1ファイルだけにする。分割しない。

## 一時ファイルの後始末

作業中に作った一時ファイル、ワークツリー、検証用の Docker 資源は、作業が終わったら削除する。
自分が作ったものだけを、絶対パスで消す。
