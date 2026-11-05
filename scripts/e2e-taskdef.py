#!/usr/bin/env python3
"""M09 タスク定義の生成と検査（標準ライブラリだけを使う）。

完成版はテンプレートの値だけを置き換えて作る。文字列全体を置換すると JSON が壊れるため、
パース後の文字列値に対してだけ置換する（G4）。
"""

import argparse
import json
import os
import re
import sys

# 値の形式。Why: 値は JSON の文字列として埋まるため、制御文字や区切り記号を入れないように絞る。
IMAGE_RE = re.compile(r"\A[A-Za-z0-9._/:@-]{1,256}\Z")
UPSTREAM_RE = re.compile(r"\A[A-Za-z0-9_-]{1,32}\Z")
HOST_RE = re.compile(r"\A[A-Za-z0-9.-]{1,253}\Z")
DIGITS_RE = re.compile(r"\A[0-9]{1,5}\Z")
ENV_NAME_RE = re.compile(r"\A[A-Z][A-Z0-9_]*\Z")
WHOLE_PLACEHOLDER_RE = re.compile(r"\A\{\{([A-Z_]+)\}\}\Z")
LEFTOVER_RE = re.compile(r"\{\{|\}\}")

# 許可リスト。Why: 許可しない項目（volumes、secrets など）を黙って通さず、名指しで止めるため（Q-913）。
TOP_KEYS = {"family", "networkMode", "requiresCompatibilities", "cpu", "memory", "containerDefinitions"}
CONTAINER_KEYS = {"name", "image", "essential", "environment", "portMappings", "dependsOn",
                  "healthCheck", "command", "entryPoint"}
ENV_KEYS = {"name", "value"}
PORT_KEYS = {"containerPort", "protocol"}
DEPENDS_KEYS = {"containerName", "condition"}
HEALTH_KEYS = {"command", "interval", "timeout", "retries", "startPeriod"}
DEPENDS_CONDITIONS = {"START", "HEALTHY"}

PLACEHOLDER_CHECKS = {
    "CLIENT_IMAGE": ("--client-image", IMAGE_RE),
    "SQUID_IMAGE": ("--squid-image", IMAGE_RE),
    "SQUID_UPSTREAM": ("--upstream", UPSTREAM_RE),
}


MOCK_ENV_NAMES = {"SQUID_MOCK_HOST", "SQUID_MOCK_PORT"}

# docker-args の検査。Why: 名前とラベルは、停止と後始末が対象を選ぶ根拠になるため、形式を絞る。
PAUSE_NAME_RE = re.compile(r"\Aswsc-[a-z0-9-]{1,40}\Z")
RUN_ID_RE = re.compile(r"\A[A-Za-z0-9]{1,32}\Z")
CONTAINER_NAME_RE = re.compile(r"\A[a-z][a-z0-9-]{0,40}\Z")
INSTANCE_PREFIX = "swsc-"  # Why: scripts/e2e-lib.sh の SWSC_PREFIX と同じ値を、変換単体で使えるように持つ。
LABEL = "swsc.managed=true"  # Why: scripts/e2e-lib.sh の SWSC_LABEL と同じ値（停止の対象の判定に使う）。
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")


class Invalid(Exception):
    """検査に通らない入力。メッセージに値は書かず、項目の名前と理由だけを書く。"""


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as exc:
        # Why: 入力が読めないことは検査の不合格（1）ではなく、使い方の誤り（2）として区別する。
        print(f"FAIL: 入力を読めない: {path}: {type(exc).__name__}", file=sys.stderr)
        sys.exit(2)


def reject_unknown(node, allowed, where):
    for key in node:
        if key not in allowed:
            raise Invalid(f"{where} に許可されていない項目がある: {key}")


def fill(node, values):
    """値の置換。許可された名前のプレースホルダーだけを、対応する値に置き換える。"""
    if isinstance(node, dict):
        return {key: fill(value, values) for key, value in node.items()}
    if isinstance(node, list):
        return [fill(value, values) for value in node]
    if isinstance(node, str):
        match = WHOLE_PLACEHOLDER_RE.match(node)
        if match:
            name = match.group(1)
            if name not in values:
                raise Invalid(f"未知のプレースホルダー: {name}")
            return values[name]
    return node


