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
# Squid が Client から使うプロキシの待ち受け。start の前に空きを確かめる（T2603）。
SWSC_SQUID_PORT=3128
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

# 指定した経路と完全一致する URL の受信数を返す。取得や解析に失敗したら1。
# Why: 接頭辞では数えない。/api/users/123 が /api/users/1234 や /api/users/123/x を含むと、件数が合わないため。
# Why not: 経路を python のコードに埋め込む。引数で渡せば、記号を含む経路がコードとして解釈されないため。
# Why: meta.total と requests[] が食い違うときは数えない。一部だけ読んだ件数で通すと、検査の意味が無くなるため（scenario-lib の journal_count と同じ作法）。
swsc_wiremock_count_path() { # 経路
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    printf 'FAIL: 経路を1つ指定する\n' >&2
    return 1
  fi
  _body=$(curl -fsS --max-time 5 http://127.0.0.1:8080/__admin/requests) || return 1
  printf '%s' "$_body" | python3 -B -c '
import json, sys
path = sys.argv[1]
d = json.load(sys.stdin)
entries = d.get("requests")
meta = d.get("meta")
total = meta.get("total") if isinstance(meta, dict) else None
if not isinstance(entries, list) or not isinstance(total, int) or total != len(entries):
    sys.stderr.write("FAIL: requests[] が meta.total と一致しない\n")
    sys.exit(1)
count = 0
for entry in entries:
    request = entry.get("request") if isinstance(entry, dict) else None
    url = request.get("url") if isinstance(request, dict) else None
    if not isinstance(url, str):
        sys.stderr.write("FAIL: requests[].request.url が文字列ではない\n")
        sys.exit(1)
    if url == path:
        count += 1
print(count)
' "$1"
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
  # Why: 使う2つのポートを、停止の後に確かめる。自分の残りを使用中と誤認しないため。
  if ! swsc_check_ports_free "$SWSC_MOCK_PORT" "$SWSC_SQUID_PORT"; then
    printf 'FAIL: 使用中のポートがある（swsc- 以外のコンテナかプロセス。旧基盤の可能性がある）\n' >&2
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
# ロックは最初に取る。取れなければ trap を張らずに戻る。後始末（stop）の後にロックを解放する。
swsc_start_op() {
  swsc_lock_enter || return 1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '_t=$?; swsc_stop >/dev/null 2>&1 || true; swsc_lock_leave || [ "$_t" -ne 0 ] || _t=1; exit "$_t"' EXIT
  _rc=0
  swsc_start_main || _rc=$?
  trap - EXIT INT TERM
  if [ "$_rc" -ne 0 ]; then swsc_stop || true; fi
  swsc_lock_leave || { [ "$_rc" -ne 0 ] || _rc=1; }
  return "$_rc"
}

# 1回の要求で Client を1回起動する。上書きの URL は -e で渡す（env-file より優先される）。
# 追加の NAME=VALUE（省略可）も -e で渡す。Why: 呼び出し側が環境変数を足せるよう、既存の3引数の形を残したまま拡張するため。
# Why: 引数の組み立ては run の .args に任せ、ここでは上書きだけを足す。
swsc_client_once() { # 実行ディレクトリ 実行ID ベースURL [NAME=VALUE...]
  _file=$1/swsc-client-$2.args
  _id=$2
  # Why: set -- が位置パラメータを入れ替えるため、ベースURLは先に別の変数へ退避する。
  # Why not: $3 を後から参照する形は採らない。入れ替え後の値（--label）が URL になり、Squid が全て拒否する（実機で確認）。
  _base_url=$3
  shift 3
  if [ ! -f "$_file" ]; then
    printf 'FAIL: 引数のファイルが無い: swsc-client-%s\n' "$_id" >&2
    return 1
  fi
  # Why: -e は、.args のイメージ名より前に並ぶ必要がある。追加分を先に -e の組へ直してから、.args の行を後ろへ足す。
  # Why not: docker run の後ろに置く。イメージより後ろの語は Client のコマンドの引数になるため。
  _n=$#
  while [ "$_n" -gt 0 ]; do
    _kv=$1
    shift
    set -- "$@" -e "$_kv"
    _n=$((_n - 1))
  done
  set -- "$@" -e "TEST_API_BASE_URL=$_base_url"
  while IFS= read -r _line || [ -n "$_line" ]; do
    set -- "$@" "$_line"
  done <"$_file"
  docker run --rm "$@"
}

# Client を1回起動し、標準出力と標準エラーをファイルへ分けて保存する。終了コードは Client のものをそのまま返す。
# 引数や前提が足りないときは、docker を呼ばずに 2 を返す。
# Why: 環境変数の名前と値は、実行の前に全部検査する。途中の不正で一部だけ実行されると、結果の解釈が難しくなるため。
# Why not: 値をシェル文字列へ連結する。記号や空白を含む値が、コマンドとして解釈されるのを避けるため。
swsc_client_once_env() { # 実行ディレクトリ 実行ID ベースURL 標準出力の保存先 標準エラーの保存先 [NAME=VALUE...]
  if [ "$#" -lt 5 ]; then
    printf 'FAIL: 引数が足りない（実行ディレクトリ、実行ID、ベースURL、標準出力の保存先、標準エラーの保存先）\n' >&2
    return 2
  fi
  _env_run=$1
  _env_id=$2
  _env_url=$3
  _env_out=$4
  _env_err=$5
  shift 5
  if [ -z "$_env_out" ] || [ -z "$_env_err" ]; then
    printf 'FAIL: 標準出力と標準エラーの保存先を指定する\n' >&2
    return 2
  fi
  if [ ! -f "$_env_run/swsc-client-$_env_id.args" ]; then
    printf 'FAIL: 起動情報が無い: swsc-client-%s\n' "$_env_id" >&2
    return 2
  fi
  # Why: 改行の判定に使う。case のパターンへ直接書くと、改行の扱いが読みにくくなるため。
  _nl=$(printf '\n_')
  _nl=${_nl%_}
  for _kv in "$@"; do
    # Why: 値は表示しない。認証情報を含みうる値を、エラーに出さないため。
    case $_kv in
      *"$_nl"* | *[[:cntrl:]]*)
        printf 'FAIL: 環境変数の指定に制御文字（改行を含む）がある。値は表示しない\n' >&2
        return 2
        ;;
    esac
    case $_kv in
      *=*) ;;
      *)
        printf 'FAIL: 環境変数の指定が NAME=VALUE の形ではない\n' >&2
        return 2
        ;;
    esac
    _name=${_kv%%=*}
    # Why: 名前が数字で始まる、または記号を含むと、docker run が環境変数として受け付けないため。
    case $_name in
      '' | [0-9]* | *[!A-Za-z0-9_]*)
        printf 'FAIL: 環境変数の名前が不正（英字かアンダースコアで始まる英数字とアンダースコアだけ）\n' >&2
        return 2
        ;;
    esac
  done
  _rc=0
  swsc_client_once "$_env_run" "$_env_id" "$_env_url" "$@" >"$_env_out" 2>"$_env_err" || _rc=$?
  return "$_rc"
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
  # Why: ロックは取ってから trap を張る。取れないときに stop を呼ぶと、他の実行の swsc- を止めるため。
  swsc_lock_enter || return 1
  _sig=0
  trap '_sig=130; exit 130' INT
  trap '_sig=143; exit 143' TERM
  trap '_t=$?; if [ "$_sig" -ne 0 ]; then swsc_stop >/dev/null 2>&1 || true; fi; swsc_lock_leave || [ "$_t" -ne 0 ] || _t=1; exit "$_t"' EXIT
  _rc=0
  swsc_test_run || _rc=$?
  return "$_rc"
}

