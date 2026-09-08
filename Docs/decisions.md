# Accounts API Security Decisions and Trade-offs

## 1. Biggest decisions

### Artifact trust over tag trust

Production images are published to ECR with immutable commit-derived tags and deployed by digest. The image is signed with Cosign using the GitHub Actions OIDC identity, and the SBOM is generated from the same immutable image and attached as an attestation.

**Trade-off:** This adds CI and admission complexity, but prevents a mutable image tag from becoming the release identity. A signature proves the artifact was signed by the trusted CI identity under the configured trust policy; it does not prove the code is vulnerability-free or safe.

### Strong workload isolation

`accounts-api` runs under PSA Restricted, with no unnecessary Kubernetes RBAC, no host filesystem/runtime access, non-root execution, and workload-specific Kyverno controls.

**Trade-off:** Restricted security posture can break legitimate workloads. For this financial-data service, the stronger baseline is justified. Exceptions require an explicit, expiring waiver rather than weakening the namespace baseline.

### Deliberate non-enforcement of low-value scanner findings

Not every Checkov recommendation blocks deployment. Controls directly tied to the threat modepublic RDS exposure, encryption, backup/recovery, deletion protection, CloudTrail coverage, and public PostgreSQL ingresblock. Lower-signal recommendations initially warn.

**Trade-off:** Some defence-in-depth findings may remain open temporarily. This is deliberate risk prioritisation rather than scanner avoidance.

## 2. Enforcement posture

| Control                               | Day-one posture |
| ------------------------------------- | --------------- |
| Secret detection                      | Block           |
| SAST ERROR                            | Block           |
| SCA HIGH/CRITICAL                     | Block           |
| Threat-model IaC checks               | Block           |
| Other IaC recommendations             | Warn            |
| PSA Restricted for accounts namespace | Enforce         |
| Runtime-socket admission              | Enforce         |
| Trusted production image              | Enforce         |
| New broad cluster policies            | Audit first     |

Promotion from audit to enforce requires understood false positives, identified owners, representative positive/negative tests, tested remediation/waiver handling, and no unacceptable production impact.

Waivers are temporary, owned, approved, auditable and expire after seven days. An expired waiver fails CI.

## 3. Blast radius

### A. accounts-api compromised through RCE

The attacker initially controls the application process.

The design denies:

* Kubernetes API access because no Role or RoleBinding exists and the ServiceAccount token is not mounted.
* Node/container-runtime access through removal and admission prevention of runtime socket mounts.
* Host filesystem access through PSA Restricted.
* Privilege escalation through non-root execution and `allowPrivilegeEscalation: false`.
* Broad AWS access through the dedicated Pod Identity role.
* Unnecessary outbound destinations through default-deny egress.

The attacker can still access whatever data the application itself is legitimately authorised to access, including customer records reachable through its database credentials. This is the most important residual risk.

Evidence would come from Kubernetes audit/deployment records, AWS CloudTrail, application telemetry, Falco alerts, and Secrets Manager activity where available.

Evidence goes dark around malicious activity performed entirely through legitimate application functionality unless application-level behavioural monitoring identifies it.

### B. Maintainer GitHub account compromised

The attacker could attempt to modify application code or the CI workflow.

The design limits the blast radius through protected `main`, CODEOWNERS for workflow/security files, narrowly scoped GitHub OIDC trust, repository/owner identity restrictions, immutable ECR tags, and signed release artifacts.

A malicious workflow modification should require the protected review boundary before it can alter the trusted release workflow.

After an incident, useful evidence includes GitHub audit/workflow history, image digests, Cosign verification records, ECR image history, AWS CloudTrail, and deployment history.

Evidence goes dark if a compromised maintainer performs authorised GitHub actions without triggering a protected workflow/security-file change.

## 4. Detection gap

A malicious actor using legitimate `accounts-api` functionality to retrieve and exfiltrate unusually large volumes of authorised customer data may not trigger the current controls.

Closing that gap requires application-level behavioural analytics, data-access telemetry, anomaly detection and an operational owner. This is intentionally beyond the minimum take-home scope.

## 5. Regulatory framing

| Technical control                              | Regulatory value                                        |
| ---------------------------------------------- | ------------------------------------------------------- |
| Private RDS + restricted SG                    | Reduces unauthorised customer-data exposure             |
| Secrets Manager + least-privilege workload IAM | Access control and credential governance                |
| Log minimisation/redaction                     | Reduces unnecessary PII/cardholder-data exposure        |
| Multi-Region validated CloudTrail              | Audit-trail integrity and investigation readiness       |
| Immutable signed artifacts                     | Software supply-chain and change-control evidence       |
| Backup retention/deletion protection           | Recovery and availability of regulated customer records |

Regulatory obligations vary by jurisdiction and card-processing scope; the controls are mapped to the security objective rather than presented as proof of compliance by themselves.

## 6. What was cut

The assessment does not deploy a real AWS environment, implement a live third-party KYC integration, build a full production rotation system, or implement comprehensive runtime detection.

Those are deliberate scope decisions. The next production step would be to deploy the controls in a non-production AWS account, verify EKS Pod Identity and Secrets Manager rotation end-to-end, enforce signed-image admission, and exercise the break-glass process with real CloudTrail evidence.