def walk_strings(node):
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            yield from walk_strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk_strings(value)
    elif isinstance(node, str):
        yield node


def check_leftovers(doc):
    for text in walk_strings(doc):
        if LEFTOVER_RE.search(text):
            raise Invalid("置換されていないプレースホルダーが残っている")


def check_string_list(value, where):
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise Invalid(f"{where} は文字列の配列でなければならない")


def check_container(container):
    if not isinstance(container, dict):
        raise Invalid("コンテナ定義がオブジェクトではない")
    name = container.get("name", "?")
    where = f"コンテナ定義 {name}"
    reject_unknown(container, CONTAINER_KEYS, where)
    for env in container.get("environment", []):
        if not isinstance(env, dict):
            raise Invalid(f"{where} の environment が不正")
        reject_unknown(env, ENV_KEYS, f"{where} の environment")
        if not isinstance(env.get("name"), str) or not ENV_NAME_RE.match(env["name"]):
            raise Invalid(f"{where} の環境変数名が不正")
        if not isinstance(env.get("value"), str):
            raise Invalid(f"{where} の環境変数の値が文字列ではない")
    for port in container.get("portMappings", []):
        if not isinstance(port, dict):
            raise Invalid(f"{where} の portMappings が不正")
        reject_unknown(port, PORT_KEYS, f"{where} の portMappings")
        if not isinstance(port.get("containerPort"), int) or port.get("protocol") != "tcp":
            raise Invalid(f"{where} の portMappings の形式が不正")
    for dep in container.get("dependsOn", []):
        if not isinstance(dep, dict):
            raise Invalid(f"{where} の dependsOn が不正")
        reject_unknown(dep, DEPENDS_KEYS, f"{where} の dependsOn")
        if dep.get("condition") not in DEPENDS_CONDITIONS:
            raise Invalid(f"{where} の dependsOn の条件は START か HEALTHY だけ")
    if "healthCheck" in container:
        health = container["healthCheck"]
        if not isinstance(health, dict):
            raise Invalid(f"{where} の healthCheck が不正")
        reject_unknown(health, HEALTH_KEYS, f"{where} の healthCheck")
        command = health.get("command")
        if not (isinstance(command, list) and len(command) == 2 and command[0] == "CMD-SHELL"):
            raise Invalid(f"{where} の healthCheck は CMD-SHELL の形式だけ")
        for key in ("interval", "timeout", "retries", "startPeriod"):
            if not isinstance(health.get(key), int):
                raise Invalid(f"{where} の healthCheck の {key} が整数ではない")
    for key in ("command", "entryPoint"):
        if key in container:
            check_string_list(container[key], f"{where} の {key}")


def check_structure(doc):
    if not isinstance(doc, dict):
        raise Invalid("タスク定義がオブジェクトではない")
    reject_unknown(doc, TOP_KEYS, "トップレベル")
    containers = doc.get("containerDefinitions")
    if not isinstance(containers, list) or not containers:
        raise Invalid("containerDefinitions が空または配列ではない")
    for container in containers:
        check_container(container)


def production_findings(doc):
    """本番向けの条件（FR-909 の層2、層3）。不合格の理由には環境変数名だけを書き、値は書かない。"""
    findings = []
    containers = doc.get("containerDefinitions")
    if not isinstance(containers, list):
        return ["containerDefinitions が配列ではない"]
    upstream_seen = False
    for container in containers:
        if not isinstance(container, dict):
            findings.append("コンテナ定義の形式が不正")
            continue
        name = container.get("name", "?")
        env_list = container.get("environment", [])
        if not isinstance(env_list, list):
            findings.append(f"{name}: environment が配列ではない")
            continue
        for env in env_list:
            if not isinstance(env, dict):
                continue
            env_name = env.get("name")
            if env_name == "SQUID_UPSTREAM":
                upstream_seen = True
                if env.get("value") != "direct":
                    findings.append(f"{name}: SQUID_UPSTREAM の値が direct ではない")
            elif env_name in MOCK_ENV_NAMES:
                findings.append(f"{name}: {env_name} が残っている")
    if not upstream_seen:
        findings.append("SQUID_UPSTREAM が設定されていない")
    return findings


