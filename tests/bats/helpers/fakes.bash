# 偽の docker、aws などの用意を、1か所にまとめる。
# bats の検査（tests/bats/*.bats）は load で読み、sh の検査（tests/m09-execution-and-ci.sh など）は . で読む。
# 呼び出し側が、TMP（作業場所。偽の呼び出し記録の置き場）を先に設定すること。
# 本文は旧の定義（tests/m09-execution-and-ci.sh）から変えていない。

# 必要なツールだけを束ねたPATHを作る。docker、aws、docker-compose は含めない。
make_base_bin() { # 出力先
  mkdir -p "$1"
  for _t in sh env python3 curl grep sed awk cat cp mv rm rmdir mkdir chmod cmp diff sort head tail tr wc dirname basename ls find mktemp sleep date; do
    _p=$(command -v "$_t" 2>/dev/null || true)
    case $_p in
      /*) ln -sf "$_p" "$1/$_t" ;;
    esac
  done
  # Why: python3 を mise のシムのまま使うと、HOME を空の一時ディレクトリにした検査の中で、
  # 毎回 Python を取得し直して約18秒かかる。導入済みの実体を指すようにする。
  _real=$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null || true)
  case $_real in
    /*) ln -sf "$_real" "$1/python3" ;;
  esac
}

# 呼ばれたら引数を記録して成功する偽物を作る。
make_fake() { # 名前 置き場 記録先
  mkdir -p "$2"
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 0\n' "$1" "$3" >"$2/$1"
  chmod +x "$2/$1"
}

# 偽の docker、aws、docker-compose を入れたPATHを作る（記録は $TMP/rec-*）。
make_shims() { # 置き場
  make_fake docker "$1" "$TMP/rec-docker"
  make_fake aws "$1" "$TMP/rec-aws"
  make_fake docker-compose "$1" "$TMP/rec-compose"
}

no_calls() { # 記録が空、または無いこと
  for _f in "$TMP"/rec-*; do
    [ ! -e "$_f" ] || [ ! -s "$_f" ] || return 1
  done
  return 0
}
