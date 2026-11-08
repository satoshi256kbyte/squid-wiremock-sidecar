# R01 フェーズ1 検証結果

フェーズ1（版の宣言。T-R0101〜T-R0107、T-R0150）の結果を記録する。
実装（T-R0101）はサブエージェント（Claude Haiku 5.5）、ほかの確認はメインエージェントが行った。
実行環境はLinux aarch64の2コアのEC2（2026-11-07）である。AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 変更範囲

| ファイル | 内容 |
| --- | --- |
| `mise.toml`（新規） | `min_version = "2026.11.3"`と、`[tools]`の`shellcheck = "0.11.0"`だけを持つ（NFR-R0109） |
| `.shellcheckrc`（新規） | `shell=sh`、`severity=style`、`external-sources=true`、`source-path=SCRIPTDIR`の4行だけを持つ。`disable=`は無い（FR-R0108） |
| `mise.lock`（新規） | `mise lock --platform linux-x64,linux-arm64,macos-x64,macos-arm64`で作った。4つの環境のURLとSHA256を持つ |

この時点の品質ゲートは`sh -n`のままである。`scripts/`、`tests/`、`.github/`は変えていない。

## 2. `mise.lock`の照合（T-R0102、T-R0103）

`mise.toml`の内容を確かめてから、`mise trust`を実行した。backendは`aqua:koalaman/shellcheck`、`lockfile_version`は4である。

| 環境 | URL（公式のGitHubリリースの資産） | SHA256 | 照合元との一致 |
| --- | --- | --- | --- |
| linux-arm64 | `.../v0.11.0/shellcheck-v0.11.0.linux.aarch64.tar.xz` | `12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588` | GitHub APIの`digest`と一致。公式のバイナリを直接ダウンロードして計った値とも一致 |
| linux-x64 | `.../v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz` | `8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198` | GitHub APIの`digest`と一致 |
| macos-arm64 | `.../v0.11.0/shellcheck-v0.11.0.darwin.aarch64.tar.xz` | `56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79` | GitHub APIの`digest`と一致 |
| macos-x64 | `.../v0.11.0/shellcheck-v0.11.0.darwin.x86_64.tar.xz` | `3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6` | GitHub APIの`digest`と一致 |

URLの`...`は`https://github.com/koalaman/shellcheck/releases/download`である。
`mise.lock`の`checksum_source`は`mise-versions`であり、照合はmiseと別の情報源（GitHub APIのリリース資産の`digest`）で行った。
リポジトリで作った`mise.lock`は、plan作成時に照合した見本と1文字も違わない。

mise本体の検証の方法は次のとおりとする（NFR-R0110）。

| 環境 | 方法 |
| --- | --- |
| CI | `jdx/mise-action`の`version`で版を、`sha256`で本体のSHA256を固定する。actionのソースはminisignの署名も確かめる |
| ローカル | 公式のバイナリを取得し、固定の値（下の表）と照合してから置く。同じリリースの`SHASUMS256.txt`だけには頼らない |

mise 2026.11.3の公式のSHA256は次のとおりである（2026-11-07に`SHASUMS256.txt`から取得）。この環境のmise本体は`linux-arm64`の値と一致した。

| 環境 | SHA256 |
| --- | --- |
| linux-x64 | `c2f7e814cb39f60b7f67a0ff36cb805e94128bf2dff09d175309d0f095b8cc3b` |
| linux-arm64 | `a9a2a66bbbe87ea9cc849e1f006606ae2b34f3d3ba56a54d5cd5d64b6557d164` |
| macos-x64 | `49f32abd93f54147af0599a1c9583d2092df8e7250c9fe635783a7932c4087ef` |
| macos-arm64 | `6d39119ab914c54ab865204dee9337c71b83a7ed1e730f663c2fc3453e38fe9c` |

## 3. 導入と失敗の確認（T-R0104）

`MISE_DATA_DIR`と`MISE_CACHE_DIR`をスクラッチの一時ディレクトリへ向けて、利用者の環境に影響させずに確かめた。

