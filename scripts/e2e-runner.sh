# M09 pause方式のランナー。scripts/e2e.sh と tests/m09 から読み込む（直接実行しない）。
# 前提: 先に e2e-lib.sh を読み込み、SWSC_ROOT を設定しておく。
# Why: 起動の順序（WireMock、管理APIの応答、pause、Squid）を1か所に集め、偽の docker と curl で固定するため（G1）。

# 待機の上限（秒）。Why: 既定は仕様どおり120秒。検査が失敗経路を数秒で確かめられるよう、上書きだけを許す。
SWSC_WAIT_SECONDS=${SWSC_WAIT_SECONDS:-120}

# 完成版を docker run の引数へ変換する。実行ごとのファイルを、実行ディレクトリへ作る。
swsc_runner_prepare() { # 実行ディレクトリ 完成版 実行ID
  mkdir -p "$1"
  python3 -B "$SWSC_ROOT/scripts/e2e-taskdef.py" docker-args \
    --taskdef "$2" --out-dir "$1" --pause-name swsc-pause --run-id "$3"
}

swsc_runner_create_network() {
  docker network create --label "$SWSC_LABEL" "$SWSC_NET" >/dev/null
}

# WireMock は、既存のシナリオを読み取り専用で受け、ホストの8080だけに公開する。
# Why: 他のコンテナには公開しない。Client は pause の名前空間から名前で届く。
swsc_runner_start_wiremock() {
  docker run -d --name swsc-wiremock --label "$SWSC_LABEL" --label swsc.role=wiremock \
    --network "$SWSC_NET" -p 127.0.0.1:8080:8080 \
    -v "$SWSC_ROOT/wiremock-scenarios:/home/wiremock:ro" \
    "$SWSC_WIREMOCK_IMAGE" >/dev/null
}

# コンテナが止まっているか。存在しない場合も止まっているとみなす。
# Why: 起動したコンテナが落ちたとき、待機の上限（既定120秒）まで待たずに、原因の段階で止めるため。
# Why not 状態の文字列を網羅しない: 止まっていると言えるのは Running が false のときだけにする。
swsc_runner_stopped() { # インスタンス名
  _running=$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null) || return 0
  [ "$_running" = false ]
}

# WireMock の管理APIが応答するまで待つ。Squid は起動時に WireMock の名前を引くため、先に待つ（G1）。
swsc_runner_wait_wiremock() {
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  while ! curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:8080/__admin/mappings; do
    if swsc_runner_stopped swsc-wiremock; then
      printf 'FAIL: WireMock が停止している（管理APIの応答を待てない）\n' >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: WireMock の管理APIが %s 秒以内に応答しない\n' "$SWSC_WAIT_SECONDS" >&2
      return 1
    fi
    sleep 1
  done
}

# pause は名前空間の持ち主になるだけで、何もしない。Squid と Client が、その名前空間に参加する。
swsc_runner_start_pause() {
  docker run -d --name swsc-pause --label "$SWSC_LABEL" --label swsc.role=pause \
    --network "$SWSC_NET" "$SWSC_PAUSE_IMAGE" sleep infinity >/dev/null
}

# 実行ディレクトリの .args を1行1引数として読み、docker run へ渡す。値は .env にあり、引数には出ない。
# Why: 引数の組み立てを変換の出力に任せ、シェルでは文字列を連結しないため（空白や記号を壊さない）。
swsc_runner_run_container() { # detach|fg 実行ディレクトリ インスタンス名
  _mode=$1
  _file=$2/$3.args
  if [ ! -f "$_file" ]; then
    printf 'FAIL: 引数のファイルが無い: %s\n' "$3" >&2
    return 1
  fi
  set --
  while IFS= read -r _line || [ -n "$_line" ]; do
    set -- "$@" "$_line"
  done <"$_file"
  if [ "$_mode" = detach ]; then
    docker run -d "$@" >/dev/null
  else
    docker run --rm "$@"
  fi
}

# 必須の Squid を、pause の名前空間で起動する。
swsc_runner_start_squid() { # 実行ディレクトリ
  swsc_runner_run_container detach "$1" swsc-squid
}

