#!/usr/bin/env python3
"""Audit Moonata against the official jsonata-js test suite.

The script intentionally keeps the upstream jsonata repository outside this
repo. By default it expects `/tmp/jsonata-upstream` to contain a clone of
https://github.com/jsonata-js/jsonata.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_UPSTREAM = Path("/tmp/jsonata-upstream")
DEFAULT_EXE = Path("_build/native/debug/build/cmd/main/main.exe")


@dataclass
class AuditResult:
    eligible: int
    passed: int
    failed: int
    skipped: int
    fail_by_group: Counter[str]
    skip_by_reason: Counter[str]
    failures: list[dict[str, Any]]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit Moonata against jsonata-js official test-suite cases.",
    )
    parser.add_argument(
        "--upstream",
        type=Path,
        default=DEFAULT_UPSTREAM,
        help="jsonata-js checkout or test-suite directory (default: /tmp/jsonata-upstream)",
    )
    parser.add_argument(
        "--exe",
        type=Path,
        default=DEFAULT_EXE,
        help="Moonata native CLI executable (default: _build/native/debug/build/cmd/main/main.exe)",
    )
    parser.add_argument(
        "--group",
        action="append",
        default=[],
        help="Only audit a group name, e.g. --group function-string. Can be repeated.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Per-case timeout in seconds (default: 5.0)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=10,
        help="Number of top failing groups to print (default: 10)",
    )
    parser.add_argument(
        "--show-failures",
        type=int,
        default=0,
        help="Print the first N failure details after the summary.",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        help="Write a machine-readable audit report to this path.",
    )
    parser.add_argument(
        "--fail-on-failure",
        action="store_true",
        help="Exit with code 1 when any comparable official case fails.",
    )
    return parser.parse_args()


def resolve_suite_root(upstream: Path) -> Path:
    if (upstream / "groups").is_dir() and (upstream / "datasets").is_dir():
        return upstream
    suite = upstream / "test" / "test-suite"
    if (suite / "groups").is_dir() and (suite / "datasets").is_dir():
        return suite
    raise SystemExit(
        "Cannot find jsonata test-suite. Expected either "
        f"{upstream}/groups or {upstream}/test/test-suite/groups.",
    )


def expand_cases(payload: Any) -> Iterable[dict[str, Any]]:
    if isinstance(payload, dict) and ("expr" in payload or "expr-file" in payload):
        yield payload
    elif isinstance(payload, list):
        for case in payload:
            if isinstance(case, dict):
                yield case
    elif isinstance(payload, dict):
        for name, value in payload.items():
            if isinstance(value, list):
                for case in value:
                    if isinstance(case, dict):
                        cloned = dict(case)
                        cloned.setdefault("name", name)
                        yield cloned
            elif isinstance(value, dict):
                cloned = dict(value)
                cloned.setdefault("name", name)
                yield cloned


def comparable(case: dict[str, Any]) -> tuple[bool, str]:
    if "result" not in case:
        return False, "no_result"
    if case.get("bindings"):
        return False, "bindings"
    if "timelimit" in case:
        return False, "timelimit"
    if "depth" in case:
        return False, "depth"
    if "expr-file" in case or not isinstance(case.get("expr"), str):
        return False, "non-string-expr"
    return True, ""


def data_for(case: dict[str, Any], suite_root: Path) -> tuple[bool, Any, str]:
    if "data" in case:
        return True, case["data"], ""
    dataset = case.get("dataset")
    if dataset:
        dataset_name = str(dataset)
        if not dataset_name.endswith(".json"):
            dataset_name += ".json"
        dataset_path = suite_root / "datasets" / dataset_name
        if not dataset_path.exists():
            return False, None, "missing-dataset"
        with dataset_path.open(encoding="utf-8") as handle:
            return True, json.load(handle), ""
    return True, None, ""


def run_case(
    exe: Path,
    expr: str,
    data: Any,
    timeout: float,
) -> tuple[bool, Any, str]:
    with tempfile.NamedTemporaryFile(
        "w",
        suffix=".json",
        encoding="utf-8",
        delete=False,
    ) as handle:
        json.dump(data, handle, ensure_ascii=False)
        data_path = handle.name

    try:
        proc = subprocess.run(
            [str(exe), expr, "--file", data_path],
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, None, "timeout"
    finally:
        try:
            os.unlink(data_path)
        except OSError:
            pass

    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()
    if proc.returncode != 0:
        return False, None, f"exit {proc.returncode}: {stderr or stdout}"
    if stdout.startswith("错误:"):
        return False, None, stdout
    try:
        return True, json.loads(stdout), ""
    except json.JSONDecodeError as exc:
        return False, None, f"invalid-json-output: {exc}"


def case_id(group_file: Path) -> str:
    return f"{group_file.parent.name}/{group_file.name}"


def audit(args: argparse.Namespace) -> AuditResult:
    suite_root = resolve_suite_root(args.upstream)
    exe = args.exe
    if not exe.exists():
        raise SystemExit(
            f"Moonata CLI executable not found: {exe}\n"
            "Run: moon build cmd/main --target native",
        )

    selected_groups = set(args.group)
    eligible = passed = failed = skipped = 0
    fail_by_group: Counter[str] = Counter()
    skip_by_reason: Counter[str] = Counter()
    failures: list[dict[str, Any]] = []

    group_files = sorted((suite_root / "groups").glob("**/*.json"))
    for group_file in group_files:
        group = group_file.parent.name
        if selected_groups and group not in selected_groups:
            continue

        with group_file.open(encoding="utf-8") as handle:
            payload = json.load(handle)

        for case in expand_cases(payload):
            ok, reason = comparable(case)
            if not ok:
                skipped += 1
                skip_by_reason[reason] += 1
                continue

            data_ok, data, data_reason = data_for(case, suite_root)
            if not data_ok:
                skipped += 1
                skip_by_reason[data_reason] += 1
                continue

            eligible += 1
            expr = case["expr"]
            run_ok, actual, run_reason = run_case(
                exe=exe,
                expr=expr,
                data=data,
                timeout=args.timeout,
            )
            expected = case["result"]
            if run_ok and actual == expected:
                passed += 1
                continue

            failed += 1
            fail_by_group[group] += 1
            failure = {
                "case": case_id(group_file),
                "group": group,
                "expr": expr,
                "reason": "mismatch" if run_ok else run_reason,
                "expected": expected,
            }
            if run_ok:
                failure["actual"] = actual
            failures.append(failure)

    return AuditResult(
        eligible=eligible,
        passed=passed,
        failed=failed,
        skipped=skipped,
        fail_by_group=fail_by_group,
        skip_by_reason=skip_by_reason,
        failures=failures,
    )


def print_summary(result: AuditResult, top: int, show_failures: int) -> None:
    print(
        f"eligible {result.eligible} pass {result.passed} "
        f"fail {result.failed} skip {result.skipped}",
    )
    print("top_failures")
    for group, count in result.fail_by_group.most_common(top):
        print(group, count)
    print("skip_reasons")
    for reason, count in result.skip_by_reason.most_common():
        print(reason, count)

    if show_failures > 0 and result.failures:
        print("failures")
        for failure in result.failures[:show_failures]:
            print(json.dumps(failure, ensure_ascii=False, sort_keys=True))


def write_json_report(path: Path, result: AuditResult) -> None:
    report = {
        "eligible": result.eligible,
        "pass": result.passed,
        "fail": result.failed,
        "skip": result.skipped,
        "top_failures": result.fail_by_group.most_common(),
        "skip_reasons": result.skip_by_reason.most_common(),
        "failures": result.failures,
    }
    with path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main() -> int:
    args = parse_args()
    result = audit(args)
    print_summary(result, top=args.top, show_failures=args.show_failures)
    if args.json_out is not None:
        write_json_report(args.json_out, result)
    if args.fail_on_failure and result.failed > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
