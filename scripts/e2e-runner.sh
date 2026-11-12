# ローカルと CI のランナー。scripts/e2e.sh から読み込む（直接実行しない）。
# 前提: 先に e2e-lib.sh を読み込み、SWSC_ROOT を設定しておく。
#
# 完成版のタスク定義を ECS のエミュレータ（fakecloud）へ登録し、run-task でタスクとして起動する。
# 範囲は register-task-definition と run-task だけで、create-service などサービスとしての起動は対象外。
# 呼び出しは curl で行い、AWS CLI と認証情報は使わない。
#
# Why not 同じタスクの 127.0.0.1 共有: fakecloud は同じタスクのコンテナを別の名前空間で起動する（実測）。
# そのため Client のプロキシは Squid に付けた別名（swsc-squid）へ向ける。AWS 用の完成版とは環境変数の値だけが違う。

# 待機の上限（秒）。Why: 既定は120秒。検査が失敗経路を数秒で確かめられるよう、上書きだけを許す。
SWSC_WAIT_SECONDS=${SWSC_WAIT_SECONDS:-120}

# ECS の API を呼ぶ。Why: エミュレータは署名を検証しないため、curl の JSON 呼び出しで足りる。
swsc_ecs_call() { # アクション JSON
  curl -sS --fail-with-body --max-time 60 -X POST "$SWSC_FAKECLOUD_URL/" \
    -H 'Content-Type: application/x-amz-json-1.1' \
    -H "X-Amz-Target: AmazonEC2ContainerServiceV20141113.$1" -d "$2"
}

# コンテナが止まっているか。存在しない場合も止まっているとみなす。
# Why: 起動したコンテナが落ちたとき、待機の上限まで待たずに、原因の段階で止めるため。
# Why not 状態の文字列を網羅しない: 止まっていると言えるのは Running が false のときだけにする。
swsc_runner_stopped() { # インスタンス名
  _running=$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null) || return 0
  [ "$_running" = false ]
}

# 指定の URL が応答するまで待つ。待っている間にコンテナが止まったら、待たずに失敗にする。
swsc_runner_wait_url() { # コンテナ名 URL 表示名
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  while ! curl -fsS --max-time 2 -o /dev/null "$2"; do
    if swsc_runner_stopped "$1"; then
      printf 'FAIL: %s が停止している（応答を待てない）\n' "$3" >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: %s が %s 秒以内に応答しない\n' "$3" "$SWSC_WAIT_SECONDS" >&2
      return 1
    fi
    sleep 1
  done
}

# WireMock は、既存のシナリオを読み取り専用で受け、ホストの 127.0.0.1:8080 だけに公開する。
# Why: 他のホストには公開しない。タスクのネットワークへは、タスクごとに接続する（swsc_task_attach）。
swsc_runner_start_wiremock() {
  docker run -d --name swsc-wiremock --label "$SWSC_LABEL" --label swsc.role=wiremock \
    -p "127.0.0.1:${SWSC_MOCK_PORT}:8080" \
    -v "$SWSC_ROOT/wiremock-scenarios:/home/wiremock:ro" \
    "$SWSC_WIREMOCK_IMAGE" >/dev/null
}

# イメージの置き場。Why: エミュレータは、ローカルにしか無いイメージの pull を拒否する（TaskFailedToStart）。
swsc_runner_start_registry() {
  docker run -d --name swsc-registry --label "$SWSC_LABEL" --label swsc.role=registry \
    -p "127.0.0.1:${SWSC_REGISTRY_PORT}:5000" "$SWSC_REGISTRY_IMAGE" >/dev/null
}

# ビルドしたイメージをレジストリへ置く。タスク定義は localhost:<ポート>/... の参照を使う。
swsc_runner_push_images() {
  for _i in "$SWSC_LOCAL_CLIENT_NAME" "$SWSC_LOCAL_SQUID_NAME"; do
    docker tag "$_i:e2e" "$SWSC_REGISTRY_HOST/$_i:e2e" || return 1
    docker push "$SWSC_REGISTRY_HOST/$_i:e2e" >/dev/null || return 1
  done
}

