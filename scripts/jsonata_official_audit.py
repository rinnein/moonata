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
import re
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


@dataclass
class AuditCase:
    group: str
    group_file: Path
    case: dict[str, Any]


@dataclass
class RunResult:
    ok: bool
    value: Any | None
    detail: str
    stdout: str
    stderr: str


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


def expand_cases(payload: Any, group_file: Path, group: str) -> Iterable[AuditCase]:
    if isinstance(payload, dict) and (
        "expr" in payload
        or "expr-file" in payload
        or "result" in payload
        or "undefinedResult" in payload
        or "code" in payload
    ):
        yield AuditCase(group=group, group_file=group_file, case=payload)
    elif isinstance(payload, list):
        for case in payload:
            if isinstance(case, dict):
                yield AuditCase(group=group, group_file=group_file, case=case)
    elif isinstance(payload, dict):
        for name, value in payload.items():
            if isinstance(value, list):
                for case in value:
                    if isinstance(case, dict):
                        cloned = dict(case)
                        cloned.setdefault("name", name)
                        yield AuditCase(group=group, group_file=group_file, case=cloned)
            elif isinstance(value, dict):
                cloned = dict(value)
                cloned.setdefault("name", name)
                yield AuditCase(group=group, group_file=group_file, case=cloned)


def expected_outcome(case: dict[str, Any]) -> tuple[bool, str, Any, str]:
    if "result" in case:
        return True, "result", case["result"], ""
    if case.get("undefinedResult") is True:
        return True, "undefined", None, ""
    if "code" in case:
        return True, "code", case["code"], ""
    if "depth" in case:
        return False, "", None, "depth"
    return False, "", None, "no_expected_outcome"


def resolve_relative_candidates(
    raw: str,
    roots: list[Path],
    suffixes: list[str] | None = None,
) -> list[Path]:
    path = Path(raw)
    candidates: list[Path] = []

    def add(candidate: Path) -> None:
        if candidate not in candidates:
            candidates.append(candidate)

    if path.is_absolute():
        add(path)
        return candidates

    suffixes = suffixes or [""]
    for root in roots:
        for suffix in suffixes:
            candidate = root / path
            if suffix and candidate.suffix != suffix:
                candidate = candidate.with_suffix(suffix)
            add(candidate)

    return candidates


def load_text_from_candidates(candidates: list[Path]) -> tuple[bool, str, str]:
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return True, candidate.read_text(encoding="utf-8"), ""
    tried = ", ".join(str(path) for path in candidates)
    return False, "", f"missing-file: {tried}"


def data_for(case: dict[str, Any], source_dir: Path, suite_root: Path) -> tuple[bool, Any, str]:
    if "data" in case:
        return True, case["data"], ""
    dataset = case.get("dataset")
    if dataset:
        candidates = resolve_relative_candidates(
            str(dataset),
            roots=[source_dir, source_dir.parent, suite_root, suite_root / "datasets"],
            suffixes=[".json"],
        )
        for dataset_path in candidates:
            if dataset_path.exists() and dataset_path.is_file():
                with dataset_path.open(encoding="utf-8") as handle:
                    return True, json.load(handle), ""
        tried = ", ".join(str(path) for path in candidates)
        return False, None, f"missing-dataset: {tried}"
    return True, None, ""


def expr_for(case: dict[str, Any], source_dir: Path, suite_root: Path) -> tuple[bool, str, str]:
    expr = case.get("expr")
    if isinstance(expr, str):
        return True, expr, ""

    expr_file = case.get("expr-file")
    if isinstance(expr_file, str):
        candidates = resolve_relative_candidates(
            expr_file,
            roots=[source_dir, source_dir.parent, suite_root, suite_root / "groups"],
        )
        ok, text, reason = load_text_from_candidates(candidates)
        if ok:
            return True, text, ""
        return False, "", reason

    return False, "", "non-string-expr"


def normalize_binding_name(name: str) -> tuple[bool, str]:
    candidate = name if name.startswith("$") else f"${name}"
    if re.fullmatch(r"\$[A-Za-z_][A-Za-z0-9_]*", candidate):
        return True, candidate
    return False, candidate