# test:ci。start が失敗しても test を飛ばし、collect、stop の順で必ず呼ぶ。終了コードは test か start の値。
# EXIT の trap は、INT と TERM で本体に届かなかった場合の最終防衛に限る（_done で二重実行を防ぐ）。
swsc_test_ci_main() {
  # Why: ロックはトップレベルで1回だけ取る。配下の swsc_start_main は SWSC_LOCK_HELD を見て取り直さない。
  swsc_lock_enter || return 1
  _done=0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '_t=$?; if [ "$_done" -eq 0 ]; then swsc_collect || true; swsc_stop || true; fi; swsc_lock_leave || [ "$_t" -ne 0 ] || _t=1; exit "$_t"' EXIT
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

# test:ci の名前指定。M08 の代表4シナリオから選んだものだけを、test:ci のロックの下で実行する。
# Why: 起動、実行、収集、停止は tests/m08-e2e-suite.sh が持つ。ここは名前の検査、ロック、子への引き渡しだけを行う。
# Why: 子には SWSC_LOCK_HELD=1 を渡し、ロックを二重に取らない（test:ci の規約）。
swsc_test_ci_scenarios() { # シナリオ名...
  for _n in "$@"; do
    case $_n in
      normal | error-500-then-200 | ratelimit-429 | slow-5000) ;;
      *)
        printf 'FAIL: 不明なシナリオ: %s（normal、error-500-then-200、ratelimit-429、slow-5000 から選ぶ）\n' "$_n" >&2
        return 2
        ;;
    esac
  done
  swsc_lock_enter || return 1
  # Why: 子はバックグラウンドで起動して wait する。前景で動かすと、sh は子が終わるまで trap を処理せず、
  # 親だけが TERM で止められたときにロックが残り、子が孤児になるため（evidence-code-review の MUST）。
  # 信号を受けたら子へ TERM を送り、子の後始末（collect、stop）を待ってからロックを解放する。
  _swsc_ci_child=
  trap '_swsc_ci_stop_child; exit 130' INT
  trap '_swsc_ci_stop_child; exit 143' TERM
  trap '_t=$?; _swsc_ci_stop_child; swsc_lock_leave || [ "$_t" -ne 0 ] || _t=1; exit "$_t"' EXIT
  swsc_test_ci_scenarios_child "$@" &
  _swsc_ci_child=$!
  _rc=0
  wait "$_swsc_ci_child" || _rc=$?
  _swsc_ci_child=
  exit "$_rc"
}

