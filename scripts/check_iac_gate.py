import json
import sys
from pathlib import Path

BLOCKING_PREFIX = "CKV2_AWS_ACCOUNTS_"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_iac_gate.py <checkov-json>")
        return 2

    report = Path(sys.argv[1])

    if not report.exists():
        print(f"Checkov report not found: {report}")
        return 2

    data = json.loads(report.read_text())
    failed = data.get("results", {}).get("failed_checks", [])

    blocking = [
        finding
        for finding in failed
        if finding.get("check_id", "").startswith(BLOCKING_PREFIX)
    ]

    if blocking:
        print("Blocking IaC findings:")
        for finding in blocking:
            print(
                f"- {finding.get('check_id')}: "
                f"{finding.get('check_name')} "
                f"({finding.get('file_path')})"
            )
        return 1

    print("Threat-model IaC gate passed")

    if failed:
        print(
            f"Non-blocking Checkov findings remain: {len(failed)}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())