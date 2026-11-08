# M09 の契約検証（contract 操作）。scripts/e2e.sh から読み込む（直接実行しない）。
# MiniStack を起動して完成版を登録し、describe で取り出して比べる（FR-904）。
# MiniStack の起動と削除は、この操作だけが担当する。
# Why: 起動と削除の責任を1か所に置き、start、test、test:ci が MiniStack に触れないようにするため。

# describe で取り出す項目。Why: ARN を返す項目を取らず、比べる項目だけに絞るため（FR-918）。
SWSC_DESCRIBE_QUERY='taskDefinition.{networkMode: networkMode, containerDefinitions: containerDefinitions[].{name: name, image: image, essential: essential, environment: environment, portMappings: portMappings, dependsOn: dependsOn, healthCheck: healthCheck}}'

# 段階名を示して止まる。標準エラーに出す。
swsc_contract_fail() { # 段階名 理由
  printf 'FAIL: contract の段階「%s」で止まった: %s\n' "$1" "$2" >&2
}

# 終了時の後始末。EXIT の trap から呼ぶ（成功、失敗、INT、TERM のどれでも）。
# Why: 失敗時は collect を先に呼ぶ。消してからでは、MiniStack のログが残らないため。
# Why not: 成功時に collect を呼ばない。ログは失敗の調べに使うもので、成功の度に集めると遅くなるため。
swsc_contract_exit() { # 終了コード
  _rc=$1
  if [ "$_rc" -ne 0 ] && type swsc_collect >/dev/null 2>&1; then
    swsc_collect || true
  fi
  swsc_contract_remove_ministack
  # Why: ロックは MiniStack を消した後に解放する。解放の前に別の実行が入ると、同じ4566を取り合うため。
  swsc_lock_leave || [ "$_rc" -ne 0 ] || _rc=1
  exit "$_rc"
}

# 自分が作った MiniStack だけを消す。名前の完全一致とラベルの両方で絞る。
# Why: 名前だけで消すと、利用者が同じ名前で作った別のコンテナを強制削除してしまう（security-review の Low）。
# Why not: 同名の別コンテナは消さない。後の docker run が名前の衝突で失敗し、「起動」の段階で原因が分かる。
swsc_contract_remove_ministack() {
  _ids=$(docker ps -aq --filter "name=^${SWSC_MINISTACK_NAME}\$" --filter "label=$SWSC_LABEL" 2>/dev/null) || return 0
  for _id in $_ids; do
    docker rm -f "$_id" >/dev/null 2>&1 || true
  done
  return 0
}

# ECS の応答（list-task-definitions）を、上限まで待つ。上限は SWSC_CONTRACT_WAIT_SECONDS（既定120秒）。
# Why: 応答を待つ上限を持ち、MiniStack が起動しないときに無限に待たないため。
swsc_contract_wait_ready() {
  _limit=$(($(date +%s) + ${SWSC_CONTRACT_WAIT_SECONDS:-120}))
  while :; do
    if swsc_aws ecs list-task-definitions >/dev/null 2>&1; then
      return 0
    fi
    if [ "$(date +%s)" -ge "$_limit" ]; then
      return 1
    fi
    sleep 2
  done
}

# 契約検証の本体。手順は plan.md 3.5 の表に従う。成功なら 0、失敗なら 1。
# 前提検査（認証情報を含む）は、呼び出し元（scripts/e2e.sh）が済ませている。
contract_main() {
  # Why: ロックは trap より前に取る。取れないときに MiniStack の削除を走らせると、他の実行の4566を壊すため。
  swsc_lock_enter || return 1
  trap 'swsc_contract_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # 1. 既存の swsc-ministack を消してから、ポートを確かめる（自分の残りを使用中と誤認しないため）
  swsc_contract_remove_ministack
  if swsc_port_in_use "$SWSC_MINISTACK_PORT"; then
    swsc_contract_fail ポート確認 "ポート${SWSC_MINISTACK_PORT}が使用中（swsc-以外のコンテナかプロセス。旧基盤（docker-compose）の可能性がある）"
    return 1
  fi

  # 2. 完成版を、start と同じ入力で作る
  swsc_prepare_dir "$SWSC_E2E_DIR" || {
    swsc_contract_fail 完成版 "出力先を用意できない（上の行を確かめる）"
    return 1
  }
  swsc_render_local "$SWSC_E2E_DIR/taskdef.json" || {
    swsc_contract_fail 完成版 "生成に失敗した"
    return 1
  }

  # 3. MiniStack を起動する。ソケットは渡さず、公開は127.0.0.1だけにする（NFR-906）
  docker run -d --name "$SWSC_MINISTACK_NAME" --label "$SWSC_LABEL" --label swsc.role=ministack \
    -p "127.0.0.1:${SWSC_MINISTACK_PORT}:4566" "$SWSC_MINISTACK_IMAGE" >/dev/null || {
    swsc_contract_fail 起動 "MiniStack のコンテナを作れない（イメージ ${SWSC_MINISTACK_IMAGE} を確かめる）"
    return 1
  }

  # 4. ECS の応答を待つ（確認先は list-task-definitions。G2で空の一覧を返した）
  swsc_contract_wait_ready || {
    swsc_contract_fail 起動待ち "MiniStack が ECS の応答を返さない（上限${SWSC_CONTRACT_WAIT_SECONDS:-120}秒）"
    return 1
  }

  # 5. 登録する。ARN は取らず、リビジョンだけを取る
  _rev=$(swsc_aws ecs register-task-definition --cli-input-json "file://$SWSC_E2E_DIR/taskdef.json" \
    --query taskDefinition.revision --output text) || {
    swsc_contract_fail 登録 "register-task-definition が失敗した"
    return 1
  }
  case $_rev in
    '' | *[!0-9]*)
      swsc_contract_fail 登録 "リビジョンを取れない"
      return 1
      ;;
  esac

  # 6. describe で、比べる項目だけを取り出す
  _jq=$(swsc_jq) || {
    swsc_contract_fail 取り出し "jq を得られない（mise install --locked を実行する）"
    return 1
  }
  _family=$("$_jq" -e -r '.family' "$SWSC_E2E_DIR/taskdef.json") || {
    swsc_contract_fail 取り出し "完成版から family を読めない"
    return 1
  }
  swsc_aws ecs describe-task-definition --task-definition "$_family:$_rev" \
    --query "$SWSC_DESCRIBE_QUERY" --output json >"$SWSC_E2E_DIR/ministack-describe.json" || {
    swsc_contract_fail 取り出し "describe-task-definition が失敗した"
    return 1
  }

  # 7. 完成版と describe を比べ、結果を残す
  python3 -B "$SWSC_ROOT/scripts/e2e-taskdef.py" compare --report "$SWSC_E2E_DIR/ministack-contract.json" \
    "$SWSC_E2E_DIR/taskdef.json" "$SWSC_E2E_DIR/ministack-describe.json" || {
    swsc_contract_fail 比較 "完成版と describe が一致しない（不一致の項目は上の行）"
    return 1
  }

  # 8. docker inspect の Mounts と公開ポートだけを残す。識別情報を消してから保存する（FR-918）
  _raw=$(docker inspect --format '{"Mounts":{{json .Mounts}},"Ports":{{json .NetworkSettings.Ports}}}' \
    "$SWSC_MINISTACK_NAME") || {
    swsc_contract_fail 検査 "docker inspect が失敗した"
    return 1
  }
  printf '%s\n' "$_raw" | swsc_mask >"$SWSC_E2E_DIR/ministack-inspect.json"
  return 0
}