# test:ci の名前指定の子。M08 の smoke を、親のロックの下（SWSC_LOCK_HELD=1）で動かす。
# Why: 関数に分けるのは、unit で子を差し替えて、信号とロックの扱いだけを確かめるため。
swsc_test_ci_scenarios_child() { # シナリオ名...
  SWSC_LOCK_HELD=1 exec sh "$SWSC_ROOT/tests/m08-e2e-suite.sh" smoke "$@"
}

# 子が動いていれば TERM を送り、終わるまで待つ。動いていなければ何もしない。冪等。
_swsc_ci_stop_child() {
  if [ -n "${_swsc_ci_child:-}" ]; then
    kill -TERM "$_swsc_ci_child" 2>/dev/null || true
    wait "$_swsc_ci_child" 2>/dev/null || true
    _swsc_ci_child=
  fi
}

# 停止。接頭辞とラベルの両方が一致するものだけを、依存の順に消す。冪等（対象が無ければ0）。
swsc_stop() {
  swsc_runner_remove_managed
}

# 管理対象（接頭辞 swsc- とラベル swsc.managed=true の両方に一致）が残っていなければ0。
# 残っていれば名前を標準エラーに示して1。Docker の呼び出しが失敗したときも1にし、残存なしと区別する。
# Why: runner の後始末と同じ基準で数えるため。片方だけ一致するものは、他のプロジェクトの資源として数えない。
# Why not `|| true`: Docker が失敗したときに「残存なし」と誤認させないため。
swsc_check_managed_empty() {
  _ps=$(docker ps -a --filter "label=$SWSC_LABEL" --format '{{.Names}}') || {
    printf 'FAIL: docker ps に失敗したため、管理対象の残存を確かめられない\n' >&2
    return 1
  }
  _nets=$(docker network ls --filter "label=$SWSC_LABEL" --format '{{.Name}}') || {
    printf 'FAIL: docker network ls に失敗したため、管理対象の残存を確かめられない\n' >&2
    return 1
  }
  _rc=0
  while read -r _name; do
    case $_name in
      "$SWSC_PREFIX"*)
        printf 'FAIL: 管理対象のコンテナが残っている: %s\n' "$_name" >&2
        _rc=1
        ;;
    esac
  done <<EOF
