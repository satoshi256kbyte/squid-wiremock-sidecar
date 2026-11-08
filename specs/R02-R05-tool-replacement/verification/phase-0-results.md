# R02-R05 フェーズ0 検証結果（commit 0）

フェーズ0（版の宣言と導入）の結果を記録する（T-R0201〜T-R0210）。
実行環境は Linux aarch64 の 2 コアの EC2（2026-11-08）である。識別情報と利用者の絶対パスは記録しない。

## 1. 最新の版の確かめ直し（T-R0201）

`gh api repos/<owner>/<repo>/releases/latest` で確かめた。仕様の値と一致した。

| ツール | 版 | 公開日 | 仕様との一致 |
| --- | --- | --- | --- |
| actionlint | v1.7.12 | 2026-03-30 | 一致 |
| gitleaks | v8.30.1 | 2026-03-21 | 一致 |
| bats-core | v1.14.0 | 2026-07-21 | 一致 |
| jq | jq-1.8.2 | 2026-06-20 | 一致 |
| yq | v4.54.2 | 2026-11-06 | 一致 |

## 2. `mise.lock` の記録（T-R0206）

`mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64` で、6ツール（shellcheck を含む）× 4環境の記録を作った。
差分は 141 行の追加だけで、既存の shellcheck の記録は変わらなかった（削除 0 行）。
URL は、すべて公式の GitHub のリリース（bats は `github_archive` のソースのアーカイブ）である。

## 3. 取得物の完全性（T-R0207）

`mise.lock` の 24 件の sha256 を、公式の値と照合した。

| 照合の方法 | 件数 | 結果 |
| --- | ---: | --- |
| GitHub のリリース資産の `digest`（`gh api`） | 20 | 一致 |
| bats のソースのアーカイブを取得して計った SHA256 | 4 | 一致 |
| 合計 | 24 | 不一致 0 |

yq の `checksums-bsd`（SHA512）は、この照合では計っていない。SHA256 の一致だけを確かめた。

## 4. 導入と出力の形（T-R0208）

`mise install --locked` で 6 ツールを導入した（`MISE_LOCKED=1`）。結果は成功。

| ツール | `mise current` | 出力の形（`--version` など） | 版の取り出し |
| --- | --- | --- | --- |
| actionlint | 1.7.12 | `1.7.12`（`-version` を使う） | 行全体 |
| bats | 1.14.0 | `Bats 1.14.0` | 空白で区切った2番目 |
| gitleaks | 8.30.1 | `gitleaks version 8.30.1` | 最後の語 |
| jq | 1.8.2 | `jq-1.8.2` | `jq-` を取り除く（表記の対応: `1.8.2` は `jq-1.8.2`） |
| yq | 4.54.2 | `yq (https://github.com/mikefarah/yq/) version v4.54.2` | `version v` の後 |
| shellcheck | 0.11.0 | `version: 0.11.0` | 既存の方式 |

## 5. batsの動作（T-R0209）

`mise which bats` の実体で、`@test` を1件持つ一時の `.bats` を実行した。
`bin/bats` は同梱の `libexec` を相対で見つけ、`1..1` と `ok 1` を出した（終了コード 0）。
一時ファイルは、確認の後に絶対パスで削除した。

## 6. `jdx/mise-action` の `install_args`（T-R0210）

`install-args.ts` の `buildInstallCommand` は、`--locked` が既に含まれるかを確かめ（`hasLocked`）、含まれなければ足す。
`install_args: --locked` は、そのまま `install --locked` になり、重複しない。
R01 の phase-4-results.md で確かめた内容と同じ。

## 7. 未確認として残すもの

- U2 の `checksums-bsd` の SHA512 の照合は、未実施。
- macOS での導入（U14、U19 は利用者の作業）は、このフェーズでは行わない。

## 8. 必須レビューの結果（T-R0215）

| レビュー | 重大な指摘（Critical、High、Medium） | 指摘 | 対応 |
| --- | ---: | --- | --- |
| `evidence-code-review` | 0 | なし | なし |
| `security-review` | 0 | Low 1件、NITS 1件 | 下の表 |

| 指摘 | 扱い |
| --- | --- |
| Low: bats の4環境の SHA256 は、公式の digest（attestation）ではなく、初回取得時にメインが `curl` で計った値である（TOFU）。`mise.lock` の bats の行に `provenance` が無い | 許容する。bats-core の公式のソースのアーカイブであり、リリース資産の `bats-core-1.14.0.tar.gz` の値と突き合わせられれば、そちらでも確かめる。突き合わせは、次の版を上げるときに行う |
| NITS: yq の SHA512（`checksums-bsd`）が未照合 | 許容する。yq の SHA256 は公式の digest と一致している（3章）。SHA512 の照合は、後続の作業で行う |

## 9. 品質ゲート（T-R0216）

`sh scripts/quality-gate.sh` を1回実行した。結果は `quality-gate: passed`（244秒）である。

| ゲート | 結果 |
| --- | --- |
| `git diff --check`（作業ツリー、ステージ、`origin/main...HEAD`） | 指摘なし |
| shellcheck（`git ls-files -co` の `*.sh`） | 0件 |
| `npm run -s lint:md` | 0件 |
| `tests/s14-taskdef-contract.sh unit` | 5件中5件通過 |
| `tests/m09-execution-and-ci.sh unit` | 226件中226件通過 |
| `tests/m09-execution-and-ci.sh smoke` | 11件中11件通過（121秒） |

M02〜M08 の smoke は、変更範囲の判定で対象外になった（この commit が変えるのは mise、m09、文書だけ）。AGENTS.md の変更範囲の表に従った。
識別情報の検査（12桁の数字、`arn:aws`、`AKIA`）は、commit の差分と `verification/` で0件だった。
管理対象のコンテナの残りは0件である。
