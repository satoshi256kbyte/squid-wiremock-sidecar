#!/bin/sh
# retry-lib.sh は entrypoint.sh から読み込まれる関数だけを置く。
# 読み込み時に値の設定、ファイル作成、通信、sleep は行わない。
# 関数は POSIX sh の機能だけを使う。busybox の sh と awk で動かすため。

# 5xx の再試行対象は 500 と 503 だけ、429 は別ポリシーとして返す。
# 502 と 504 は M06 の対象外（spec.md 6章）なので含めない。
is_retryable_status() {
  case "$1" in
    500|503)
      printf '%s\n' 5xx
      return 0
      ;;
    429)
      printf '%s\n' 429
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 倍々にしながら毎回上限で止める。2^(n-1) を直接計算すると大きな n で桁あふれする。
# 上限は6桁以内に正規化済みなので、途中の値が64bit整数を超えることはない。
backoff_wait_5xx() { # リトライ番号n 基準秒 上限秒
  _n=$1
  _wait=$2
  _cap=$3
  if [ "$_wait" -eq 0 ]; then
    printf '%s\n' 0
    return 0
  fi
  _i=1
  while [ "$_i" -lt "$_n" ] && [ "$_wait" -lt "$_cap" ]; do
    _wait=$((_wait * 2))
    _i=$((_i + 1))
  done
  if [ "$_wait" -gt "$_cap" ]; then
    _wait=$_cap
  fi
  printf '%s\n' "$_wait"
}

# 429 の待機秒数と切り詰めフラグ（0か1）を "<秒> <フラグ>" で返す。
# Retry-After がない場合も既定待機に上限を適用する。上限で切り詰めた場合は、
# 既定待機でもフラグを1にする（spec.md にこの場合の規定がないため、要確認）。
resolve_429_wait() { # Retry-After秒（空可） 既定待機秒 上限秒
  _ra=$1
  _default=$2
  _cap=$3
  if [ -n "$_ra" ]; then
    _wait=$_ra
  else
    _wait=$_default
  fi
  if [ "$_wait" -gt "$_cap" ]; then
    printf '%s 1\n' "$_cap"
  else
    printf '%s 0\n' "$_wait"
  fi
}

# 標準入力のヘッダー全文から Retry-After の秒数を取り出す。
# 不在扱い（空、負数、小数、HTTP日付、数字以外を含む値）は何も出さずに終了コード1。
# 7桁以上の数字は秒数形式として上限超過に当たるので、1000000 に飽和して返す。
# 桁数だけで判定し、算術に渡さない。20桁の数字列を $(( )) へ渡すと桁あふれするため。
# busybox の awk で動くように、gsub と substr と index だけを使う。
parse_retry_after() {
  awk '
    BEGIN { found = 0; value = "" }
    {
      line = $0
      sub(/\r$/, "", line)
      colon = index(line, ":")
      if (colon == 0) next
      name = tolower(substr(line, 1, colon - 1))
      if (name == "retry-after") {
        value = substr(line, colon + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", value)
        found = 1
      }
    }
    END {
      if (!found) exit 1
      if (value !~ /^[0-9]+$/) exit 1
      # 同名が複数あるときは最後の値を使う。先頭0を落として桁数を数え直す。
      sub(/^0+/, "", value)
      if (value == "") value = "0"
      if (length(value) > 6) value = "1000000"
      print value
    }
  '
}

# 先頭の0を除いて正規化し、結果を _norm に残す。
# 8進数として解釈されないよう、算術に渡す前にこの関数を通す。0だけの値は "0" に残す。
_strip_leading_zeros() {
  _norm=$1
  while case $_norm in 0?*) true ;; *) false ;; esac; do
    _norm=${_norm#0}
  done
}

# 10進の非負整数で、先頭0を除いて6桁以内なら成功する。結果は _norm に残す。
# 7桁以上を弾く理由は、待機秒数を算術へ渡したときの上限を一定に保つため。
_check_digits() {
  case $1 in
    ''|*[!0-9]*) return 1 ;;
  esac
  _strip_leading_zeros "$1"
  [ "${#_norm}" -le 6 ]
}

# 空または未設定は既定値にする。値は先頭0を落として代入し直す。
_apply_one() { # 変数名 既定値
  eval "_raw=\${$1:-}"
  if [ -z "$_raw" ]; then
    _raw=$2
  fi
  _strip_leading_zeros "$_raw"
  eval "$1=\$_norm"
}

apply_config_defaults() {
  _apply_one RETRY_MAX_ATTEMPTS_5XX 3
  _apply_one RETRY_BACKOFF_BASE_SECONDS 1
  _apply_one RETRY_MAX_ATTEMPTS_429 3
  _apply_one RETRY_429_DEFAULT_WAIT_SECONDS 2
  _apply_one RETRY_MAX_WAIT_SECONDS 30
  _apply_one CONNECT_TIMEOUT_SECONDS 5
  _apply_one RESPONSE_TIMEOUT_SECONDS 10
}

# 不正な変数の名前だけを出して 1 を返す。値は出さない（診断ログに設定値を残さないため）。
_validate_one() { # 変数名 最小値（0か1）
  eval "_raw=\${$1:-}"
  if [ -z "$_raw" ]; then
    return 0
  fi
  if ! _check_digits "$_raw"; then
    printf '%s\n' "$1"
    return 1
  fi
  if [ "$2" -eq 1 ] && [ "$_norm" -eq 0 ]; then
    printf '%s\n' "$1"
    return 1
  fi
  return 0
}

# 検査順は plan.md 3.2 に従う。最初の不正変数だけを報告するため、先に失敗したら返す。
validate_config() {
  _validate_one RETRY_MAX_ATTEMPTS_5XX 0 || return 1
  _validate_one RETRY_BACKOFF_BASE_SECONDS 0 || return 1
  _validate_one RETRY_MAX_ATTEMPTS_429 0 || return 1
  _validate_one RETRY_429_DEFAULT_WAIT_SECONDS 0 || return 1
  _validate_one RETRY_MAX_WAIT_SECONDS 0 || return 1
  _validate_one CONNECT_TIMEOUT_SECONDS 1 || return 1
  _validate_one RESPONSE_TIMEOUT_SECONDS 1 || return 1
  return 0
}