$_ps
EOF
  while read -r _name; do
    case $_name in
      "$SWSC_PREFIX"*)
        printf 'FAIL: 管理対象のネットワークが残っている: %s\n' "$_name" >&2
        _rc=1
        ;;
    esac
  done <<EOF
$_nets
EOF
  return "$_rc"
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

# T2601: 固定ポート（8080、3128、4566）を、同時に1つの実行だけが使うためのロック。
# Why: ホスト全体の資源なので、並列の実行が互いのポートを壊さないようにするため。
# Why not: $TMPDIR に置く。プロセスや端末ごとに異なり、別のシェル間で排他が効かないため。
# Why not: 古いロックの自動削除。実行中の他者のロックを壊すため。利用者が確かめてから手動で消す。

# ロックを取る。取れれば0。既にある、または親が無くて作れなければ標準エラーに示して1。
# Why: mkdir は既存のときだけ失敗するので、同時に取れるのは1つだけになる。親は作らない（場所の誤りを隠さないため）。
swsc_lock_acquire() {
  _lock=${SWSC_LOCK_DIR:-/tmp/swsc-e2e-ports.lock}
  if ! mkdir "$_lock" 2>/dev/null; then
    if [ -d "$_lock" ]; then
      _owner=
      if [ -f "$_lock/owner" ]; then
        _owner=$(tr '\n' ' ' <"$_lock/owner")
      fi
      printf 'FAIL: 固定ポートのロックが既にある: %s（所有者: %s）\n' "$_lock" "${_owner:-不明}" >&2
      printf '確認: ls -ld %s で実行中の e2e と管理対象コンテナを見て、実行中でないことを確かめてから rmdir %s で手動で消す。\n' \
        "$_lock" "$_lock" >&2
    else
      printf 'FAIL: 固定ポートのロックを作れない（親ディレクトリが無い等）: %s\n' "$_lock" >&2
    fi
    return 1
  fi
  # Why: 開始時刻は、取り残されたロックが古いかどうかを利用者が判断する材料になるため。
  if ! printf '%s\n%s\n' "$$" "$(date '+%Y-%m-%dT%H:%M:%S%z')" >"$_lock/owner"; then
    # Why: 所有者を書けなかったロックは、誰のものか判らないので残さない。
    rm -f "$_lock/owner"
    rmdir "$_lock"
    printf 'FAIL: ロックの所有者を書けなかった: %s\n' "$_lock" >&2
    return 1
  fi
}

# 自分（$$）が取ったロックだけを解放する。解放できれば0。対象が違えば何も消さず1。
# Why: 他者のロックを消すと、その実行中に別の実行が同じポートへ入り込むため。
swsc_lock_release() {
  _lock=${SWSC_LOCK_DIR:-/tmp/swsc-e2e-ports.lock}
  if [ ! -f "$_lock/owner" ] || [ "$(sed -n 1p "$_lock/owner")" != "$$" ]; then
    printf 'FAIL: ロックの所有者ではないため解放しない: %s\n' "$_lock" >&2
    return 1
  fi
  # Why not: rm -rf。中身を問わず消すと、想定外のファイルまで道連れにするため。owner だけを消してから rmdir する。
  rm -f "$_lock/owner" || return 1
  rmdir "$_lock"
}

