# M09 入口の共通関数。scripts/e2e.sh から読み込む（直接実行しない）。
# 読み込んだだけで何も実行しない。Why: 検査の unit が、関数だけを個別に呼べるようにするため。

# 名前と版の定数。Why: 版を1か所に置き、文書と検査が同じ値を見るため（NFR-909）。
SWSC_PREFIX=swsc-
SWSC_LABEL=swsc.managed=true
SWSC_NET=swsc-net
SWSC_MINISTACK_IMAGE=ministackorg/ministack:1.5.37
SWSC_PAUSE_IMAGE=alpine:3.20
SWSC_WIREMOCK_IMAGE=wiremock/wiremock:3.13.1
SWSC_MINISTACK_ENDPOINT=http://127.0.0.1:4566
SWSC_REGION=ap-northeast-1
SWSC_MINISTACK_NAME=swsc-ministack
SWSC_MINISTACK_PORT=4566
# Why: 出力先を既定の .e2e から変えられるようにする。検査の unit が一時領域へ向けるため。
: "${SWSC_E2E_DIR:=${SWSC_ROOT:-}/.e2e}"
# 収集したログの出力先（FR-921）。unit が一時領域へ向けられるように、既定の場所だけを変数に置く。
: "${SWSC_LOG_DIR:=${SWSC_ROOT:-}/e2e-logs}"
# 識別情報の検出（arn:aws と、前後が英数字と - でない12桁）。Why: UUID の末尾の偶然の12桁を拾わないため（R-07）。
SWSC_ID_RE='arn:aws|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)'
# 自分が作ったディレクトリの目印。Why: 出力先を環境変数で上書きされても、作っていない既存の
# ディレクトリを削除や書き換えしないため（security-review の Low）。
SWSC_DIR_MARKER=.swsc-managed
SWSC_MOCK_PORT=8080
# 手元の起動（start、contract）で使う完成版の入力。start と contract が同じ値を使うため1か所に置く。
SWSC_LOCAL_CLIENT_IMAGE=swsc-client:e2e
SWSC_LOCAL_SQUID_IMAGE=swsc-squid:e2e
SWSC_LOCAL_MOCK_HOST=swsc-wiremock
SWSC_LOCAL_MOCK_PORT=8080

# 必要なコマンドがあるかを検査する。原因を標準エラーに示す。
swsc_need_cmd() { # コマンド名
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '前提不足: %s が見つからない\n' "$1" >&2
    return 1
  fi
}

# ダミー認証情報を検査する。値は表示せず、変数名だけを示す。
# Why: 既定の認証情報（~/.aws、既定プロファイル）へ切り替えないため、未設定と test 以外を止める（FR-905）。
swsc_check_creds() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    printf '前提不足: AWS_PROFILE が設定されている。ダミー認証情報だけを使う\n' >&2
    return 1
  fi
  if [ "${AWS_ACCESS_KEY_ID:-}" != test ]; then
    printf '前提不足: AWS_ACCESS_KEY_ID がダミー値（test）ではない、または未設定\n' >&2
    return 1
  fi
  if [ "${AWS_SECRET_ACCESS_KEY:-}" != test ]; then
    printf '前提不足: AWS_SECRET_ACCESS_KEY がダミー値（test）ではない、または未設定\n' >&2
    return 1
  fi
}

# 起動と通信検証（smoke層）の前提。ポートの空きは含めない（起動の中で、自分の swsc- を止めた後に確かめる）。
swsc_check_smoke_prereq() {
  swsc_need_cmd docker || return 1
  swsc_need_cmd python3 || return 1
  swsc_need_cmd curl || return 1
}

# 停止と後始末の前提。
swsc_check_stop_prereq() {
  swsc_need_cmd docker || return 1
}

# MiniStackの契約検証（contract層）の前提。認証情報は、aws と docker を呼ぶ前に検査する。
swsc_check_contract_prereq() {
  swsc_need_cmd docker || return 1
  swsc_need_cmd aws || return 1
  swsc_need_cmd python3 || return 1
  swsc_check_creds || return 1
}