| 確認 | コマンド | 結果 |
| --- | --- | --- |
| 導入 | `MISE_LOCKED=1 mise install --locked` | 終了コード0、約1秒 |
| 期待する版 | `mise current shellcheck` | `0.11.0` |
| 実体 | `mise which shellcheck`の実体の`--version` | `version: 0.11.0`。実体はmiseのデータディレクトリの中にある |
| lockに無い版 | 複製の`mise.toml`を`0.10.0`にして`mise install --locked` | 終了コード1、`shellcheck@0.10.0 is not in the lockfile` |
| チェックサムの不一致 | 複製の`mise.lock`のlinux-arm64のSHA256を書き換えて`mise install --locked` | 終了コード1、`Checksum mismatch` |

失敗の2件は、リポジトリの外の複製で確かめ、リポジトリの`mise.toml`と`mise.lock`は書き換えていない。
複製に付けた`mise trust`の記録は`mise trust --untrust`で外した。
複製、`MISE_DATA_DIR`、`MISE_CACHE_DIR`に使ったスクラッチの一時ディレクトリは、絶対パスを指定して削除した。

## 4. 文書の一致（T-R0150）

| 文書 | `mise which shellcheck` | `mise current shellcheck` | `mise exec -- shellcheck`の記述 |
| --- | ---: | ---: | --- |
| `spec.md` | 2 | 1 | 無し |
| `clarify.md` | 2 | 2 | Q-R0110の「`mise exec`は使わず」の1か所（使わない理由） |
| `plan.md` | 8 | 6 | 1.1節の事実の行の1か所（使わない理由） |

未導入の`mise exec`がPATH上の別のshellcheckで成功する事実は、3つの文書に理由として書かれている。
実行方法として`mise exec -- shellcheck`を使う記述は残っていない。

## 5. 必須レビュー（T-R0105）

2つのレビューを、1スキルに1つのサブエージェント（Claude Sonnet 5.5、effort medium、memoryとlessonsは渡さない）で、直列に行った。
対象は`sh scripts/review-snapshot.sh`で作ったスナップショットで、主対象は本フェーズの新規4ファイルである。

| レビュー | Critical | High | Medium | Low | 要確認 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `evidence-code-review` | 0 | 0 | 0 | 0 | 0 |
| `security-review` | 0 | 0 | 0 | 1 | 1 |

`security-review`の1回目は、ファイルを読む道具が無いエージェントで起動したため、スキル本文を読めず、正式な結果として扱わなかった。
道具のあるエージェントで同じ依頼を再実行し、その結果を上の表に記録した。

`security-review`の指摘は、どちらもコミットのブロッカーではない。後続のフェーズで次のように扱う。

| 指摘 | 内容 | 扱い |
| --- | --- | --- |
| Low | ロックの強制が`--locked`と`MISE_LOCKED`に依存する。付けずに`mise install`すると、未記録の環境ではSHA256の照合が無い | フェーズ4で`scripts/quality-gate.sh`と`jdx/mise-action`の`install_args`に`--locked`を入れる。フェーズ5の文書で、導入手順を`mise install --locked`に統一する |
| 要確認 | CIの`jdx/mise-action`は作業ディレクトリの`mise.toml`を自動で信頼する。PRが`[env]`、`[hooks]`、`[tasks]`を足すと、CIで実行される | フェーズ4で`permissions: contents: read`、シークレットを渡さない、`pull_request_target`を使わない、の3点を守り、workflowの変更時に再確認する |

レビューの判定不能な範囲は、SHA256の外部照合の再計算（2章の記録に基づく）、macOSの実機での導入、フェーズ2以降の変更である。

## 6. 品質ゲート（T-R0106）

| ゲート | 結果 |
| --- | --- |
| `sh scripts/quality-gate.sh` | `quality-gate: passed`（`git diff --check`、`sh -n`の17件、`npm run -s lint:md`で83ファイル0件） |
| `git diff --check`（作業ツリー） | 指摘なし |

この時点のゲートはshellcheckをまだ実行しない。shellcheckのゲートへの組み込みはフェーズ4で行う。
