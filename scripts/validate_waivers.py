from datetime import date
from pathlib import Path

import yaml

WAIVER_FILE = Path("security/waivers.yaml")


REQUIRED_FIELDS = {
    "id",
    "gate",
    "finding",
    "repository",
    "workload",
    "reason",
    "owner",
    "approver",
    "created",
    "expires",
}


def main() -> int:
    data = yaml.safe_load(WAIVER_FILE.read_text()) or {}

    if data.get("version") != 1:
        raise SystemExit("Unsupported waiver schema version")

    waivers = data.get("waivers", [])

    today = date.today()

    for waiver in waivers:
        missing = REQUIRED_FIELDS - waiver.keys()

        if missing:
            raise SystemExit(
                f"{waiver.get('id', '<unknown>')}: "
                f"missing fields: {', '.join(sorted(missing))}"
            )

        created = date.fromisoformat(waiver["created"])
        expires = date.fromisoformat(waiver["expires"])

        if expires <= created:
            raise SystemExit(
                f"{waiver['id']}: expiry must be after creation"
            )

        if (expires - created).days > 7:
            raise SystemExit(
                f"{waiver['id']}: waiver lifetime exceeds 7 days"
            )

        if expires < today:
            raise SystemExit(
                f"{waiver['id']}: waiver expired on {waiver['expires']}"
            )

    print(f"Validated {len(waivers)} active waiver(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())