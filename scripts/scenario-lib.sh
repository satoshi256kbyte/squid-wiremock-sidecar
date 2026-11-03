#!/bin/sh
# M07 のシナリオ名の解決と静的検査を行う共有部品。
# 直接実行せず、利用側が . で読み込む。読み込んだだけでは何も実行しない。
# 関数はリポジトリのルートで呼ぶ。既定のマッピングの場所は wiremock-scenarios/mappings とする。
#
# POSIX sh のみを使う。JSON の解析は M03 と同じ python3 に任せ、値は引数で渡す。
# シェルの展開で Python のコードを組み立てると、名前に含まれる文字がコードとして解釈されるため、
# コードは固定の文字列にして、名前は sys.argv で受け取る。

# マッピングを読み、動作ごとに判定する。終了コードは呼び出し側へそのまま返す。
# 第1引数は動作（resolve、names、check）、第2引数はマッピングのディレクトリ、第3引数は名前。
_scenario_py() {
  python3 - "$@" <<'PY'
import json
import re
import sys
from pathlib import Path

# 名前の形式は fullmatch で判定する。re.match の $ は末尾の改行を許すため使わない。
NAME_RE = re.compile(r"[a-z0-9][a-z0-9-]*")
# 標準エラーへ出す文字列から、制御文字を取り除くための正規表現。
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")

mode = sys.argv[1]
mappings_dir = Path(sys.argv[2])
name_arg = sys.argv[3] if len(sys.argv) > 3 else ""


def say(message):
    sys.stderr.write(CONTROL_RE.sub("", message) + "\n")


def fail(message, code=1):
    say(message)
    sys.exit(code)


def load_stubs():
    stubs = []
    # 並びを固定し、同じ入力で同じ結果になるようにする。
    for path in sorted(mappings_dir.glob("*.json")):
        try:
            with path.open(encoding="utf-8") as stream:
                stub = json.load(stream)
        except (OSError, ValueError):
            fail(f"invalid mapping file: {path.name}")
        if not isinstance(stub, dict):
            fail(f"mapping is not an object: {path.name}")
        stubs.append((path.name, stub))
    return stubs


def route(stub):
    request = stub.get("request")
    if not isinstance(request, dict):
        return (None, None)
    return (request.get("method"), request.get("urlPath"))


def known_names(stubs):
    return sorted({s["name"] for _, s in stubs if isinstance(s.get("name"), str)})


def resolve(stubs):
    if not NAME_RE.fullmatch(name_arg):
        matches = []
    else:
        matches = [(f, s) for f, s in stubs if s.get("name") == name_arg]

    if not matches:
        say(f"unknown scenario: {name_arg}")
        say("known scenarios:")
        for known in known_names(stubs):
            say(f"  {known}")
        sys.exit(2)

    routes = {route(s) for _, s in matches}
    if len(routes) > 1:
        fail(f"scenario {name_arg} has conflicting method or urlPath in its stubs")
    method, url_path = routes.pop()
    if not isinstance(url_path, str):
        fail(f"scenario {name_arg} has no request.urlPath")
    print(url_path)


def names(stubs):
    for name in known_names(stubs):
        print(name)


def check(stubs):
    errors = []

    if not stubs:
        errors.append("no mapping files found")

    # 名前ごとの宛先と、シナリオグループごとのスタブを集める。
    routes_by_name = {}
    groups = {}
    entries_by_route = {}

    for file_name, stub in stubs:
        request = stub.get("request")
        response = stub.get("response")
        if not isinstance(request, dict) or not isinstance(request.get("method"), str) \
                or not isinstance(request.get("urlPath"), str):
            errors.append(f"{file_name}: request.method と request.urlPath が必要")
            continue
        if not isinstance(response, dict) or "status" not in response:
            errors.append(f"{file_name}: response.status が必要")

        this_route = route(stub)
        scenario = stub.get("scenarioName")
        name = stub.get("name")

        if name is not None:
            if not isinstance(name, str) or not NAME_RE.fullmatch(name):
                errors.append(f"{file_name}: name の形式が不正")
            else:
                routes_by_name.setdefault(name, set()).add(this_route)

        # 部分指定: 状態を持つのに scenarioName が無いスタブは、グループに入れられず検査を逃れる
        if ("requiredScenarioState" in stub or "newScenarioState" in stub) and scenario is None:
            errors.append(f"{file_name}: 状態を持つのに scenarioName が無い")
        if scenario is not None:
            groups.setdefault(scenario, []).append((file_name, stub))

        entries_by_route.setdefault(this_route, []).append((file_name, scenario))

    for name, routes in routes_by_name.items():
        if len(routes) > 1:
            errors.append(f"name {name} が複数の宛先を持つ")

    for scenario, members in groups.items():
        # 状態の網羅: 開始状態の Started がちょうど1件
        started = [f for f, s in members if s.get("requiredScenarioState") == "Started"]
        if len(started) != 1:
            errors.append(f"{scenario}: Started のスタブが {len(started)} 件（1件であること）")

        states = {s.get("requiredScenarioState") for _, s in members}
        for file_name, stub in members:
            if "requiredScenarioState" not in stub:
                errors.append(f"{file_name}: requiredScenarioState が無い")
            # 遷移の到達性: 遷移先は、どれかのスタブの開始状態として現れる
            if "newScenarioState" in stub and stub["newScenarioState"] not in states:
                errors.append(f"{file_name}: 遷移先 {stub['newScenarioState']} を待つスタブが無い")

        # 宛先の一致と名前の一致: グループ内は同じ method、urlPath、name を持つ
        if len({route(s) for _, s in members}) > 1:
            errors.append(f"{scenario}: グループ内で method または urlPath が一致しない")
        group_names = {s.get("name") for _, s in members}
        if len(group_names) > 1 or None in group_names:
            errors.append(f"{scenario}: グループ内で name が一致しない、または無い")

    # パスの重複: 同じ method と urlPath は、同じシナリオグループの中にだけ現れてよい
    for this_route, entries in entries_by_route.items():
        if len(entries) < 2:
            continue
        scenarios = {scenario for _, scenario in entries}
        if None in scenarios or len(scenarios) > 1:
            files = ", ".join(f for f, _ in entries)
            errors.append(f"宛先の重複 {this_route[0]} {this_route[1]}: {files}")

    for error in errors:
        say(f"scenario check: {error}")
    if errors:
        sys.exit(1)


stubs = load_stubs()
if mode == "resolve":
    resolve(stubs)
elif mode == "names":
    names(stubs)
elif mode == "check":
    check(stubs)
else:
    fail(f"unknown mode: {mode}", 3)
PY
}