# AWS CLI の呼び出しの唯一の入口。毎回 MiniStack の宛先を明示し、既定の認証情報を読ませない。
# Why: AWS 設定ファイルと既定プロファイルを、この1回の呼び出しから外すため（FR-905）。
# Why not: 接続と読み取りに時間制限を付けるのは、応答しない MiniStack で待ち続けないため（待機の上限は呼び出し側で持つ）。
swsc_aws() {
  swsc_check_creds || return 1
  env -u AWS_PROFILE \
    AWS_CONFIG_FILE=/dev/null \
    AWS_SHARED_CREDENTIALS_FILE=/dev/null \
    AWS_EC2_METADATA_DISABLED=true \
    aws --endpoint-url "$SWSC_MINISTACK_ENDPOINT" --region "$SWSC_REGION" \
    --cli-connect-timeout 5 --cli-read-timeout 30 "$@"
}

# 出力先を、書き込める状態にする。目印を置いたディレクトリだけを、自分のものとして扱う。
# Why: 既存の中身があるディレクトリ（利用者のもの）は、目印が無ければ拒否する。
# collect の識別情報の削除と clean の削除が、リポジトリ外の既存ファイルに届かないようにするため。
# Why not: パスの許可リストは採らない。unit が一時領域を使い、利用者の上書き先も固定できないため。
swsc_prepare_dir() { # ディレクトリ
  case ${1:-} in
    / | '' | [!/]*)
      printf 'FAIL: 出力先は / 以外の絶対パスで指定する: %s\n' "${1:-}" >&2
      return 1
      ;;
  esac
  if [ -L "$1" ] || { [ -e "$1" ] && [ ! -d "$1" ]; }; then
    printf 'FAIL: 出力先がディレクトリではない、またはシンボリックリンクである: %s\n' "$1" >&2
    return 1
  fi
  if [ -d "$1" ] && [ ! -f "$1/$SWSC_DIR_MARKER" ] && [ -n "$(ls -A "$1")" ]; then
    printf 'FAIL: 出力先に swsc が作っていない中身がある。別のパスを指定する: %s\n' "$1" >&2
    return 1
  fi
  mkdir -p "$1" || return 1
  : >"$1/$SWSC_DIR_MARKER"
}

# 手元の起動の完成版を、start と contract と同じ入力で作る。
swsc_render_local() { # 出力先
  swsc_render "$1" "$SWSC_LOCAL_CLIENT_IMAGE" "$SWSC_LOCAL_SQUID_IMAGE" local mock "$SWSC_LOCAL_MOCK_HOST" "$SWSC_LOCAL_MOCK_PORT"
}

# 127.0.0.1 のポートが応答するか（使用中か）を返す。応答すれば 0、無ければ 1。
# Why: 応答の確認は socket で行う。ポートの占有者を名前では判定できない（プロジェクト名が任意のため）。
swsc_port_in_use() { # ポート番号
  python3 -B -c '
import socket, sys
s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
' "$1"
}

# 標準入力の識別情報を、標準出力でマスクする。ARN を先に消し、残った12桁のアカウントIDを消す。
# Why: 前後が英数字と - でない12桁だけを対象にするため。16進のハッシュの一部を誤って消さないため（R-07）。
# Why: 12桁の置換は2回書く。1回目で前後の文字を消費すると、隣り合う2つ目を取り逃がすため。
swsc_mask() {
  sed -E \
    -e 's/arn:aws[^"[:space:]]*/<RESOURCE_ARN>/g' \
    -e 's/(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)/\1<ACCOUNT_ID>\2/g' \
    -e 's/(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)/\1<ACCOUNT_ID>\2/g'
}

# 完成版のタスク定義を作る唯一の経路。start と contract は、同じ入力でこの関数を呼ぶ。
# Why: 登録用と起動用で生成手順を分けると、比較の前提が崩れるため（FR-903）。
swsc_render() { # 出力先 クライアントイメージ Squidイメージ プロファイル 上流 [mockホスト mockポート]
  # Why: 生成の呼び出しを1か所にまとめる。mock の宛先が無いときは空文字で渡し、
  # 引数の数で呼び分けない（空白の混ざった値で引数が増えるのを防ぐため、展開を使わない）。
  _mock_host=${6:-}
  _mock_port=${7:-}
  python3 -B "$SWSC_ROOT/scripts/e2e-taskdef.py" render \
    --template "$SWSC_ROOT/ecs/task-definition.template.json" --out "$1" \
    --client-image "$2" --squid-image "$3" --profile "$4" --upstream "$5" \
    --mock-host "$_mock_host" --mock-port "$_mock_port"
}