def validate_option(name, value, pattern):
    if not pattern.match(value):
        raise Invalid(f"{name} の値の形式が不正")


def cmd_render(args):
    if args.profile == "production":
        if args.upstream != "direct":
            raise Invalid("本番向けでは --upstream は direct だけ")
        if args.mock_host is not None or args.mock_port is not None:
            raise Invalid("本番向けでは --mock-host と --mock-port を指定できない")
    # 空文字は未指定として扱う。Why: 呼び出し側が1回の呼び出しで両方を渡せるようにするため。
    args.mock_host = args.mock_host or None
    args.mock_port = args.mock_port or None
    if (args.mock_host is None) != (args.mock_port is None):
        raise Invalid("--mock-host と --mock-port は両方指定する")

    supplied = {
        "CLIENT_IMAGE": args.client_image,
        "SQUID_IMAGE": args.squid_image,
        "SQUID_UPSTREAM": args.upstream,
    }
    for placeholder, (option, pattern) in PLACEHOLDER_CHECKS.items():
        validate_option(option, supplied[placeholder], pattern)

    template = load_json(args.template)
    doc = fill(template, supplied)
    check_leftovers(doc)

    if args.mock_host is not None:
        validate_option("--mock-host", args.mock_host, HOST_RE)
        validate_option("--mock-port", args.mock_port, DIGITS_RE)
        port = int(args.mock_port)
        if not 1 <= port <= 65535:
            raise Invalid("--mock-port の値が範囲外")
        squid = next((c for c in doc.get("containerDefinitions", []) if c.get("name") == "squid"), None)
        if squid is None:
            raise Invalid("squid コンテナが無い")
        squid.setdefault("environment", []).extend([
            {"name": "SQUID_MOCK_HOST", "value": args.mock_host},
            {"name": "SQUID_MOCK_PORT", "value": args.mock_port},
        ])

    check_structure(doc)
    if args.profile == "production":
        findings = production_findings(doc)
        if findings:
            raise Invalid("本番向けの検査に不合格: " + "; ".join(findings))

    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    tmp_path = args.out + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp_path, args.out)
    return 0


def cmd_check_production(args):
    doc = load_json(args.file)
    if not isinstance(doc, dict):
        print("FAIL: タスク定義がオブジェクトではない", file=sys.stderr)
        return 2
    findings = production_findings(doc)
    for finding in findings:
        print(f"FAIL: {finding}", file=sys.stderr)
    if findings:
        return 1
    print("OK: 本番向けの検査に合格")
    return 0


