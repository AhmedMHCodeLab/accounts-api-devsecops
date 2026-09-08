# accounts-api — DevSecOps Security Assessment

Security controls and policy-as-code for a representative regulated-banking workload running on Kubernetes and AWS.

[![Security Gates](https://github.com/AhmedMHCodeLab/accounts-api-devsecops/actions/workflows/security-gates.yml/badge.svg)](https://github.com/AhmedMHCodeLab/accounts-api-devsecops/actions/workflows/security-gates.yml)

> **Assessment note:** The production `accounts-api` is assumed to already exist. This repository contains a minimal representative implementation so the security controls can be authored, tested, and demonstrated locally without a paid AWS account.

## Security approach

The design is driven by five ranked threats documented in [`Docs/threat-model.md`](Docs/threat-model.md):

1. **T1 — CI/repository compromise → malicious production artifact**
2. **T2 — Application RCE → Kubernetes/node/AWS lateral movement**
3. **T3 — Credential compromise → unauthorized customer-data access**
4. **T4 — Sensitive customer data → logs/telemetry exposure**
5. **T5 — Compromised workload → malicious egress/exfiltration**

Every implemented control maps to one of these threats or is explicitly justified as defence-in-depth, auditability, or governance.

## Repository layout

```text
.
├── .github/
│   ├── CODEOWNERS
│   └── workflows/
│       ├── build.yml
│       └── security-gates.yml
├── Docs/
│   ├── break-glass.md
│   ├── decisions-log.md
│   ├── decisions.md
│   ├── log-redaction.md
│   ├── rotation.md
│   └── threat-model.md
├── app/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── iam/
│   ├── accounts-api-policy.json
│   ├── github-actions-ecr-policy.json
│   └── github-actions-ecr-trust.json
├── k8s/
│   ├── accounts-api-egress.yaml
│   ├── accounts-api-secrets.yaml
│   ├── accounts-api.yaml
│   └── namespace.yaml
├── policy/
│   ├── checkov/
│   ├── falco/
│   ├── kyverno/
│   └── tests/
├── scripts/
│   ├── check_iac_gate.py
│   └── validate_waivers.py
├── security/
│   └── waivers.yaml
├── terraform/
│   ├── accounts-api.tf
│   └── ecr.tf
├── .gitattributes
├── .gitignore
└── Makefile
```

## One-command validation

Run the locally reproducible security controls with:

```bash
make security
```

This covers the IAM regression test, Kyverno policy tests, Terraform validation, and the selected Checkov controls.

The repository does **not** require AWS credentials for these local checks.

## Run the representative service

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r app/requirements.txt

uvicorn app.main:app --reload --port 8080
```

Verify:

```bash
curl http://localhost:8080/health

curl http://localhost:8080/v1/accounts/account-001

curl \
  -H 'X-User-Id: customer-001' \
  http://localhost:8080/v1/accounts/account-001
```

Expected behaviour:

```text
/health                    → 200
account without identity  → 401
valid identity            → 200
unauthorised identity     → 403
```

`X-User-Id` is only a local authentication stand-in. It is not the production authentication mechanism.

## Container hardening

Build:

```bash
docker build \
  --file app/Dockerfile \
  --tag accounts-api:test \
  app
```

The image uses:

* a digest-pinned Python base image
* a dedicated non-root user
* UID/GID `10001`
* no unnecessary Linux capabilities
* a Kubernetes read-only root filesystem
* `allowPrivilegeEscalation: false`
* health checks

Locally verified:

```bash
docker inspect accounts-api:test \
  --format '{{.Config.User}}'
```

Expected:

```text
10001:10001
```

And:

```bash
docker run --rm accounts-api:test \
  python -c 'import os; print(os.getuid(), os.getgid())'
```

Expected:

```text
10001 10001
```

## Kubernetes security

The `accounts` namespace uses Pod Security Admission with the `restricted` profile.

Kyverno provides workload-specific admission controls.

Run:

```bash
kyverno test policy/tests
```

Current local regression evidence:

```text
Test Summary: 1 tests passed and 0 tests failed
```

The negative fixture contains a container-runtime socket mount:

```text
policy/tests/accounts-api-runtime-bad.yaml
```

and is rejected by:

```text
policy/kyverno/accounts-api-runtime.yaml
```

A direct policy evaluation reports the expected validation failure:

```text
accounts-api must not mount a container runtime socket.
```

That is a successful negative test: the unsafe workload was rejected.

The production image-trust policy is separate:

```text
policy/kyverno/accounts-api-image-trust.yaml
```

It requires the configured GitHub Actions signing identity and digest verification for production `accounts-api` images.

Live registry-backed Cosign admission verification was not run during this assessment.

## Terraform and IaC policy tests

Threat-model-specific Checkov policies are under:

```text
policy/checkov/
```

Test the negative fixture:

```bash
checkov \
  --file policy/tests/terraform/bad.tf \
  --external-checks-dir policy/checkov \
  --framework terraform
```

The `bad.tf` fixture intentionally violates the security baseline.

Test the positive fixture:

```bash
checkov \
  --file policy/tests/terraform/good.tf \
  --external-checks-dir policy/checkov \
  --framework terraform
```

The custom accounts-api controls pass on the positive fixture and fail on the negative fixture.

Built-in Checkov recommendations outside the selected threat-model scope may still be reported. They are not automatically treated as blocking findings.

Terraform is validated without applying infrastructure:

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
```

Current validation result:

```text
Success! The configuration is valid.
```

## IAM and workload identity

`accounts-api` uses a dedicated IAM policy through EKS Pod Identity.

Current permissions are deliberately limited to:

```text
secretsmanager:GetSecretValue
secretsmanager:DescribeSecret
kms:Decrypt
```

The resources are scoped to the application's database secret and encryption key.

KMS decryption is constrained with:

```text
kms:ViaService = secretsmanager.ap-south-1.amazonaws.com
```

Regression test:

```bash
python policy/tests/test_iam_policy.py
```

Current result:

```text
IAM policy checks passed
```

The supplied wildcard IAM policy has therefore been replaced by a workload-specific authorization boundary.

## Build and release integrity

The intended production release path is:

```text
GitHub
  ↓
GitHub Actions OIDC
  ↓
scoped AWS build role
  ↓
ECR
  ↓
immutable commit-derived tag
  ↓
image digest
  ├── Cosign signature
  └── SPDX SBOM attestation
  ↓
verification
  ↓
admission
```

The ECR repository configuration uses immutable image tags.

The GitHub OIDC trust policy is scoped to the repository identity, owner identity, `main` branch and `Build and Sign` workflow.

Relevant files:

```text
.github/workflows/build.yml
iam/github-actions-ecr-trust.json
iam/github-actions-ecr-policy.json
terraform/ecr.tf
```

### Signature limitation

A valid signature establishes that the artifact was signed by the trusted CI identity under the configured verification policy.

It does **not** prove:

* the source code is safe
* dependencies contain no vulnerabilities
* the application has no exploitable logic
* the artifact is appropriate for every deployment context

## Pipeline gates and waiver path

The initial gate posture is deliberately risk-based.

| Control                       | Day-one posture |
| ----------------------------- | --------------- |
| Secret detection              | Block           |
| SCA HIGH/CRITICAL             | Block           |
| SAST ERROR                    | Block           |
| Threat-model IaC checks       | Block           |
| Other Checkov recommendations | Warn/report     |

Secret scanning uses a full Git history checkout with `fetch-depth: 0`.

Waivers live in:

```text
security/waivers.yaml
```

and are validated by:

```text
scripts/validate_waivers.py
```

A waiver requires:

* finding identifier
* affected repository/workload
* owner
* approver
* reason
* creation date
* hard expiry

Maximum waiver lifetime is seven days. Expired waivers fail validation.

The emergency path is documented in:

```text
Docs/break-glass.md
```

It is temporary, scoped, attributable and followed by a post-incident review.

## Secrets and data protection

Production secrets originate in AWS Secrets Manager.

The intended EKS delivery path is:

```text
AWS Secrets Manager
        ↓
EKS Pod Identity
        ↓
ASCP / Secrets Store CSI Driver
        ↓
read-only mounted secret
        ↓
accounts-api
```

Configuration:

```text
k8s/accounts-api-secrets.yaml
```

No plaintext credential is committed to the repository.

Rotation and emergency response are documented in:

```text
Docs/rotation.md
```

The emergency rotation target is 15 minutes from incident declaration to the new credential becoming active in the workload.

## Logging and customer data

The log-redaction specification is:

```text
Docs/log-redaction.md
```

The application logging design prohibits request/response bodies containing customer data and excludes:

```text
name
email
phone
IBAN
balance
card data
authorization headers
API keys
database credentials
Secrets Manager values
```

The design explicitly recognises that infrastructure telemetry can still expose operational metadata such as timestamps, paths, status codes, timing, source/network metadata and correlation identifiers.

Redaction therefore reduces unnecessary data exposure; it does not prove zero sensitive information can ever enter telemetry.

## Runtime detection

A workload-specific Falco rule detects shell execution inside `accounts-api`:

```text
policy/falco/accounts-api-runtime.yaml
```

The rule defines its alert payload, routing, owner and first responder actions.

Live runtime event generation was not reproduced against a Kubernetes node during the assessment.

## Egress

`accounts-api` uses default-deny egress with explicit allowances for:

* cluster DNS
* the third-party KYC provider

Configuration:

```text
k8s/accounts-api-egress.yaml
```

The KYC CIDR in the repository is documentation-only and must be replaced with the provider's real controlled CIDR range.

Kubernetes NetworkPolicy provides L3/L4 control. It cannot establish that an allowed HTTPS connection is benign or prevent malicious data exfiltration over an explicitly allowed connection.

## AWS production mapping

| Local/repository control | AWS/EKS production mapping                   |
| ------------------------ | -------------------------------------------- |
| Local Kubernetes         | Amazon EKS                                   |
| PSA + Kyverno            | EKS admission controls                       |
| Local container          | Amazon ECR                                   |
| Cosign                   | Signed ECR artifact + admission verification |
| GitHub OIDC              | GitHub Actions → AWS IAM federation          |
| ServiceAccount identity  | EKS Pod Identity                             |
| Secrets Store CSI        | AWS Secrets Manager + ASCP                   |
| PostgreSQL               | Amazon RDS for PostgreSQL                    |
| Audit logging            | AWS CloudTrail                               |
| Runtime detection        | Falco / AWS runtime security services        |
| NetworkPolicy            | EKS network controls                         |

Where a control cannot be reproduced locally, the repository contains the production-oriented configuration and states the verification limitation rather than treating configuration as proof of runtime enforcement.

## Known unverified controls

The following are production-authored but were not exercised against a live AWS environment during the assessment:

* GitHub OIDC assumption into AWS
* ECR tag immutability
* Cosign registry-backed signing/verification
* SBOM attestation retrieval from the registry
* Secrets Manager / ASCP integration
* live NetworkPolicy enforcement
* live Falco event generation
* emergency rotation against an actual RDS/Secrets Manager pair

These are intentionally identified rather than presented as locally proven.

## Security design principles

**Least privilege** — compromised workloads receive only the access required for their function.

**Prevent before detect** — admission, IAM, artifact trust and network controls stop known-bad states where practical.

**Immutable release path** — source, build, artifact digest, signature and SBOM are linked.

**Fail closed** — security-critical controls reject unsafe configurations.

**Controlled exceptions** — blocking gates have an explicit, expiring waiver and separate break-glass path.

**Honest limitations** — local tests are not presented as proof of live AWS enforcement.

## Validation summary

| Area                         | Status                                        |
| ---------------------------- | --------------------------------------------- |
| Threat model                 | Complete                                      |
| Representative service       | Complete                                      |
| Docker hardening             | **Locally verified**                          |
| IAM least privilege          | **Locally verified**                          |
| Kyverno runtime policy       | **Locally verified**                          |
| Terraform remediation        | **Locally verified**                          |
| Checkov custom controls      | **Locally verified**                          |
| GitHub OIDC trust            | Authored                                      |
| ECR immutability             | Authored                                      |
| Cosign signing               | Authored                                      |
| SBOM attestation             | Authored                                      |
| Image admission verification | Authored; live registry test not run          |
| Pipeline gates               | Authored; live CI execution should be checked |
| Waiver validation            | Authored                                      |
| Runtime detection            | Authored; live Falco event not reproduced     |
| Egress control               | Authored; CNI enforcement not reproduced      |
| Secrets delivery             | Authored; live AWS integration not run        |
| Rotation procedure           | Documented                                    |
| Log-redaction specification  | Documented                                    |
| Final decisions              | Complete                                      |

## Documents

* [`Docs/threat-model.md`](Docs/threat-model.md) — ranked threats, trust boundaries and traceability
* [`Docs/decisions-log.md`](Docs/decisions-log.md) — engineering decisions and assumptions
* [`Docs/decisions.md`](Docs/decisions.md) — final decisions, trade-offs and blast-radius analysis
* [`Docs/break-glass.md`](Docs/break-glass.md) — emergency production procedure
* [`Docs/rotation.md`](Docs/rotation.md) — secret rotation and emergency rotation
* [`Docs/log-redaction.md`](Docs/log-redaction.md) — customer-data logging specification