def binding_expression(case: dict[str, Any]) -> tuple[bool, str, str]:
    bindings = case.get("bindings")
    if not isinstance(bindings, dict) or len(bindings) == 0:
        return True, "", ""

    parts: list[str] = []
    for raw_name, value in bindings.items():
        ok, name = normalize_binding_name(str(raw_name))
        if not ok:
            return False, "", f"invalid-binding-name: {raw_name}"
        parts.append(f"{name} := {json.dumps(value, ensure_ascii=False)}")

    return True, "; ".join(parts), ""


def wrap_expression_with_bindings(expr: str, bindings_expr: str) -> str:
    if bindings_expr == "":
        return expr
    return f"({bindings_expr}; {expr})"


def resolve_timeout(case: dict[str, Any], fallback_timeout: float) -> float:
    timelimit = case.get("timelimit")
    if isinstance(timelimit, (int, float)) and timelimit > 0:
        return float(timelimit) / 1000.0
    return fallback_timeout


def run_case(
    exe: Path,
    expr: str,
    data: Any,
    timeout: float,
) -> RunResult:
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
        return RunResult(ok=False, value=None, detail="timeout", stdout="", stderr="")
    finally:
        try:
            os.unlink(data_path)
        except OSError:
            pass

    stdout = proc.stdout.strip()
    stderr = proc.stderr.strip()
    if proc.returncode != 0:
        detail = stderr or stdout
        return RunResult(
            ok=False,
            value=None,
            detail=f"exit {proc.returncode}: {detail}",
            stdout=stdout,
            stderr=stderr,
        )
    if stdout.startswith("错误:"):
        return RunResult(ok=False, value=None, detail=stdout, stdout=stdout, stderr=stderr)
    try:
        return RunResult(ok=True, value=json.loads(stdout), detail="", stdout=stdout, stderr=stderr)
    except json.JSONDecodeError as exc:
        return RunResult(
            ok=False,
            value=None,
            detail=f"invalid-json-output: {exc}",
            stdout=stdout,
            stderr=stderr,
        )


def code_matches(expected_code: Any, run_result: RunResult) -> bool:
    if run_result.ok:
        return False
    code = str(expected_code).strip()
    if not code:
        return False
    haystack = "\n".join(
        part for part in [run_result.detail, run_result.stdout, run_result.stderr] if part
    )
    return code in haystack


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

        for entry in expand_cases(payload, group_file, group):
            case = entry.case

            ok, expected_kind, expected_value, reason = expected_outcome(case)
            if not ok:
                skipped += 1
                skip_by_reason[reason] += 1
                continue

            expr_ok, expr, expr_reason = expr_for(case, entry.group_file.parent, suite_root)
            if not expr_ok:
                skipped += 1
                skip_by_reason[expr_reason] += 1
                continue

            data_ok, data, data_reason = data_for(case, entry.group_file.parent, suite_root)
            if not data_ok:
                skipped += 1
                skip_by_reason[data_reason] += 1
                continue

            bindings_ok, bindings_expr, bindings_reason = binding_expression(case)
            if not bindings_ok:
                skipped += 1
                skip_by_reason[bindings_reason] += 1
                continue

            eligible += 1
            wrapped_expr = wrap_expression_with_bindings(expr, bindings_expr)
            run_result = run_case(
                exe=exe,
                expr=wrapped_expr,
                data=data,
                timeout=resolve_timeout(case, args.timeout),
            )

            if expected_kind in {"result", "undefined"}:
                if run_result.ok and run_result.value == expected_value:
                    passed += 1
                    continue

                failed += 1
                fail_by_group[group] += 1
                failure = {
                    "case": case_id(entry.group_file),
                    "group": group,
                    "expr": wrapped_expr,
                    "reason": "mismatch" if run_result.ok else run_result.detail,
                    "expected": expected_value,
                }
                if run_result.ok:
                    failure["actual"] = run_result.value
                failures.append(failure)
                continue

            if expected_kind == "code":
                if code_matches(expected_value, run_result):
                    passed += 1
                    continue

                failed += 1
                fail_by_group[group] += 1
                failure = {
                    "case": case_id(entry.group_file),
                    "group": group,
                    "expr": wrapped_expr,
                    "reason": "code-mismatch" if not run_result.ok else "expected-error",
                    "expected": expected_value,
                }
                if not run_result.ok:
                    failure["actual"] = run_result.detail
                else:
                    failure["actual"] = run_result.value
                failures.append(failure)
                continue

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