# エミュレータ。Docker のソケットを渡して、ECS のタスクをコンテナとして実行させる。
# Why: ソケットを渡すとホストの Docker を操作できる。127.0.0.1 だけに公開し、CI は使い捨てのランナーで動かす。
swsc_runner_start_fakecloud() {
  docker run -d --name swsc-fakecloud --label "$SWSC_LABEL" --label swsc.role=fakecloud \
    -p "127.0.0.1:${SWSC_FAKECLOUD_PORT}:4566" \
    -v /var/run/docker.sock:/var/run/docker.sock --add-host host.docker.internal:host-gateway \
    "$SWSC_FAKECLOUD_IMAGE" >/dev/null
}

# クラスタを作り、完成版のタスク定義を登録する。
swsc_runner_register() { # 完成版
  swsc_ecs_call CreateCluster '{"clusterName":"default"}' >/dev/null || return 1
  swsc_ecs_call RegisterTaskDefinition "$(cat "$1")" >/dev/null || {
    printf 'FAIL: タスク定義を登録できない\n' >&2
    return 1
  }
}

# 起動の順序を固定する。Why: WireMock とレジストリを先に待ち、エミュレータが使うイメージを置いてから登録する。
swsc_runner_start_all() { # 完成版
  swsc_runner_start_wiremock || return 1
  swsc_runner_wait_url swsc-wiremock "http://127.0.0.1:${SWSC_MOCK_PORT}/__admin/mappings" WireMock || return 1
  swsc_runner_start_registry || return 1
  swsc_runner_wait_url swsc-registry "http://127.0.0.1:${SWSC_REGISTRY_PORT}/v2/" レジストリ || return 1
  swsc_runner_push_images || {
    printf 'FAIL: イメージをレジストリへ置けない\n' >&2
    return 1
  }
  swsc_runner_start_fakecloud || return 1
  swsc_runner_wait_url swsc-fakecloud "$SWSC_FAKECLOUD_URL/_fakecloud/health" エミュレータ || return 1
  swsc_runner_register "$1"
}