# 入口（start、test、test:ci、contract）の最初に呼ぶ。取れれば0、取れなければ標準エラーに示して1。
# 取れなかった入口は、trap も後始末も設定せずに止まる（他の実行の swsc- を止めないため）。
# Why: 同じシェルの中で2回取らないよう SWSC_LOCK_HELD を見る。test:ci のように入口が入れ子で呼ぶ
#      操作でも、取得は1回に保てるため。export しないのは、子プロセスが自分の取ったロックと誤認しないため。
swsc_lock_enter() {
  if [ "${SWSC_LOCK_HELD:-0}" = 1 ]; then
    return 0
  fi
  swsc_lock_acquire || return 1
  SWSC_LOCK_HELD=1
  _SWSC_LOCK_OWNED=1
}

# 自分が取ったロックだけを解放する。取っていなければ何もせず0。解放に失敗したら1。
# Why: 呼び出し元は、後始末（stop、collect）の後で呼ぶ。先に消すと、後始末の最中に別の実行が入るため。
# Why not `|| true`: 解放できなかったロックを残ったまま成功扱いにしないため。呼び出し元が終了コードに反映する。
swsc_lock_leave() {
  if [ "${_SWSC_LOCK_OWNED:-0}" != 1 ]; then
    return 0
  fi
  _SWSC_LOCK_OWNED=0
  SWSC_LOCK_HELD=0
  swsc_lock_release
}

# 指定したポートが全て空いていれば0。使用中のポート番号を標準エラーに出し、1を返す。
# Why: 引数を先に全部検査してから確かめる。不正な番号を、空きの判定に混ぜないため。
# Why not: 1つ目で止める。使用中のポートを一度に全部示すと、利用者が一回で対処できるため。
swsc_check_ports_free() { # ポート番号...
  if [ "$#" -eq 0 ]; then
    printf 'FAIL: 確認するポート番号を指定する\n' >&2
    return 1
  fi
  for _p in "$@"; do
    case $_p in
      '' | *[!0-9]*)
        printf 'FAIL: ポート番号が不正（数字だけで指定する）: %s\n' "$_p" >&2
        return 1
        ;;
    esac
    if [ "$_p" -lt 1 ] || [ "$_p" -gt 65535 ]; then
      printf 'FAIL: ポート番号が範囲外（1〜65535）: %s\n' "$_p" >&2
      return 1
    fi
  done
  _rc=0
  for _p in "$@"; do
    if swsc_port_in_use "$_p"; then
      printf 'FAIL: ポート %s は使用中\n' "$_p" >&2
      _rc=1
    fi
  done
  return "$_rc"
}

# Squid の access log に、指定した各文字列が含まれれば0。1つでも無ければ1。
# Why: grep -F で固定文字列として探す。パターンをシェルや sh -c に渡すと、* や $( ) が評価されるため。
# Why: 不一致と取得失敗を別の文言にする。前者は検査の結果、後者は環境の問題で、利用者の対処が違うため。
# Why: access log のパスは squid-config/squid.conf の access_log 行（/var/log/squid/access.log）と同じ値にする。
# Why not: 既定のパスを推測する。設定ファイルと違う場所を読むと、空や古い記録で誤って通るため。
swsc_squid_log_check() { # パターン...
  if [ "$#" -eq 0 ]; then
    printf 'FAIL: 検査するパターンを1つ以上指定する\n' >&2
    return 1
  fi
  # Why: 改行を含むパターンは grep -F が複数のパターンとして扱うため、一致の意味が変わる。拒否する。
  _nl=$(printf '\n_')
  _nl=${_nl%_}
  for _p in "$@"; do
    case $_p in
      '')
        printf 'FAIL: 空のパターンは指定できない\n' >&2
        return 1
        ;;
      *"$_nl"*)
        printf 'FAIL: 改行を含むパターンは指定できない\n' >&2
        return 1
        ;;
    esac
  done
  _log=$(docker exec "${SWSC_PREFIX}squid" cat /var/log/squid/access.log) || {
    printf 'FAIL: Squid の access log を取得できない（docker exec の失敗）\n' >&2
    return 1
  }
  _rc=0
  for _p in "$@"; do
    if ! printf '%s\n' "$_log" | grep -Fq -- "$_p"; then
      printf 'FAIL: Squid の access log に一致しない: %s\n' "$_p" >&2
      _rc=1
    fi
  done
  return "$_rc"
}
