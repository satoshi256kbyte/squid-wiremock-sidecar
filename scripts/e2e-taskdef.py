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
# Client が叩く先。Why: スキームとホスト（とポート）だけを許す。パスや認証情報を入れて値が漏れないようにする。
API_BASE_URL_RE = re.compile(r"\Ahttps?://[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?\Z")
LOG_GROUP_RE = re.compile(r"\A[A-Za-z0-9_/.#-]{1,512}\Z")
LOG_REGION_RE = re.compile(r"\A[a-z]{2}(-[a-z]+)+-[0-9]\Z")
ROLE_ARN_RE = re.compile(r"\Aarn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}\Z")
LOG_STREAM_PREFIX = "swsc-e2e"
API_BASE_URL_ENV = "TEST_API_BASE_URL"
# Client が使うプロキシ。Why: ローカルのエミュレータは、同じタスクのコンテナで 127.0.0.1 を共有しないため、
# Squid に付けた別名へ向ける。本番は 127.0.0.1:3128 のままにするので、本番では指定を拒否する。
PROXY_URL_RE = re.compile(r"\Ahttp://[A-Za-z0-9.-]{1,253}:[0-9]{1,5}\Z")
PROXY_ENV_NAMES = ("HTTP_PROXY", "HTTPS_PROXY")
# Fargate の CPU アーキテクチャ。Why: arm64 のマシンで作ったイメージを動かすには ARM64 を指定する。
CPU_ARCHITECTURES = {"x86_64": "X86_64", "arm64": "ARM64"}
WHOLE_PLACEHOLDER_RE = re.compile(r"\A\{\{([A-Z_]+)\}\}\Z")
LEFTOVER_RE = re.compile(r"\{\{|\}\}")

# 許可リスト。Why: 許可しない項目（volumes、secrets など）を黙って通さず、名指しで止めるため（Q-913）。
TOP_KEYS = {"family", "networkMode", "requiresCompatibilities", "cpu", "memory", "containerDefinitions",
            "executionRoleArn", "taskRoleArn", "runtimePlatform"}
CONTAINER_KEYS = {"name", "image", "essential", "environment", "portMappings", "dependsOn",
                  "healthCheck", "command", "entryPoint", "logConfiguration"}
LOG_KEYS = {"logDriver", "options"}
LOG_OPTION_KEYS = {"awslogs-group", "awslogs-region", "awslogs-stream-prefix"}
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
    if "logConfiguration" in container:
        log = container["logConfiguration"]
        if not isinstance(log, dict):
            raise Invalid(f"{where} の logConfiguration が不正")
        reject_unknown(log, LOG_KEYS, f"{where} の logConfiguration")
        options = log.get("options")
        if log.get("logDriver") != "awslogs" or not isinstance(options, dict):
            raise Invalid(f"{where} の logConfiguration は awslogs の形式だけ")
        reject_unknown(options, LOG_OPTION_KEYS, f"{where} の logConfiguration.options")


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


def apply_overrides(doc, args):
    """任意の引数（宛先URL、ログ、ロール）を完成版へ反映する。指定が無い項目は触らない。"""
    if args.api_base_url:
        validate_option("--api-base-url", args.api_base_url, API_BASE_URL_RE)
        client = next((c for c in doc.get("containerDefinitions", []) if c.get("name") == "client"), None)
        if client is None:
            raise Invalid("client コンテナが無い")
        env = [e for e in client.get("environment", []) if e.get("name") != API_BASE_URL_ENV]
        env.append({"name": API_BASE_URL_ENV, "value": args.api_base_url})
        client["environment"] = env

    if args.proxy_url:
        validate_option("--proxy-url", args.proxy_url, PROXY_URL_RE)
        client = next((c for c in doc.get("containerDefinitions", []) if c.get("name") == "client"), None)
        if client is None:
            raise Invalid("client コンテナが無い")
        env = [e for e in client.get("environment", []) if e.get("name") not in PROXY_ENV_NAMES]
        env += [{"name": name, "value": args.proxy_url} for name in PROXY_ENV_NAMES]
        client["environment"] = env

    if (args.log_group is None) != (args.log_region is None):
        raise Invalid("--log-group と --log-region は両方指定する")
    if args.log_group is not None:
        validate_option("--log-group", args.log_group, LOG_GROUP_RE)
        validate_option("--log-region", args.log_region, LOG_REGION_RE)
        for container in doc.get("containerDefinitions", []):
            container["logConfiguration"] = {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": args.log_group,
                    "awslogs-region": args.log_region,
                    "awslogs-stream-prefix": LOG_STREAM_PREFIX,
                },
            }

    if args.cpu_architecture:
        doc["runtimePlatform"] = {
            "cpuArchitecture": CPU_ARCHITECTURES[args.cpu_architecture],
            "operatingSystemFamily": "LINUX",
        }

    for option, key, value in (("--execution-role-arn", "executionRoleArn", args.execution_role_arn),
                               ("--task-role-arn", "taskRoleArn", args.task_role_arn)):
        if value:
            validate_option(option, value, ROLE_ARN_RE)
            doc[key] = value


def cmd_render(args):
    if args.profile == "production":
        if args.upstream != "direct":
            raise Invalid("本番向けでは --upstream は direct だけ")
        if args.mock_host is not None or args.mock_port is not None:
            raise Invalid("本番向けでは --mock-host と --mock-port を指定できない")
        # Why: テンプレートの既定は http://api.example.com で、本番に残さないため。
        if not args.api_base_url or not args.api_base_url.startswith("https://"):
            raise Invalid("本番向けでは --api-base-url に https:// の URL が要る")
        if args.proxy_url:
            raise Invalid("本番向けでは --proxy-url を指定できない（127.0.0.1:3128 のままにする）")
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

    apply_overrides(doc, args)

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
    render.add_argument("--api-base-url", help="Client が叩く先（TEST_API_BASE_URL）。本番は https:// だけ")
    render.add_argument("--proxy-url", help="Client のプロキシ（HTTP_PROXY、HTTPS_PROXY）。local だけ")
    render.add_argument("--log-group", help="CloudWatch Logs のロググループ。--log-region と一緒に指定する")
    render.add_argument("--log-region")
    render.add_argument("--cpu-architecture", choices=sorted(CPU_ARCHITECTURES),
                        help="Fargate の CPU アーキテクチャ。省略時は指定しない（Fargate の既定の x86_64）")
    render.add_argument("--execution-role-arn")
    render.add_argument("--task-role-arn")
    render.set_defaults(func=cmd_render)

    check = sub.add_parser("check-production", help="任意のタスク定義が本番向けの条件を満たすか検査する")
    check.add_argument("file")
    check.set_defaults(func=cmd_check_production)

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