# 指定のコンテナが healthy になるまで待つ。unhealthy は待たずに失敗させる。
swsc_runner_wait_healthy() { # コンテナ名
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

# ---------------------------------------------------------------------------
# タスクの起動と後始末。1回の Client 実行につき、1つのタスクを起動する。
# ---------------------------------------------------------------------------

# Client の環境変数の上書き（NAME=VALUE...）を、RunTask の本文にする。
# Why: 値は python の引数で渡し、コードに埋め込まない。記号や空白を含む値がコードとして解釈されないため。
swsc_task_request() { # NAME=VALUE...
  python3 -B -c '
import json, sys
env = []
for kv in sys.argv[1:]:
    name, _, value = kv.partition("=")
    env.append({"name": name, "value": value})
print(json.dumps({
    "cluster": "default",
    "taskDefinition": "swsc-e2e",
    "launchType": "FARGATE",
    "networkConfiguration": {"awsvpcConfiguration": {"subnets": ["subnet-00000000"]}},
    "overrides": {"containerOverrides": [{"name": "client", "environment": env}]},
}))
' "$@"
}

# RunTask の応答からタスクIDを出す。タスクを置けなかったときは理由を標準エラーに出して1。
swsc_task_id_from() { # 応答
  printf '%s' "$1" | python3 -B -c '
import json, re, sys
d = json.load(sys.stdin)
if d.get("failures") or not d.get("tasks"):
    sys.stderr.write("FAIL: タスクを起動できない: %s\n" % json.dumps(d.get("failures")))
    sys.exit(1)
task_id = d["tasks"][0]["taskArn"].rsplit("/", 1)[-1]
# Why: タスクIDは docker のフィルタとネットワーク名に使う。16進32桁だけを通す。
if not re.fullmatch(r"[0-9a-f]{32}", task_id):
    sys.stderr.write("FAIL: タスクIDの形式が不正\n")
    sys.exit(1)
print(task_id)
'
}

# タスクのネットワークへ WireMock を接続し、Squid に別名を付ける。
# Why: エミュレータは、同じタスクのコンテナを別々の名前空間で起動し、Squid の名前を固定しない。
# Why: WireMock は Squid の起動前に接続する。Squid は起動時に WireMock の名前を引くため。
# Why: Client は dependsOn で Squid が healthy になるまで起動しない。その間に別名を付ける。
swsc_task_attach() { # タスクID
  _net=fakecloud-ecs-$1
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  until docker network inspect "$_net" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: タスクのネットワークができない\n' >&2
      return 1
    fi
    sleep 0.05
  done
  docker network connect "$_net" swsc-wiremock || return 1
  until docker inspect "$1-squid" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: Squid のコンテナができない\n' >&2
      return 1
    fi
    sleep 0.05
  done
  docker network disconnect "$_net" "$1-squid" || return 1
  docker network connect --alias swsc-squid "$_net" "$1-squid"
}

# Client のコンテナが終わるまで待ち、出力と終了コードを取る。
# Why: エミュレータは、終わったコンテナを後から消す。終わってから探すと取り逃がすため、コンテナができた時点で
# docker logs -f と docker wait を付け、終了を待つ。Squid が先に止まったら（タスクが止まったら）待たずに失敗にする。
swsc_task_wait_client() { # タスクID 標準出力の保存先 標準エラーの保存先
  _limit=$(($(date +%s) + SWSC_WAIT_SECONDS))
  until docker inspect "$1-client" >/dev/null 2>&1; do
    if swsc_runner_stopped "$1-squid"; then
      printf 'FAIL: Squid が止まり、Client が起動しない\n' >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      printf 'FAIL: Client が %s 秒以内に起動しない\n' "$SWSC_WAIT_SECONDS" >&2
      return 1
    fi
    sleep 0.05
  done
  docker logs -f "$1-client" >"$2" 2>"$3" &
  _logs_pid=$!
  SWSC_TASK_CLIENT_RC=$(docker wait "$1-client") || {
    kill "$_logs_pid" 2>/dev/null || true
    wait "$_logs_pid" 2>/dev/null || true
    printf 'FAIL: Client の終了を確認できない\n' >&2
    return 1
  }
  wait "$_logs_pid" 2>/dev/null || true
}

# タスクを起動し、Client が終わるまで待つ。タスクIDを SWSC_TASK_ID、Client の終了コードを SWSC_TASK_CLIENT_RC に残す。
# Why: 戻り値でなく変数に置く。コマンド置換の中で起動すると、親のシェルに後始末の情報が残らないため。
swsc_task_begin() { # 標準出力の保存先 標準エラーの保存先 NAME=VALUE...
  SWSC_TASK_ID=
  SWSC_TASK_CLIENT_RC=
  _bo=$1
  _be=$2
  shift 2
  _body=$(swsc_task_request "$@") || return 1
  _res=$(swsc_ecs_call RunTask "$_body") || {
    printf 'FAIL: run-task に失敗した\n' >&2
    return 1
  }
  SWSC_TASK_ID=$(swsc_task_id_from "$_res") || return 1
  mkdir -p "$SWSC_E2E_DIR/run" || return 1
  printf '%s\n' "$SWSC_TASK_ID" >>"$SWSC_E2E_DIR/run/tasks"
  swsc_task_attach "$SWSC_TASK_ID" || return 1
  swsc_task_wait_client "$SWSC_TASK_ID" "$_bo" "$_be"
}

# 調査のために、Squid のログとコンテナのログを実行ディレクトリへ追記する。
# Why: タスクごとに Squid が作り直されるため、消す前に残さないと collect で読めない。
swsc_task_save_logs() { # タスクID [Client の標準出力 Client の標準エラー]
  _d=$SWSC_E2E_DIR/run
  mkdir -p "$_d" || return 1
  for _f in access cache; do
    {
      printf '== task %s\n' "$1"
      docker exec "$1-squid" cat "/var/log/squid/$_f.log" 2>&1 || true
    } >>"$_d/squid-$_f.log"
  done
  {
    printf '== task %s squid\n' "$1"
    docker logs "$1-squid" 2>&1 || true
  } >>"$_d/containers-squid.log"
  {
    printf '== task %s client\n' "$1"
    # Why: Client のコンテナは消えていることがある。取得済みの出力から写す。
    if [ -n "${2:-}" ] && [ -f "$2" ]; then cat "$2"; fi
    if [ -n "${3:-}" ] && [ -f "$3" ]; then cat "$3"; fi
  } >>"$_d/containers-client.log"
}

# タスクのコンテナとネットワークを消す。冪等（無ければ何もしない）。
# Why: 対象は fakecloud-ecs-task=<ID> のラベルと fakecloud-ecs-<ID> のネットワークだけ。他のタスクには触れない。
swsc_task_teardown() { # タスクID
  _ids=$(docker ps -a -q --filter "label=fakecloud-ecs-task=$1") || return 1
  for _c in $_ids; do
    docker rm -f "$_c" >/dev/null || return 1
  done
  if docker network inspect "fakecloud-ecs-$1" >/dev/null 2>&1; then
    docker network disconnect -f "fakecloud-ecs-$1" swsc-wiremock >/dev/null 2>&1 || true
    # Why: コンテナを消すと、エミュレータも同じネットワークを消しにくる。先に消えた場合は成功とみなす。
    if ! docker network rm "fakecloud-ecs-$1" >/dev/null 2>&1; then
      ! docker network inspect "fakecloud-ecs-$1" >/dev/null 2>&1 || return 1
    fi
  fi
}

# Client を1回実行する。標準出力と標準エラーを分けて保存し、Client の終了コードを返す。
swsc_task_run_client() { # 標準出力の保存先 標準エラーの保存先 NAME=VALUE...
  _o=$1
  _e=$2
  shift 2
  _rc=0
  swsc_task_begin "$_o" "$_e" "$@" || _rc=1
  _tid=$SWSC_TASK_ID
  _crc=${SWSC_TASK_CLIENT_RC:-1}
  if [ -n "$_tid" ]; then
    swsc_task_save_logs "$_tid" "$_o" "$_e" || true
    swsc_task_teardown "$_tid" || _rc=1
  fi
  [ "$_rc" -eq 0 ] || return 1
  return "$_crc"
}

# 追加の Client を、同じタスクのネットワークで実行する（Squid の再起動後の確認だけに使う）。
# Why: タスクの Client は1回で終わるため。ECS を通らないので、使う範囲を再起動後の確認に限る。
swsc_task_extra_client() { # タスクID 標準出力の保存先 標準エラーの保存先 ベースURL
  docker run --rm --name "swsc-client-extra-$$" --label "$SWSC_LABEL" --label swsc.role=client \
    --network "fakecloud-ecs-$1" \
    -e "HTTP_PROXY=$SWSC_LOCAL_PROXY_URL" -e "HTTPS_PROXY=$SWSC_LOCAL_PROXY_URL" \
    -e "TEST_API_BASE_URL=$4" "$SWSC_LOCAL_CLIENT_NAME:e2e" >"$2" 2>"$3"
}

# 検査と後始末の対象を、接頭辞 swsc- とラベルの両方で絞って消す。
# Why: 他のプロジェクトのコンテナを、名前かラベルのどちらか一方だけでは選ばないため。
swsc_runner_remove_managed() {
  # タスクのコンテナとネットワーク。起動の記録と、エミュレータが覚えているタスクの両方から探す。
  _tasks=
  if [ -f "$SWSC_E2E_DIR/run/tasks" ]; then
    _tasks=$(cat "$SWSC_E2E_DIR/run/tasks")
  fi
  # Why: 自分のエミュレータのコンテナがあるときだけ問い合わせる。同じポートで動く他のプロセスの
  # タスクを、後始末の対象にしないため。
  _more=
  if docker inspect swsc-fakecloud >/dev/null 2>&1; then
    _more=$(curl -fsS --max-time 3 "$SWSC_FAKECLOUD_URL/_fakecloud/ecs/tasks" 2>/dev/null | python3 -B -c '
import json, sys
try:
    for t in json.load(sys.stdin).get("tasks", []):
        print(t["taskId"])
except ValueError:
    pass
' 2>/dev/null || true)
  fi
  for _t in $_tasks $_more; do
    case $_t in *[!0-9a-f]* | '') continue ;; esac
    swsc_task_teardown "$_t" || return 1
  done
  _list=$(docker ps -a --filter "label=$SWSC_LABEL" --format '{{.ID}} {{.Names}}') || return 1
  # Why: Client とエミュレータを、WireMock とレジストリより先に消す。
  for _want in first rest; do
    while read -r _id _name; do
      case $_name in swsc-*) ;; *) continue ;; esac
      case $_name in
        swsc-client-* | swsc-fakecloud) _k=first ;;
        *) _k=rest ;;
      esac
      [ "$_k" = "$_want" ] || continue
      docker rm -f "$_id" >/dev/null || return 1
    done <<EOF
$_list
EOF
  done
  # レジストリ用のタグ。Why: ローカルのイメージ自体は残し、レジストリの参照だけを消す。
  for _i in "$SWSC_LOCAL_CLIENT_NAME" "$SWSC_LOCAL_SQUID_NAME"; do
    docker image rm "$SWSC_REGISTRY_HOST/$_i:e2e" >/dev/null 2>&1 || true
  done
}
