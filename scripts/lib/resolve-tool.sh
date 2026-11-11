# shellcheck shell=sh
# shellcheck disable=SC2034 # RESOLVED_PATH と RESOLVED_VERSION は、読み込んだ側が使う。
# miseの固定版のツールを照合する関数を定義する。読み込んでも、コマンドは実行しない（副作用なし）。
# scripts/e2e-lib.sh が . で読み込む。

# resolve_tool <ツール名> <版を取り出す sed の式> <版を出す引数>
# 成功時は RESOLVED_PATH（実体のパス）と RESOLVED_VERSION（実際の版）を設定して 0 を返す。
# 失敗時は導入手順つきの FAILED: を stderr に出し、1 を返す。呼び出し側は if ! で受ける。
# Why: 自動の導入を止める3つの環境変数を、miseを呼ぶ各コマンドに付ける。export はしない。
# Why: mise の取得は if ! で受ける。var=$(...) で直接受けると set -e で止まり、導入手順を出せないため。
# Why: 版の期待値は mise current（mise.toml の固定版）から得る。ゲートごとに版を書き直さないため。
resolve_tool() {
  RESOLVED_PATH=
  RESOLVED_VERSION=
  _rt_name=$1
  _rt_sed=$2
  _rt_arg=$3

  if ! command -v mise >/dev/null 2>&1; then
    printf 'FAILED: miseが未導入。miseを導入し、mise install --lockedを実行する（docs/ローカル実行とCI.md）\n' >&2
    return 1
  fi
  if ! _rt_expected=$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise current "$_rt_name" 2>/dev/null) \
    || [ -z "$_rt_expected" ]; then
    printf 'FAILED: %sの期待する版を得られない（mise.toml の固定版を確かめる）。mise install --lockedを実行する\n' "$_rt_name" >&2
    return 1
  fi
  if ! _rt_path=$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which "$_rt_name" 2>/dev/null) \
    || [ -z "$_rt_path" ]; then
    printf 'FAILED: %sが未導入。mise install --lockedを実行する\n' "$_rt_name" >&2
    return 1
  fi
  if ! _rt_out=$("$_rt_path" "$_rt_arg" 2>&1); then
    printf 'FAILED: %s %s が失敗した。mise install --lockedを実行する\n' "$_rt_name" "$_rt_arg" >&2
    return 1
  fi
  _rt_actual=$(printf '%s\n' "$_rt_out" | sed -n "$_rt_sed" | sed -n '1p')
  if [ "$_rt_actual" != "$_rt_expected" ]; then
    printf 'FAILED: %sの版が期待と異なる（期待 %s、実際 %s）。mise install --lockedを実行する\n' \
      "$_rt_name" "$_rt_expected" "$_rt_actual" >&2
    return 1
  fi
  RESOLVED_PATH=$_rt_path
  RESOLVED_VERSION=$_rt_actual
  return 0
}