# Squid のビルド文脈を作る。Dockerfile が COPY する名前に揃える。
# Why: リポジトリ全体を文脈にすると、node_modules などを送ってしまうため。
swsc_stage_squid_context() { # 出力先ディレクトリ
  mkdir -p "$1"
  cp "$SWSC_ROOT/squid-config/squid.conf" "$1/squid.conf"
  cp "$SWSC_ROOT/squid-config/whitelist.txt" "$1/whitelist.txt"
  cp "$SWSC_ROOT/ecs/squid/Dockerfile" "$1/Dockerfile"
  cp "$SWSC_ROOT/ecs/squid/derive-config.sh" "$1/derive-config.sh"
  cp "$SWSC_ROOT/ecs/squid/entrypoint.sh" "$1/entrypoint.sh"
}

# WireMock が受けた /api/ の要求の件数を返す。
# Why: Squid が起動後に送る /squid-internal-periodic/ の要求を数えないため（G1、G3）。
# Why not meta.total: 同じ理由で、件数が1つずれる。
swsc_wiremock_total() {
  _body=$(curl -fsS --max-time 5 http://127.0.0.1:8080/__admin/requests) || return 1
  printf '%s' "$_body" | python3 -B -c "import json, sys
d = json.load(sys.stdin)
print(sum(1 for r in d.get('requests', []) if str(r.get('request', {}).get('url', '')).startswith('/api/')))"
}

# ---------------------------------------------------------------------------
# 入口の操作（start、test、test:ci、stop、clean、logs、collect）。
# 関数はここに置き、scripts/e2e.sh は振り分けだけを行う。Why: 検査の unit が、順序と終了コードを
# 偽の関数で差し替えて確かめられるようにするため。
# ---------------------------------------------------------------------------

# 指定の名前のコンテナが動いているか（Squid の稼働の確認）。
swsc_squid_running() {
  [ "$(docker inspect --format '{{.State.Running}}' "${SWSC_PREFIX}squid" 2>/dev/null || true)" = true ]
}

# 手元の起動で、ビルドしたイメージを作る。Why: 文脈は必要なファイルだけを写し、リポジトリ全体を送らないため。
# Why not `docker build` の既定の文脈: node_modules や .git を送ってしまうため。
swsc_build_images() {
  _ctx=$SWSC_E2E_DIR/context
  if [ -d "$_ctx" ]; then rm -r -- "$_ctx" || return 1; fi
  mkdir -p "$_ctx/client/test-client" || return 1
  cp "$SWSC_ROOT/Dockerfile.test-client" "$_ctx/client/Dockerfile.test-client" || return 1
  cp "$SWSC_ROOT/test-client/entrypoint.sh" "$SWSC_ROOT/test-client/retry-lib.sh" \
    "$_ctx/client/test-client/" || return 1
  docker build -q --label "$SWSC_LABEL" -t "$SWSC_LOCAL_CLIENT_IMAGE" \
    -f "$_ctx/client/Dockerfile.test-client" "$_ctx/client" >/dev/null || return 1
  swsc_stage_squid_context "$_ctx/squid" || return 1
  docker build -q --label "$SWSC_LABEL" -t "$SWSC_LOCAL_SQUID_IMAGE" "$_ctx/squid" >/dev/null || return 1
}

# 起動（start）の本体。trap を持たない。Why: test:ci の中で、collect より先に stop が走るのを防ぐため。
# 前提検査にはポートを含めず、自分の swsc- を止めた後に8080を確かめる（FR-912）。
swsc_start_main() {
  swsc_stop || {
    printf 'FAIL: 既存の swsc- の停止に失敗した\n' >&2
    return 1
  }
  # Why: 占有者の名前では判定しない。プロジェクト名は任意で、旧基盤の名前を当てにできないため。
  if swsc_port_in_use "$SWSC_MOCK_PORT"; then
    printf 'FAIL: ポート%sが使用中（swsc- 以外のコンテナかプロセス。旧基盤の可能性がある）\n' "$SWSC_MOCK_PORT" >&2
    return 1
  fi
  # Why: build_images が出力先の中を作り直す（rm -r）ため、その前に自分のディレクトリか確かめる。
  swsc_prepare_dir "$SWSC_E2E_DIR" || return 1
  swsc_build_images || {
    printf 'FAIL: イメージのビルドに失敗した\n' >&2
    return 1
  }
  mkdir -p "$SWSC_E2E_DIR" || return 1
  swsc_render_local "$SWSC_E2E_DIR/taskdef.json" || {
    printf 'FAIL: 完成版の生成に失敗した\n' >&2
    return 1
  }
  # Why: 前の実行の起動情報を残すと、test が古い Client の引数を拾うため、作り直す。
  if [ -d "$SWSC_E2E_DIR/run" ]; then rm -r -- "$SWSC_E2E_DIR/run" || return 1; fi
  # Why: 実行IDは PID にする。Client の名前が、同じホストの別の実行と衝突しないため。
  swsc_runner_start_all "$SWSC_E2E_DIR/run" "$SWSC_E2E_DIR/taskdef.json" "$$"
}

# start 操作（単独）。失敗時だけ stop を呼ぶ。Why: 成功時は環境を残して調べられるようにするため。
# Why not collect: 単独の start の失敗では、収集は test:ci の仕事であるため。
swsc_start_op() {
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '_t=$?; swsc_stop >/dev/null 2>&1 || true; exit "$_t"' EXIT
  _rc=0
  swsc_start_main || _rc=$?
  trap - EXIT INT TERM
  if [ "$_rc" -ne 0 ]; then swsc_stop || true; fi
  return "$_rc"
}

# 1回の要求で Client を1回起動する。上書きの URL は -e で渡す（env-file より優先される）。
# Why: 引数の組み立ては run の .args に任せ、ここでは上書きだけを足す。
swsc_client_once() { # 実行ディレクトリ 実行ID ベースURL
  _file=$1/swsc-client-$2.args
  # Why: set -- が位置パラメータを入れ替えるため、ベースURLは先に別の変数へ退避する。
  # Why not: $3 を後から参照する形は採らない。入れ替え後の値（--label）が URL になり、Squid が全て拒否する（実機で確認）。
  _base_url=$3
  if [ ! -f "$_file" ]; then
    printf 'FAIL: 引数のファイルが無い: swsc-client-%s\n' "$2" >&2
    return 1
  fi
  set --
  while IFS= read -r _line || [ -n "$_line" ]; do
    set -- "$@" "$_line"
  done <"$_file"
  docker run --rm -e "TEST_API_BASE_URL=$_base_url" "$@"
}

# WireMock の受信記録を空にし、空になったことを確かめる。
# Why: 受信記録だけを消す経路は DELETE /__admin/requests。POST /__admin/requests/reset は WireMock 3.13.1 で 404 になる（実測）。
# Why not: POST /__admin/reset は採らない。マッピングまで初期化し、検査の前提（シナリオの状態）を変えてしまうため。
swsc_wiremock_reset() {
  curl -fsS --max-time 5 -X DELETE "http://127.0.0.1:${SWSC_MOCK_PORT}/__admin/requests" >/dev/null || return 1
  [ "$(swsc_wiremock_total)" = 0 ]
}

# 検査の1件。状態（終了コード、CLIENT_STATUS、/api/ の受信数）が期待どおりなら PASS。
swsc_test_item() { # 番号 名前 ベースURL 期待のステータス 期待の受信数 実行ディレクトリ 実行ID
  swsc_wiremock_reset || {
    printf 'FAIL: %s %s: WireMock の受信記録を空にできない\n' "$1" "$2"
    return 1
  }
  _crc=0
  _out=$(swsc_client_once "$6" "$7" "$3") || _crc=$?
  _status=$(printf '%s\n' "$_out" | sed -n 's/^CLIENT_STATUS=//p' | head -n 1)
  _total=$(swsc_wiremock_total) || _total=unknown
  if [ "$_crc" -eq 0 ] && [ "$_status" = "$4" ] && [ "$_total" = "$5" ]; then
    printf 'PASS: %s %s（CLIENT_STATUS=%s、受信数=%s）\n' "$1" "$2" "$_status" "$_total"
    return 0
  fi
  printf 'FAIL: %s %s（CLIENT_STATUS=%s 期待 %s、受信数=%s 期待 %s、Client終了コード=%s）\n' \
    "$1" "$2" "$_status" "$4" "$_total" "$5" "$_crc"
  return 1
}

# Squid を再起動し、healthy になるまで待つ（FR-907の3項目め）。
swsc_test_restart_squid() {
  docker restart "${SWSC_PREFIX}squid" >/dev/null || return 1
  swsc_runner_wait_healthy "${SWSC_PREFIX}squid"
}

# FR-907 の3項目。1項目でも失敗すれば、全体は失敗する。
swsc_test_body() { # 実行ディレクトリ 実行ID
  _all=0
  swsc_test_item 1 許可ドメイン http://api.example.com 200 1 "$1" "$2" || _all=1
  swsc_test_item 2 許可外ドメイン http://blocked.example.net 403 0 "$1" "$2" || _all=1
  if swsc_test_restart_squid; then
    swsc_test_item 3 Squid再起動後 http://api.example.com 200 1 "$1" "$2" || _all=1
  else
    printf 'FAIL: 3 Squid再起動後: Squid が再起動後に healthy にならない\n'
    _all=1
  fi
  return "$_all"
}

# 通信検証（test）。出力は一度ファイルへ書き、終了コードを取ってから表示する（終了コードを保つため）。
swsc_test_run() {
  swsc_prepare_dir "$SWSC_LOG_DIR" || return 1
  if ! swsc_squid_running; then
    printf 'FAIL: Squid が稼働していない。先に start を実行する\n' >&2
    return 1
  fi
  _dir=$SWSC_E2E_DIR/run
  _args=$(ls "$_dir"/swsc-client-*.args 2>/dev/null | head -n 1 || true)
  if [ -z "$_args" ]; then
    printf 'FAIL: 起動情報が無い。先に start を実行する\n' >&2
    return 1
  fi
  _id=${_args##*/swsc-client-}
  _id=${_id%.args}
  swsc_runner_wait_healthy "${SWSC_PREFIX}squid" || return 1
  _rc=0
  swsc_test_body "$_dir" "$_id" >"$SWSC_LOG_DIR/test.out" 2>"$SWSC_LOG_DIR/test.err" || _rc=$?
  cat "$SWSC_LOG_DIR/test.out"
  cat "$SWSC_LOG_DIR/test.err" >&2
  return "$_rc"
}

# test 操作。INT と TERM のときだけ stop を呼ぶ。通常の失敗では環境を残す（調べられるように）。
swsc_test_op() {
  _sig=0
  trap '_sig=130; exit 130' INT
  trap '_sig=143; exit 143' TERM
  trap '_t=$?; if [ "$_sig" -ne 0 ]; then swsc_stop >/dev/null 2>&1 || true; fi; exit "$_t"' EXIT
  _rc=0
  swsc_test_run || _rc=$?
  return "$_rc"
}

# test:ci。start が失敗しても test を飛ばし、collect、stop の順で必ず呼ぶ。終了コードは test か start の値。
# EXIT の trap は、INT と TERM で本体に届かなかった場合の最終防衛に限る（_done で二重実行を防ぐ）。
swsc_test_ci_main() {
  _done=0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '_t=$?; if [ "$_done" -eq 0 ]; then swsc_collect || true; swsc_stop || true; fi; exit "$_t"' EXIT
  _rc=0
  swsc_start_main || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    swsc_test_run || _rc=$?
  fi
  swsc_collect || true
  swsc_stop || true
  # Why: _done は collect と stop が済んでから立てる。先に立てると、collect か stop の最中に INT と TERM を受けたとき、
  # EXIT の trap が後始末を飛ばし、コンテナが残るため。後始末は冪等なので、二重に走っても害はない（security-review の Low）。
  _done=1
  exit "$_rc"
}

# 停止。接頭辞とラベルの両方が一致するものだけを、依存の順に消す。冪等（対象が無ければ0）。
swsc_stop() {
  swsc_runner_remove_managed
}

# 自分の作ったディレクトリを消す。変数が空、または無いなら何もしない（空の変数で広い場所を消さないため）。
# 目印が無いディレクトリは、利用者のものとして消さずに失敗する。
swsc_remove_dir() {
  case ${1:-} in
    '') return 0 ;;
  esac
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then return 0; fi
  if [ -L "$1" ] || [ ! -d "$1" ] || [ ! -f "$1/$SWSC_DIR_MARKER" ]; then
    printf 'FAIL: swsc が作ったディレクトリではないため削除しない: %s\n' "$1" >&2
    return 1
  fi
  rm -r -- "$1"
}

# 停止に加えて、ビルドした自分のイメージと、一時物（.e2e、e2e-logs）を消す。
# Why not 他のイメージ: alpine や wiremock は他のプロジェクトも使うため、消さない（6.1）。
swsc_clean() {
  swsc_stop || return 1
  for _i in "$SWSC_LOCAL_CLIENT_IMAGE" "$SWSC_LOCAL_SQUID_IMAGE"; do
    docker image rm "$_i" >/dev/null 2>&1 || true
  done
  # Why: 片方が拒否されても、もう片方は消す。終了コードで拒否を伝える。
  _clean_rc=0
  swsc_remove_dir "$SWSC_E2E_DIR" || _clean_rc=1
  swsc_remove_dir "$SWSC_LOG_DIR" || _clean_rc=1
  return "$_clean_rc"
}

# 名前を指定したコンテナのログを表示する。名前は4つに限り、残りの引数は docker logs へ渡す。
swsc_logs() {
  case ${1:-} in
    '')
      for _n in squid wiremock ministack pause; do
        printf '== %s\n' "$_n"
        docker logs "${SWSC_PREFIX}${_n}" 2>&1 || true
      done
      ;;
    squid | wiremock | ministack | pause)
      _n=$1
      shift
      docker logs "$@" "${SWSC_PREFIX}${_n}"
      ;;
    *)
      printf 'FAIL: logs の名前は squid、wiremock、ministack、pause のどれか\n' >&2
      return 2
      ;;
  esac
}

