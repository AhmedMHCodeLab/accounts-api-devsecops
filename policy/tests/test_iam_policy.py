import json
from pathlib import Path

POLICY = Path(__file__).resolve().parents[2] / "iam" / "accounts-api-policy.json"


def as_list(value):
    return value if isinstance(value, list) else [value]


def main() -> None:
    document = json.loads(POLICY.read_text())

    statements = document["Statement"]

    actions = {
        action
        for statement in statements
        for action in as_list(statement["Action"])
    }

    resources = {
        resource
        for statement in statements
        for resource in as_list(statement["Resource"])
    }

    assert "*" not in actions, "IAM policy must not grant wildcard actions"

    assert "*" not in resources, "IAM policy must not grant all resources"

    expected_secret_arn = (
        "arn:aws:secretsmanager:ap-south-1:123456789012:"
        "secret:accounts-api/prod/db-*"
    )

    expected_kms_arn = (
        "arn:aws:kms:ap-south-1:123456789012:"
        "key/REPLACE_WITH_ACCOUNTS_API_SECRET_KEY_ID"
    )

    assert expected_secret_arn in resources
    assert expected_kms_arn in resources

    assert actions == {
        "secretsmanager:GetSecretValue",
        "kms:Decrypt",
    }

    assert all(
        resource.startswith(
            (
                "arn:aws:secretsmanager:ap-south-1:",
                "arn:aws:kms:ap-south-1:",
            )
        )
        for resource in resources
    )

    kms_statement = next(
        statement
        for statement in statements
        if statement["Sid"] == "DecryptAccountsApiSecret"
    )

    assert kms_statement["Condition"]["StringEquals"]["kms:ViaService"] == (
        "secretsmanager.ap-south-1.amazonaws.com"
    )

    print("IAM policy checks passed")


if __name__ == "__main__":
    main()