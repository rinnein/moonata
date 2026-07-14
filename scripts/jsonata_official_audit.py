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
    # JSONata-js test runner treats the `error` field as an expected error
    # structure (see run-test-suite.js#L123-128):
    #   `expect(...).to.eventually.deep.contain(testcase.error)`
    # Each key/value in `testcase.error` must appear in the thrown error.
    # Common keys: `code`, `message`, `token`, `functionName`, `value`.
    if "error" in case and isinstance(case["error"], dict):
        return True, "error", case["error"], ""
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


def data_for(
    case: dict[str, Any], source_dir: Path, suite_root: Path
) -> tuple[bool, Any, str, bool]:
    """Resolve the input data for a case.

    Returns ``(ok, data, reason, use_undefined)``.

    ``use_undefined`` is True when the case has no inline ``data`` and either
    no ``dataset`` field or ``dataset: null``. This matches jsonata-js
    ``run-test-suite.js#resolveDataset`` which maps ``dataset === null`` to JS
    ``undefined`` rather than JSON ``null``.
    """
    if "data" in case:
        # Explicit inline data (may itself be null). Match jsonata-js by
        # passing the actual value through, not undefined.
        return True, case["data"], "", False
    dataset = case.get("dataset")
    if dataset is not None and dataset != "":
        candidates = resolve_relative_candidates(
            str(dataset),
            roots=[source_dir, source_dir.parent, suite_root, suite_root / "datasets"],
            suffixes=[".json"],
        )
        for dataset_path in candidates:
            if dataset_path.exists() and dataset_path.is_file():
                with dataset_path.open(encoding="utf-8") as handle:
                    return True, json.load(handle), "", False
        tried = ", ".join(str(path) for path in candidates)
        return False, None, f"missing-dataset: {tried}", False
    # No inline data and no named dataset: align with jsonata-js semantics
    # (dataset: null → undefined). The CLI accepts `--no-data` to evaluate
    # against an undefined root context.
    return True, None, "", True


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
    use_undefined: bool = False,
    max_depth: int | None = None,
) -> RunResult:
    """Invoke the Moonata CLI on a single case and capture its textual output.

    Uses ``surrogatepass`` when encoding argv so that official cases containing
    lone surrogates (e.g. ``function-encodeUrl/case002`` with ``'\\ud800'`` in
    the expression) reach the CLI byte-for-byte rather than crashing the
    subprocess layer. Captured stdout/stderr are decoded with ``replace`` so
    the audit script always produces a printable haystack.
    """
    extra_args: list[str] = []
    if max_depth is not None and max_depth > 0:
        extra_args.extend(["--max-depth", str(max_depth)])

    def _spawn(cmd_strs: list[str]) -> tuple[int, str, str]:
        cmd_bytes = [s.encode("utf-8", errors="surrogatepass") for s in cmd_strs]
        proc = subprocess.run(
            cmd_bytes,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        stdout = proc.stdout.decode("utf-8", errors="replace").strip()
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        return proc.returncode, stdout, stderr

    if use_undefined:
        # When the case maps to undefined input (jsonata-js `dataset: null` →
        # undefined), invoke the CLI with `--no-data` so the root context is
        # undefined rather than JSON null.
        cmd = [str(exe), expr, "--no-data"] + extra_args
        try:
            rc, stdout, stderr = _spawn(cmd)
        except subprocess.TimeoutExpired:
            return RunResult(ok=False, value=None, detail="timeout", stdout="", stderr="")
    else:
        with tempfile.NamedTemporaryFile(
            "w",
            suffix=".json",
            encoding="utf-8",
            delete=False,
        ) as handle:
            json.dump(data, handle, ensure_ascii=False)
            data_path = handle.name

        try:
            rc, stdout, stderr = _spawn(
                [str(exe), expr, "--file", data_path] + extra_args
            )
        except subprocess.TimeoutExpired:
            try:
                os.unlink(data_path)
            except OSError:
                pass
            return RunResult(ok=False, value=None, detail="timeout", stdout="", stderr="")
        finally:
            try:
                os.unlink(data_path)
            except OSError:
                pass

    if rc != 0:
        detail = stderr or stdout
        return RunResult(
            ok=False,
            value=None,
            detail=f"exit {rc}: {detail}",
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


def _error_haystack(run_result: RunResult) -> str:
    return "\n".join(
        part for part in [run_result.detail, run_result.stdout, run_result.stderr] if part
    )


def code_matches(expected_code: Any, run_result: RunResult) -> bool:
    if run_result.ok:
        return False
    code = str(expected_code).strip()
    if not code:
        return False
    return code in _error_haystack(run_result)


def error_object_matches(
    expected_error: dict[str, Any], run_result: RunResult
) -> tuple[bool, str]:
    """Verify a CLI failure against an `error` object expected by the official suite.

    Mirrors jsonata-js test runner's ``to.eventually.deep.contain(testcase.error)``
    (see ``run-test-suite.js#L123-128``). The CLI must fail, and every non-empty
    scalar value in ``expected_error`` must appear as a substring in the
    combined output (detail + stdout + stderr). This is the same string-contains
    strategy used for ``code``-kind cases, extended to ``message``/``token``/
    ``functionName``/``value``.

    Returns ``(matched, reason)``. ``reason`` is empty on success and a short
    diagnostic (e.g. ``missing-message``, ``expected-error-but-success``) on
    failure, suitable for inclusion in the failure report.
    """
    if run_result.ok:
        return False, "expected-error-but-success"
    haystack = _error_haystack(run_result)
    for key, expected_value in expected_error.items():
        if expected_value is None:
            continue
        # Booleans/numbers serialise to "true"/"false"/digits, which are too
        # generic to substring-match reliably. The official error structure
        # only uses string fields in practice, so restrict to those.
        if isinstance(expected_value, bool):
            continue
        if isinstance(expected_value, (int, float)):
            needle = str(expected_value)
        elif isinstance(expected_value, str):
            needle = expected_value
        else:
            # Dicts/lists would need structured matching; skip rather than
            # risk false positives from str(dict).
            continue
        if not needle:
            continue
        if needle not in haystack:
            return False, f"missing-{key}"
    return True, ""


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

            data_ok, data, data_reason, use_undefined = data_for(
                case, entry.group_file.parent, suite_root
            )
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
            # 对齐 jsonata-js test runner 的 timeboxExpression：case 文件的 `depth` 字段
            # 作为 maxDepth 传给 CLI，使 `tail-recursion/case002`（depth=302）等用例
            # 能在指定深度触发 U1001。
            case_depth = case.get("depth")
            max_depth = case_depth if isinstance(case_depth, int) and case_depth > 0 else None
            run_result = run_case(
                exe=exe,
                expr=wrapped_expr,
                data=data,
                timeout=resolve_timeout(case, args.timeout),
                use_undefined=use_undefined,
                max_depth=max_depth,
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

            if expected_kind == "error":
                matched, mismatch_reason = error_object_matches(
                    expected_value, run_result
                )
                if matched:
                    passed += 1
                    continue

                failed += 1
                fail_by_group[group] += 1
                failure = {
                    "case": case_id(entry.group_file),
                    "group": group,
                    "expr": wrapped_expr,
                    "reason": (
                        mismatch_reason
                        if not run_result.ok
                        else "expected-error"
                    ),
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
            safe = _sanitize_for_json(failure)
            print(json.dumps(safe, ensure_ascii=False, sort_keys=True))


def _sanitize_for_json(value: Any) -> Any:
    """Recursively replace lone surrogates so json.dump can encode to UTF-8.

    The ``function-encodeUrl/case002`` case carries ``'\\ud800'`` in both the
    expression and the expected ``value`` field. Python's ``json`` module
    refuses to encode lone surrogates when ``ensure_ascii=False``; we replace
    them with ``U+FFFD`` so the JSON report is always writable while keeping
    the surrounding context readable.
    """
    if isinstance(value, str):
        return value.encode("utf-8", errors="replace").decode("utf-8", errors="replace")
    if isinstance(value, dict):
        return {k: _sanitize_for_json(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize_for_json(v) for v in value]
    return value


def write_json_report(path: Path, result: AuditResult) -> None:
    report = {
        "eligible": result.eligible,
        "pass": result.passed,
        "fail": result.failed,
        "skip": result.skipped,
        "top_failures": result.fail_by_group.most_common(),
        "skip_reasons": result.skip_by_reason.most_common(),
        "failures": _sanitize_for_json(result.failures),
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