# コマンドの出力を収集物へ置く。失敗したら既存の収集物を残し、missing.txt に名前を追記する（冪等）。
# Why: 一時ファイルへ書いてから移すのは、失敗した回で既存の収集物を空にしないため。
swsc_collect_from_command() { # 収集物の相対パス コマンド...
  _dst=$SWSC_LOG_DIR/$1
  shift
  if "$@" >"$_dst.tmp" 2>&1; then
    mv -f "$_dst.tmp" "$_dst"
  else
    rm -f "$_dst.tmp"
    printf '%s\n' "${_dst#"$SWSC_LOG_DIR"/}" >>"$SWSC_LOG_DIR/missing.txt"
  fi
}

# ファイルを収集物へ写す。元が無い回は既存の収集物を残し、missing.txt に名前を追記する。
swsc_collect_copy() { # 収集物の相対パス 元のファイル
  if [ -f "$2" ] && cp "$2" "$SWSC_LOG_DIR/$1.tmp"; then
    mv -f "$SWSC_LOG_DIR/$1.tmp" "$SWSC_LOG_DIR/$1"
  else
    rm -f "$SWSC_LOG_DIR/$1.tmp"
    printf '%s\n' "$1" >>"$SWSC_LOG_DIR/missing.txt"
  fi
}