def cmd_docker_args(args):
    """完成版を、コンテナごとの docker run の引数へ変換する（pause方式。FR-906、FR-911）。

    出力は全て検査を通してから書く。途中で失敗した場合に、不完全な引数が残らないようにするため。
    値（環境変数）は引数に出さず、.env へ0600で書く。プロセス一覧に値を出さないため。
    """
    validate_option("--pause-name", args.pause_name, PAUSE_NAME_RE)
    validate_option("--run-id", args.run_id, RUN_ID_RE)
    doc = load_json(args.taskdef)
    check_structure(doc)
    check_leftovers(doc)
    if doc.get("networkMode") != "awsvpc":
        raise Invalid("変換の対象は awsvpc だけ")

    containers = doc["containerDefinitions"]
    names = [c["name"] for c in containers]
    if len(set(names)) != len(names):
        raise Invalid("コンテナ名が重複している")
    instances = {}
    for container in containers:
        name = container["name"]
        validate_option(f"コンテナ名 {name}", name, CONTAINER_NAME_RE)
        # Why: image は docker run の引数の末尾側に置かれる。先頭が - だと docker がオプションとして読み、
        # 許可リストの外のオプション（--privileged など）を通してしまう。render だけでなく、変換でも検査する。
        image = container.get("image")
        if not isinstance(image, str) or not IMAGE_RE.match(image) or image.startswith("-"):
            raise Invalid(f"コンテナ定義 {name} の image が不正（英数字で始まる参照だけ）")
        essential = container.get("essential")
        if not isinstance(essential, bool):
            raise Invalid(f"コンテナ定義 {name} の essential が真偽値ではない")
        # Why: 必須のコンテナは固定名、任意のコンテナ（Client）は実行ごとの名前にし、同時実行で衝突させない。
        instances[name] = f"{INSTANCE_PREFIX}{name}" if essential else f"{INSTANCE_PREFIX}{name}-{args.run_id}"

    ports = {}
    outputs = {}
    for container in containers:
        name = container["name"]
        inst = instances[name]
        for port in container.get("portMappings", []):
            number = port["containerPort"]
            if not 1 <= number <= 65535:
                raise Invalid(f"コンテナ定義 {name} の containerPort が範囲外")
            if number in ports and ports[number] != name:
                # Why: awsvpc では同じ名前空間を共有するため、同じポートは2つのコンテナで使えない。
                raise Invalid(f"containerPort {number} が複数のコンテナで重複している")
            ports[number] = name

        arg_list = container_docker_args(container, inst, args.pause_name, out_dir=args.out_dir)
        outputs[f"{inst}.args"] = arg_list
        env_lines = []
        for env in container.get("environment", []):
            # Why: 値を連結する前に検査する。連結後に改行を探すと、値の中の改行が行区切りに紛れて見えなくなるため。
            if CONTROL_RE.search(env["value"]):
                raise Invalid(f"コンテナ定義 {name} の環境変数に改行や制御文字が含まれる")
            env_lines.append(f"{env['name']}={env['value']}\n")
        outputs[f"{inst}.env"] = "".join(env_lines)
        depends = []
        for dep in container.get("dependsOn", []):
            target = dep["containerName"]
            if target not in instances or target == name:
                raise Invalid(f"コンテナ定義 {name} の dependsOn が存在しない、または自分自身を指す")
            depends.append(f"{dep['condition']} {instances[target]}")
        outputs[f"{inst}.depends"] = "".join(line + "\n" for line in depends)

    # Why: 検査と書き込みを分ける。1ファイルずつ検査して書くと、後ろのファイルで失敗したときに、
    # 前のファイルだけが出力先に残るため（evidence-code-review の SHOULD）。
    rendered = {}
    for filename, content in outputs.items():
        if isinstance(content, list):
            for value in content:
                if CONTROL_RE.search(value):
                    raise Invalid(f"{filename} の値に改行や制御文字が含まれる")
            content = "".join(value + "\n" for value in content)
        elif CONTROL_RE.search(content.replace("\n", "")):
            raise Invalid(f"{filename} の値に改行以外の制御文字が含まれる")
        rendered[filename] = content
    for filename, content in rendered.items():
        write_private(os.path.join(args.out_dir, filename), content)
    return 0


def container_docker_args(container, inst, pause, out_dir):
    """1コンテナ分の docker run の引数（1要素1行）。値は含めない（.env へ書く）。"""
    name = container["name"]
    out = [
        "--name", inst,
        "--label", LABEL,
        "--label", f"swsc.role={name}",
        "--network", f"container:{pause}",
        "--env-file", os.path.join(out_dir, f"{inst}.env"),
    ]
    if "healthCheck" in container:
        health = container["healthCheck"]
        # Why: ECS の CMD-SHELL は docker の --health-cmd へ、1つの文字列として渡す。
        out += [
            "--health-cmd", health["command"][1],
            "--health-interval", f"{health['interval']}s",
            "--health-timeout", f"{health['timeout']}s",
            "--health-retries", str(health["retries"]),
            "--health-start-period", f"{health['startPeriod']}s",
        ]
    entry = container.get("entryPoint", [])
    if entry:
        # Why: docker の --entrypoint は1つの実行ファイルだけを取る。残りは image の後ろへ置く。
        out += ["--entrypoint", entry[0]]
    out.append(container["image"])
    out += entry[1:] + container.get("command", [])
    return out


def write_private(path, content):
    """0600 で書く。Why: 環境変数の値を、他の利用者が読めないようにするため（FR-905、NFR-906）。"""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)