# 名前から宛先のパスを出力する。未定義と形式違反は終了コード2、宛先の食い違いは1。
scenario_path() { # 名前 [マッピングのディレクトリ]
  _scenario_py resolve "${2:-wiremock-scenarios/mappings}" "${1-}"
}

# 定義済みの名前を昇順で1行ずつ出力する。name を持つスタブだけを数える。
scenario_names() { # [マッピングのディレクトリ]
  _scenario_py names "${1:-wiremock-scenarios/mappings}" ""
}

# 状態グループと宛先の静的検査。不正なら理由を標準エラーへ出して終了コード1を返す。
scenario_check_static() { # [マッピングのディレクトリ]
  _scenario_py check "${1:-wiremock-scenarios/mappings}" ""
}

# WireMock を初期状態へ戻す。主経路は POST /__admin/reset の1回だけ（reset-experiment.md の5章）。
# コンテナの再起動や個別の管理APIは使わない。応答が 200 以外なら終了コード1を返す。
wiremock_reset() { # （引数なし。宛先は WIREMOCK_URL）
  _base=${WIREMOCK_URL:-http://127.0.0.1:8080}
  _status=$(curl --silent --show-error --connect-timeout 2 --max-time 10 --output /dev/null --write-out '%{http_code}' \
    -X POST "$_base/__admin/reset") || _status=000
  if [ "$_status" != 200 ]; then
    printf 'wiremock_reset: POST /__admin/reset の応答が 200 ではない（実測 %s）\n' "$_status" >&2
    return 1
  fi
}

# リセット後の状態を管理APIの応答から確かめる。3項目すべてが期待どおりなら 0、
# 1つでも外れるか読み取れなければ、項目名と期待値と実測値を標準エラーへ出して 1 を返す。
# 項目は reset-experiment.md の4章と6章に従う（件数は meta.total、状態は scenarios[].state）。
wiremock_verify_reset() { # [マッピングのディレクトリ]
  _dir=${1:-wiremock-scenarios/mappings}
  _base=${WIREMOCK_URL:-http://127.0.0.1:8080}
  _tmp=$(mktemp -d) || return 1
  _rc=0
  for _api in mappings requests scenarios; do
    if ! curl --fail --silent --show-error --connect-timeout 2 --max-time 10 -o "$_tmp/$_api.json" "$_base/__admin/$_api"; then
      printf 'wiremock_verify_reset: 読み取れない: __admin/%s\n' "$_api" >&2
      rm -rf "$_tmp"
      return 1
    fi
  done
  python3 - "$_dir" "$_tmp/mappings.json" "$_tmp/requests.json" "$_tmp/scenarios.json" <<'PY' || _rc=$?
import glob
import json
import os
import sys

# 数値は JSON の文字列と混同しないように int だけを受け入れる。bool は int の部分型なので除く。
def read(path, label):
    try:
        with open(path, encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, ValueError):
        sys.stderr.write(f"wiremock_verify_reset: 読み取れない: {label}\n")
        sys.exit(1)

def total_of(body, label):
    meta = body.get("meta") if isinstance(body, dict) else None
    value = meta.get("total") if isinstance(meta, dict) else None
    if not isinstance(value, int) or isinstance(value, bool):
        sys.stderr.write(f"wiremock_verify_reset: meta.total が読めない: {label}\n")
        sys.exit(1)
    return value

mappings_dir, mappings_path, requests_path, scenarios_path = sys.argv[1:5]
failures = []

# 項目1: マッピング件数がファイル数（.gitkeep は glob に含まれない）と一致する
expected_mappings = len([p for p in glob.glob(os.path.join(mappings_dir, "*.json")) if os.path.isfile(p)])
actual_mappings = total_of(read(mappings_path, "mappings"), "mappings")
if actual_mappings != expected_mappings:
    failures.append(f"マッピング件数: 期待 {expected_mappings} 実測 {actual_mappings}")

# 項目2: リクエストジャーナルが空
actual_journal = total_of(read(requests_path, "requests"), "requests")
if actual_journal != 0:
    failures.append(f"リクエストジャーナル件数: 期待 0 実測 {actual_journal}")

# 項目3: 全シナリオの状態が Started
scenarios = read(scenarios_path, "scenarios")
items = scenarios.get("scenarios") if isinstance(scenarios, dict) else None
if not isinstance(items, list):
    sys.stderr.write("wiremock_verify_reset: scenarios[] が読めない\n")
    sys.exit(1)
for item in items:
    state = item.get("state") if isinstance(item, dict) else None
    if state != "Started":
        name = item.get("name") if isinstance(item, dict) else None
        failures.append(f"シナリオ状態: {name} 期待 Started 実測 {state}")

for line in failures:
    sys.stderr.write(f"wiremock_verify_reset: {line}\n")
sys.exit(1 if failures else 0)
PY
  rm -rf "$_tmp"
  return "$_rc"
}