# 環境の記録。Docker の版と、使ったコンテナのイメージとダイジェストだけを書く。環境変数の値は書かない（FR-916）。
# Why: aws を呼ばない。collect は start、test、stop と同じく AWS CLI と認証情報を使わない経路のため。
swsc_collect_env() {
  {
    printf 'docker server: %s\n' "$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 取得不可)"
    for _i in "$SWSC_LOCAL_CLIENT_IMAGE" "$SWSC_LOCAL_SQUID_IMAGE"; do
      printf 'image %s: %s\n' "$_i" "$(docker image inspect --format '{{.Id}}' "$_i" 2>/dev/null || echo 取得不可)"
    done
    # Why: 派生イメージの Id だけでは、基底の ubuntu/squid:latest がどの版だったかを後から特定できない（レビュー M-3）。
    # Why not: aws --version は書かない。collect は AWS CLI を呼ばない経路のため（FR-905）。版は contract の結果に残す。
    for _i in ubuntu/squid:latest "$SWSC_MINISTACK_IMAGE"; do
      printf 'base %s: %s\n' "$_i" \
        "$(docker image inspect --format '{{index .RepoDigests 0}}' "$_i" 2>/dev/null || echo 取得不可)"
    done
    for _n in squid wiremock ministack; do
      docker inspect --format 'name={{.Name}} image={{.Config.Image}} id={{.Image}}' "${SWSC_PREFIX}${_n}" \
        2>/dev/null || true
    done
  } >"$SWSC_LOG_DIR/env.txt.tmp" || true
  if [ -f "$SWSC_LOG_DIR/env.txt.tmp" ]; then
    mv -f "$SWSC_LOG_DIR/env.txt.tmp" "$SWSC_LOG_DIR/env.txt"
  fi
}

