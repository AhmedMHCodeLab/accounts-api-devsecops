# accounts-api  (DevSecOps Security Assessment)

Security controls and policy-as-code for a representative banking workload running on Kubernetes and AWS.

> **Assessment note:** The production `accounts-api` is assumed to already exist. This repository contains a minimal representative implementation so the security controls can be built, tested, and demonstrated locally without a paid cloud account.

## Security approach

The design is driven by five ranked threats documented in [`Docs/threat-model.md`](Docs/threat-model.md):

* CI/repository compromise → malicious production artifact
* Application RCE → Kubernetes/node/AWS lateral movement
* Credential compromise → unauthorized customer-data access
* Sensitive customer data → logs/telemetry exposure
* Compromised workload → malicious egress/exfiltration

Every security control in this repository maps to one of these threats or is explicitly justified as defence-in-depth, auditability, or governance.

## Repository layout

```text
.
├── Docs/
│   ├── decisions-log.md
│   ├── decisions.md
│   └── threat-model.md
├── app/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── iam/
├── k8s/
├── policy/
│   ├── checkov/
│   ├── kyverno/
│   └── tests/
└── terraform/
```

## Local prerequisites

The assessment is designed to run without AWS.

Required:

* Docker
* Python 3.12+
* `kubectl`
* `kind`
* `kyverno` CLI
* `checkov`
* `trivy`

Optional:

* `cosign`
* `syft`

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
curl http://localhost:8080/v1/accounts/acct-001
curl -H 'X-User-Id: customer-001' http://localhost:8080/v1/accounts/acct-001
```

Expected:

```text
/health                         → 200
account without identity       → 401
valid identity                 → 200
unauthorised identity          → 403
```

The `X-User-Id` header is only a local test stand-in. It is not the production authentication mechanism.

## Build the container

```bash
docker build -t accounts-api:dev ./app
```

The image is intended to run as a non-root user and expose only the application port.

## Kubernetes policy tests

The Kubernetes security baseline uses Pod Security Admission plus Kyverno for workload-specific rules.

Run Kyverno tests:

```bash
kyverno test policy/tests/
```

A deliberately insecure workload must be rejected.

The namespace baseline is defined in:

```text
k8s/namespace.yaml
```

Workload-specific policies are under:

```text
policy/kyverno/
```

## Terraform / IaC policy tests

Custom Checkov policies are under:

```text
policy/checkov/
```

Test the positive and negative fixtures:

```bash
checkov \
  -d policy/tests/terraform \
  --external-checks-dir policy/checkov \
  --framework terraform
```

The `bad.tf` fixture intentionally violates the security baseline.

The `good.tf` fixture demonstrates the expected production configuration.

Built-in Checkov findings may also be reported. The assessment does not require every generic scanner finding to be eliminated; controls are prioritised according to the threat model.

## AWS production mapping

The local repository demonstrates the security behaviour without deploying AWS infrastructure.

Production equivalents:

| Local control                   | AWS/EKS production mapping                    |
| ------------------------------- | --------------------------------------------- |
| Local Kubernetes                | Amazon EKS                                    |
| Kyverno / PSA                   | EKS admission controls                        |
| Local image                     | Amazon ECR                                    |
| Cosign signing                  | Signed ECR artefacts + admission verification |
| GitHub OIDC                     | GitHub Actions → AWS IAM federation           |
| Local Kubernetes ServiceAccount | EKS workload identity                         |
| Secrets integration             | AWS Secrets Manager                           |
| PostgreSQL                      | Amazon RDS for PostgreSQL                     |
| Cloud audit                     | AWS CloudTrail                                |
| Runtime detection               | Falco / GuardDuty Runtime Monitoring          |
| NetworkPolicy                   | EKS network controls                          |

Where a control cannot be reproduced locally, the repository contains the production-oriented configuration and documents the AWS implementation rather than pretending the local test is equivalent.

## Security design principles

The implementation follows these principles:

**Least privilege:** a compromised application should receive only the access required to perform its function.

**Prevent before detect:** admission, IAM, artifact trust, and network controls should stop known-bad states before runtime.

**Immutable release path:** source → build → artifact → admission is traceable.

**Fail closed:** security-critical controls should deny unsafe configurations by default.

**Controlled exceptions:** blocking controls have an explicit, time-bounded waiver/break-glass path rather than informal bypasses.

**Honest limitations:** each control documents what it does not prove or prevent.

## Current implementation status

| Area                     | Status      |
| ------------------------ | ----------- |
| Threat model             | In progress |
| Representative service   | Complete    |
| Container hardening      | In progress |
| Kubernetes baseline      | In progress |
| Kubernetes policy tests  | In progress |
| Terraform remediation    | In progress |
| IAM least privilege      | In progress |
| CI integrity             | Pending     |
| Pipeline gates / waivers | Pending     |
| Runtime detection        | Pending     |
| Egress control           | Pending     |
| Secrets / rotation       | Pending     |
| Log redaction            | Pending     |
| Final decisions document | Pending     |

## Documents

* [`Docs/threat-model.md`](Docs/threat-model.md) — ranked threats, trust boundaries and control traceability
* [`Docs/decisions-log.md`](Docs/decisions-log.md) — working engineering decisions and assumptions
* [`Docs/decisions.md`](Docs/decisions.md) — final assessment decisions and trade-offs