def normalize_container(container):
    """比較する項目だけを取り出す。順序差は無くし、空の既定値（null、空の配列、空のオブジェクト）は同じ扱いにする。

    Why: AWS が返す値の順序と既定の空項目は、完成版と同じ内容でも形が違うため（G2、G4）。
    """
    env = {e.get("name"): e.get("value") for e in container.get("environment") or []}
    ports = sorted(((p.get("containerPort"), p.get("protocol")) for p in container.get("portMappings") or []),
                   key=repr)
    deps = sorted(((d.get("containerName"), d.get("condition")) for d in container.get("dependsOn") or []),
                  key=repr)
    return {
        "image": container.get("image"),
        "essential": container.get("essential"),
        "environment": env,
        "portMappings": ports,
        "dependsOn": deps,
        "healthCheck": container.get("healthCheck") or None,
    }


COMPARED_KEYS = ("image", "essential", "environment", "portMappings", "dependsOn", "healthCheck")


def containers_by_name(containers, where):
    if not isinstance(containers, list):
        raise Invalid(f"{where} の containerDefinitions が配列ではない")
    by_name = {}
    for container in containers:
        if not isinstance(container, dict) or not isinstance(container.get("name"), str):
            raise Invalid(f"{where} のコンテナ定義の名前が無い")
        if container["name"] in by_name:
            raise Invalid(f"{where} のコンテナ名が重複している")
        by_name[container["name"]] = container
    return by_name


def compare_docs(expected, actual):
    """完成版と describe の差の項目名を返す。値は返さない（環境変数の値を出さないため）。"""
    if not isinstance(expected, dict) or not isinstance(actual, dict):
        raise Invalid("比較の入力がオブジェクトではない")
    diffs = []
    if expected.get("networkMode") != actual.get("networkMode"):
        diffs.append("networkMode")
    exp = containers_by_name(expected.get("containerDefinitions"), "完成版")
    act = containers_by_name(actual.get("containerDefinitions"), "describe")
    if set(exp) != set(act):
        diffs.append("containerDefinitions（コンテナの名前の集合）")
        return diffs
    for name in sorted(exp):
        want = normalize_container(exp[name])
        got = normalize_container(act[name])
        for key in COMPARED_KEYS:
            if want[key] != got[key]:
                diffs.append(f"containers.{name}.{key}")
    return diffs


def cmd_compare(args):
    expected = load_json(args.taskdef)
    actual = load_json(args.describe)
    diffs = compare_docs(expected, actual)
    if args.report:
        report = {"result": "mismatch" if diffs else "match", "differences": diffs}
        tmp_path = args.report + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp_path, args.report)
    if diffs:
        for diff in diffs:
            print(f"FAIL: 不一致: {diff}", file=sys.stderr)
        return 1
    print("OK: 登録とdescribeの比較が一致した")
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description="M09 タスク定義の生成と検査")
    sub = parser.add_subparsers(dest="command", required=True)

    render = sub.add_parser("render", help="テンプレートから完成版を作る")
    render.add_argument("--template", required=True)
    render.add_argument("--out", required=True)
    render.add_argument("--client-image", required=True)
    render.add_argument("--squid-image", required=True)
    render.add_argument("--profile", choices=["local", "production"], required=True)
    render.add_argument("--upstream", required=True)
    render.add_argument("--mock-host")
    render.add_argument("--mock-port")
    render.set_defaults(func=cmd_render)

    check = sub.add_parser("check-production", help="任意のタスク定義が本番向けの条件を満たすか検査する")
    check.add_argument("file")
    check.set_defaults(func=cmd_check_production)

    dargs = sub.add_parser("docker-args", help="完成版を docker run の引数と .env、依存へ変換する")
    dargs.add_argument("--taskdef", required=True)
    dargs.add_argument("--out-dir", required=True)
    dargs.add_argument("--pause-name", required=True)
    dargs.add_argument("--run-id", required=True)
    dargs.set_defaults(func=cmd_docker_args)

    cmp_parser = sub.add_parser("compare", help="完成版と describe の出力を、順序と空の既定値を除いて比べる")
    cmp_parser.add_argument("taskdef")
    cmp_parser.add_argument("describe")
    cmp_parser.add_argument("--report", help="結果（一致か、不一致の項目名）を書くJSONのパス")
    cmp_parser.set_defaults(func=cmd_compare)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except Invalid as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