# 識別情報を含む行があるか（標準入力）。
swsc_has_identifier() {
  grep -Eq "$SWSC_ID_RE"
}

# 収集物の識別情報を、コピーの上でマスクする。マスクでも残るファイルは削除し、名前を scrub.txt に記録する。
# Why: 再検査は、マスクの後に残りを確かめるため。マスクで消せないファイルを残さないため（FR-918）。
swsc_collect_scrub() {
  # Why fail closed: 走査できなければ、識別情報の検査を通ったことにしない（FR-918）。
  _found=$(find "$SWSC_LOG_DIR" -type f ! -name scrub.txt ! -name missing.txt) || {
    printf 'FAIL: 収集物の走査に失敗した\n' >&2
    return 1
  }
  _list=$(printf '%s\n' "$_found" | sort)
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    if swsc_has_identifier <"$_f"; then
      if swsc_mask <"$_f" >"$_f.masked"; then
        mv -f "$_f.masked" "$_f"
      fi
      rm -f "$_f.masked"
      if swsc_has_identifier <"$_f"; then
        rm -f "$_f"
        printf '%s\n' "${_f#"$SWSC_LOG_DIR"/}" >>"$SWSC_LOG_DIR/scrub.txt"
      fi
    fi
  done <<EOF
$_list
EOF
}