# 指定のコンテナが healthy になるまで待つ。unhealthy は待たずに失敗させる。
swsc_runner_wait_healthy() { # インスタンス名
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  while :; do
    _h=$(docker inspect --format '{{.State.Health.Status}}' "$1" 2>/dev/null || true)
    case $_h in
      healthy) return 0 ;;
      unhealthy)
        printf 'FAIL: %s が unhealthy\n' "$1" >&2
        return 1
        ;;
    esac
    if swsc_runner_stopped "$1"; then
      printf 'FAIL: %s が停止している（healthy を待てない）\n' "$1" >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: %s が %s 秒以内に healthy にならない\n' "$1" "$SWSC_WAIT_SECONDS" >&2
      return 1
    fi
    sleep 1
  done
}

# Squid の待受を、pause の名前空間に参加した使い捨てのコンテナで確かめる。
# Why: ヘルスチェックの kill -0 1 は、待受の開始を示さないため（R-09）。
swsc_runner_probe_squid() { # 実行ID
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  while ! docker run --rm --name "swsc-probe-$1" --label "$SWSC_LABEL" --label swsc.role=probe \
    --network container:swsc-pause "$SWSC_PAUSE_IMAGE" nc -z 127.0.0.1 3128 >/dev/null 2>&1; do
    if swsc_runner_stopped swsc-squid; then
      printf 'FAIL: Squid が停止している（待受を確認できない）\n' >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: Squid の待受が %s 秒以内に確認できない\n' "$SWSC_WAIT_SECONDS" >&2
      return 1
    fi
    sleep 1
  done
}

# 起動の順序を固定する。Why: WireMock の応答を待たずに pause と Squid を作ると、Squid が WireMock の名前を引けない（G1）。
# 変換は最初に終える。失敗しても、コンテナを1つも作らずに止まるため。
swsc_runner_start_all() { # 実行ディレクトリ 完成版 実行ID
  swsc_runner_prepare "$1" "$2" "$3" || return 1
  swsc_runner_create_network || return 1
  swsc_runner_start_wiremock || return 1
  swsc_runner_wait_wiremock || return 1
  swsc_runner_start_pause || return 1
  swsc_runner_start_squid "$1" || return 1
  swsc_runner_wait_healthy swsc-squid || return 1
  swsc_runner_probe_squid "$3"
}

# Client を1回だけ実行し、docker run の終了コードを返す。
# Why: 依存の HEALTHY は、実行の前に待つ。Client 自身にはヘルスチェックを持たせない（Q-918）。
swsc_runner_run_client() { # 実行ディレクトリ 実行ID
  _inst=swsc-client-$2
  _deps=$1/$_inst.depends
  if [ ! -f "$_deps" ]; then
    printf 'FAIL: 依存のファイルが無い: %s\n' "$_inst" >&2
    return 1
  fi
  while IFS= read -r _dep; do
    case $_dep in
      "HEALTHY "*) swsc_runner_wait_healthy "${_dep#HEALTHY }" || return 1 ;;
      "START "*) ;; # Why: START は起動の順序だけの条件。start_all が先に作っている。
      *)
        printf 'FAIL: 未対応の依存: %s\n' "$_dep" >&2
        return 1
        ;;
    esac
  done <"$_deps"
  swsc_runner_run_container fg "$1" "$_inst"
}

# 検査と後始末の対象を、接頭辞 swsc- とラベルの両方で絞って消す（FR-921、6.1）。
# Why: 他のプロジェクトのコンテナを、名前かラベルのどちらか一方だけでは選ばないため。
# Why not docker stop: 元のエントリポイントは squid を子として動かし、SIGTERM が届かないため（G5）。
swsc_runner_remove_managed() {
  _list=$(docker ps -a --filter "label=$SWSC_LABEL" --format '{{.ID}} {{.Names}}') || return 1
  # Why: Client と Squid を、pause より先に消す。pause の名前空間を、参加者より先に失わないため。
  for _want in first rest; do
    while read -r _id _name; do
      case $_name in swsc-*) ;; *) continue ;; esac
      case $_name in
        swsc-client-* | swsc-probe-* | swsc-squid) _k=first ;;
        *) _k=rest ;;
      esac
      [ "$_k" = "$_want" ] || continue
      docker rm -f "$_id" >/dev/null || return 1
    done <<EOF
$_list
EOF
  done
  _nets=$(docker network ls --filter "label=$SWSC_LABEL" --format '{{.Name}}') || return 1
  while read -r _n; do
    case $_n in
      swsc-*) docker network rm "$_n" >/dev/null || return 1 ;;
    esac
  done <<EOF
$_nets
EOF
}
