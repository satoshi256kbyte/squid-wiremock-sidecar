# bats の検査の共通部品。各 .bats が load で読む。

# 前面のシェルで起動されたことを確かめる（旧の tests/m09-execution-and-ci.sh の冒頭の検査を移したもの）。
# SIGINT が無視されたまま起動されると、INT の検査が原因の分かりにくい形で落ちるため、先に止める。
# Why: 背景（&）や nohup で起動すると、シェルは SIGINT を無視して始まり、trap で受けられない（POSIX）。
common_require_foreground() {
  _int_rc=0
  sh -c 'kill -INT $$; exit 0' >/dev/null 2>&1 || _int_rc=$?
  if [ "$_int_rc" -eq 0 ]; then
    printf '%s\n' 'FAIL: SIGINT が無視された状態で起動された（背景起動や nohup など）。前面のシェルで実行する' >&2
    return 1
  fi
  return 0
}

# 各検査の作業場所を、bats の BATS_TEST_TMPDIR に置く。bats が検査の後に消すため、ここでは消さない。
# shellcheck disable=SC2154 # BATS_TEST_TMPDIR は bats が設定する。
common_setup_tmp() {
  TMP=$BATS_TEST_TMPDIR
  export TMP
}

# 検査ごとの後始末。作業場所は bats が消すため、ここでは追加の処理を持たない。
# Why: teardown_file は TERM では動かない（U15）。入口だけに TERM が届いたときの後始末は無い（既知のリスク。bats が孤児として残る）。
common_teardown_tmp() {
  :
}