# 収集（collect）。冪等。対象が無くても0。識別情報を削除した回だけ1（scrub.txt に名前を残す）。
# Why: 収集の失敗で test の終了コードを変えないよう、呼び出し側は collect || true で受ける（FR-921）。
swsc_collect() {
  swsc_prepare_dir "$SWSC_LOG_DIR" || return 1
  mkdir -p "$SWSC_LOG_DIR/containers" "$SWSC_LOG_DIR/squid" || return 1
  : >"$SWSC_LOG_DIR/scrub.txt" || return 1
  for _n in squid wiremock ministack; do
    swsc_collect_from_command "containers/${SWSC_PREFIX}${_n}.log" docker logs "${SWSC_PREFIX}${_n}"
  done
  swsc_collect_from_command squid/access.log docker exec "${SWSC_PREFIX}squid" cat /var/log/squid/access.log
  swsc_collect_from_command squid/cache.log docker exec "${SWSC_PREFIX}squid" cat /var/log/squid/cache.log
  swsc_collect_copy taskdef.json "$SWSC_E2E_DIR/taskdef.json"
  swsc_collect_copy ministack-contract.json "$SWSC_E2E_DIR/ministack-contract.json"
  swsc_collect_copy ministack-describe.json "$SWSC_E2E_DIR/ministack-describe.json"
  swsc_collect_copy ministack-inspect.json "$SWSC_E2E_DIR/ministack-inspect.json"
  for _f in test.out test.err; do
    if [ ! -f "$SWSC_LOG_DIR/$_f" ]; then printf '%s\n' "$_f" >>"$SWSC_LOG_DIR/missing.txt"; fi
  done
  swsc_collect_env
  swsc_collect_scrub || return 1
  if [ -s "$SWSC_LOG_DIR/scrub.txt" ]; then
    return 1
  fi
  return 0
}
