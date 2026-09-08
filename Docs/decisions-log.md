# Engineering Decisions Log

**Project:** `accounts-api` DevSecOps Assessment
**Status:** Working document — updated throughout the assessment
**Purpose:** Record security decisions, assumptions, trade-offs, and conclusions so implementation remains traceable to the threat model and does not depend on memory.

---

## D-001 — Threat Model Baseline

**Decision:** Use five primary threats as the security baseline for Sections 2–6.

1. **T1 — CI/repository compromise → malicious production artifact**
2. **T2 — Application RCE → Kubernetes/node/AWS lateral movement**
3. **T3 — Credential compromise → unauthorized customer-data access**
4. **T4 — Sensitive customer data → logs/telemetry exposure**
5. **T5 — Compromised workload → malicious egress/exfiltration**

**Reason:** Every implemented control must trace back to one of these threats unless explicitly justified as defence-in-depth, auditability, or governance.

---

## D-002 — Workload Manifest Defect Ranking

**Decision:** Rank the supplied Kubernetes defects by exploitability and blast radius rather than scanner severity.

| Rank | Defect                                         | Reason                                                                              |
| ---- | ---------------------------------------------- | ----------------------------------------------------------------------------------- |
| 1    | Docker/container-runtime socket via `hostPath` | Direct path from pod compromise toward node/container-runtime control               |
| 2    | Wildcard RBAC                                  | Grants broad namespace access, including Secrets, Pods and ConfigMaps               |
| 3    | `hostNetwork` + host filesystem access         | Removes important pod isolation boundaries and weakens network/security assumptions |
| 4    | `runAsUser: 0`                                 | Increases post-exploitation capability, especially when combined with host access   |

**Important qualification:** `hostNetwork` does not by itself prove arbitrary packet sniffing. The defensible claim is loss of network namespace isolation and weakened assumptions around network policy and workload isolation.

**Mapped threats:** T2, T3, T5.

---

## D-003 — Container Runtime Socket

**Decision:** `accounts-api` must not mount a container-runtime socket.

**Reason:** Runtime socket access creates a direct path from a compromised container toward node/container-runtime control. The workload has no legitimate requirement to control the node runtime.

**Enforcement:** Admission policy rejects known container-runtime socket mounts.

**Mode:** `Enforce`.

**Waiver:** Not permitted for `accounts-api`; there is no legitimate business requirement.

**Mapped threat:** T2.

---

## D-004 — Host Filesystem Access

**Decision:** `accounts-api` must not use `hostPath`.

**Reason:** Kubernetes and AWS guidance treat `hostPath` as a significant security boundary risk. This workload has no legitimate requirement for host filesystem access.

**Enforcement:** Pod Security Admission Restricted provides the baseline restriction. We do not duplicate the generic control in Kyverno unless a workload-specific policy requires it.

**Mode:** `Enforce`.

**Mapped threat:** T2.

---

## D-005 — Host Networking

**Decision:** `accounts-api` must not use `hostNetwork: true`.

**Reason:** The service has no stated requirement for the node's network namespace. Preserving normal pod network isolation reduces the blast radius of application compromise.

**Enforcement:** Pod Security Admission Restricted.

**Mode:** `Enforce`.

**Mapped threats:** T2, T5.

---

## D-006 — Non-root Execution

**Decision:** The workload must run as non-root and must not permit privilege escalation.

**Reason:** The service has no stated requirement for root. Reducing privileges limits post-exploitation capability.

**Enforcement:** Pod Security Admission Restricted plus explicit workload validation where useful.

**Mode:** `Enforce`.

**Trade-off:** Workloads with genuine elevated requirements should use the waiver process rather than weakening the baseline.

**Mapped threat:** T2.

---

## D-007 — Workload Security Baseline

**Decision:** `accounts-api` uses Kubernetes Pod Security Admission with the `restricted` profile. Kyverno is reserved for workload-specific requirements not adequately expressed by the standard Kubernetes baseline.

**Reason:** `accounts-api` handles customer financial data and runs in a shared EKS cluster. A security-critical workload deserves stronger pod isolation than a generic baseline.

**Trade-off:** Restricted can create compatibility friction for legitimate workloads. This is handled through controlled exceptions rather than weakening the baseline.

**Mapped threats:** T2, T5.

---

## D-008 — Kubernetes RBAC

**Decision:** Do not grant Kubernetes API permissions unless the application has a demonstrated requirement.

**Current conclusion:** The supplied wildcard Role is unjustified. `accounts-api` should have no `Role`/`RoleBinding` if it does not need to query or modify Kubernetes resources.

**Reason:** An application compromise must not become a credentialed Kubernetes control-plane compromise.

**Preferred implementation:** Dedicated ServiceAccount with no unnecessary RBAC permissions.

**Mapped threats:** T2, T3.

---

## D-009 — AWS Workload Identity

**Decision:** Use EKS Pod Identity for the new workload.

**Reason:** Current AWS EKS guidance recommends Pod Identity for new workload identity designs. It provides workload-specific IAM roles without long-lived AWS credentials.

**Trade-off:** Requires the EKS Pod Identity Agent and compatible SDK behaviour.

**Mapped threat:** T3.

---

## D-010 — Least-Privilege IAM for accounts-api

**Decision:** Replace the supplied wildcard IAM policy with a workload-specific policy granting only the AWS actions and resources required by `accounts-api`.

**Reason:** The original `Allow` + `NotAction` + `Resource: "*"` effectively grants broad AWS access to a compromised workload. For a banking workload, IAM compromise must not become account-level compromise.

**Current scope:**
- `secretsmanager:GetSecretValue` on the `accounts-api` production database secret only
- `kms:Decrypt` on the specific KMS key used to protect that secret
- KMS decrypt restricted through `kms:ViaService` to Secrets Manager

**Not granted:** IAM administration, EC2/EKS administration, S3, KMS administration, or unrestricted access to other Secrets Manager resources.

**Important:** Stream/audit permissions will be added only after the exact AWS services and resource requirements are established. They will not be invented solely to make the policy appear complete.

**Security effect:** A compromised `accounts-api` workload is denied the arbitrary AWS API access allowed by the original policy and is restricted to its explicitly required secrets/data path.

**Mapped threats:** T2, T3.

---

## D-011 — Image Trust

**Decision:** Production admission will trust signed images from the approved CI identity and use immutable image references.

**Reason:** A mutable tag does not establish which artifact was reviewed or produced.

**Important limitation:** A valid signature proves artifact provenance/integrity under the configured trust policy. It does not prove the source is safe, that dependencies are vulnerability-free, or that the application itself is trustworthy.

**Mapped threat:** T1.

---

## D-012 — SBOM

**Decision:** Generate an SBOM at build time and publish it as an attestation associated with the image.

**Reason:** The service needs an auditable inventory of software components to support vulnerability response and provenance.

**Trade-off:** SBOMs improve visibility but do not themselves prove the absence of vulnerabilities.

**Mapped threat:** T1.

---

## D-013 — Immutable Image Tags

**Decision:** Use versioned image tags and immutable registry behaviour. Deployment should ultimately resolve to an immutable artifact reference/digest.

**Reason:** `latest` is mutable and weakens release traceability.

**Mapped threat:** T1.

---

## D-014 — GitHub Actions → AWS Authentication

**Decision:** GitHub Actions authenticates to AWS using OIDC rather than long-lived access keys.

**Reason:** Short-lived federated credentials reduce credential theft and rotation risk.

**Trust requirement:** OIDC trust is scoped to the intended repository and workflow/ref rather than an organisation-wide or wildcard trust.

**Mapped threat:** T1, T3.

---

## D-015 — Enforcement Philosophy

**Decision:** Prefer preventative enforcement at trust boundaries over detection where the risk justifies it.

**Examples:**

* admission blocks unsafe workload configurations
* IAM denies unnecessary AWS access
* registry/signature controls prevent untrusted artifacts
* network policy restricts unnecessary communication

Detection remains a secondary control or compensating control where prevention is impractical.

**Mapped threats:** T1–T5.

---

## D-016 — Shared Cluster

**Decision:** Treat `accounts-api` as untrusted relative to other workloads in the EKS cluster.

**Reason:** Approximately a dozen teams share the cluster. Application compromise must not automatically imply node or neighbouring workload compromise.

**Controls:** Pod hardening, RBAC minimisation, network isolation, runtime detection, least-privilege AWS identity.

**Mapped threats:** T2, T5.

---

## D-017 — Egress

**Decision:** `accounts-api` should have default-deny egress with explicit connectivity for the KYC provider and required platform dependencies.

**Reason:** The application has one known legitimate external dependency. Unrestricted outbound access creates an unnecessary C2/exfiltration path after compromise.

**Limitation:** L3/L4 network policy cannot prove that an allowed destination is benign and cannot prevent malicious data being sent over an explicitly permitted connection.

**Mapped threat:** T5.

---

## D-018 — RDS Exposure

**Decision:** Production PostgreSQL should be private and reachable only from the required application/data network.

**Reason:** A customer database should not be reachable directly from the public internet.

**Additional controls:** encryption at rest, backups, retention, restricted security-group ingress, and removal of plaintext password handling where possible.

**Mapped threat:** T3.

---

## D-019 — Secrets Source of Truth

**Decision:** Database credentials and other runtime secrets originate in AWS Secrets Manager and are delivered to the workload through a managed integration.

**Reason:** Secrets should not exist in Git, Terraform source, or committed Kubernetes manifests.

**Production mechanism:** External Secrets Operator or Secrets Store CSI Driver, depending on the final design.

**Mapped threats:** T3, T4.

---

## D-020 — Secret Rotation

**Decision:** Rotation must support both scheduled rotation and emergency rotation during an incident.

**Reason:** In a compromise, waiting for the normal rotation interval is unacceptable.

**Requirement:** Every credential must have an explicit emergency rotation target, and the application must tolerate secret refresh without unnecessary downtime.

**Mapped threats:** T3.

---

## D-021 — Log Minimisation

**Decision:** Sensitive customer data is redacted before being emitted into application logs.

**Fields in scope:** name, email, phone, IBAN, balance, and card-related data.

**Default:** Do not log request/response bodies containing customer data.

**Reason:** Once sensitive data enters logging and SIEM systems, its exposure surface expands significantly.

**Limitation:** Infrastructure may still retain metadata such as timestamps, paths, status codes, request IDs, or other operational context. Redaction is therefore data minimisation, not proof that no sensitive information can ever exist in telemetry.

**Mapped threat:** T4.

---

## D-022 — Encryption

**Decision:** Encrypt customer data at rest and in transit using AWS-managed encryption facilities with a controlled KMS key strategy where appropriate.

**Reason:** Encryption primarily reduces the impact of storage/media compromise and protects data in transit from network interception. It does not prevent an authorised application or stolen credential from reading plaintext.

**Mapped threat:** T3, T4.

---

## D-023 — Runtime Detection

**Decision:** Implement one workload-specific runtime detection rule rather than relying only on default rules.

**Reason:** Prevention should reduce the attack surface, but runtime detection provides visibility when prevention fails.

**Requirement:** The rule must define payload, destination, owner, escalation path, and first responder actions.

**Mapped threat:** T2, T5.

---

## D-024 — Admission Rollout

**Decision:** Security-critical controls become `Enforce`; controls with meaningful compatibility uncertainty may begin in `Audit` and promote after evidence.

**Promotion criteria:**

* false-positive rate understood
* affected workloads identified
* owner for failures defined
* remediation/waiver process tested
* representative positive and negative fixtures pass
* no unacceptable production impact observed

**Reason:** The EKS cluster is shared, so technically correct policy can still fail operationally if introduced without a rollout strategy.

---

## D-025 — Waiver Mechanism

**Decision:** Security gates require an explicit waiver path rather than an informal bypass.

**Required properties:**

* named approver
* explicit reason
* affected control
* affected repository/workload
* creation timestamp
* hard expiry
* audit trail
* build failure when the waiver expires

**Reason:** A gate with no practical exception path eventually gets disabled rather than followed.

**Mapped threats:** T1–T5 depending on the waived control.

---

## D-026 — Break-Glass

**Decision:** Production-down incidents may use a separate break-glass path rather than silently bypassing security controls.

**Requirements:**

* explicitly identified emergency condition
* authorised operator
* timestamped action
* reason recorded
* temporary scope
* post-incident review
* evidence retained

**Reason:** Availability emergencies must have a controlled escape hatch without normalising permanent bypasses.

---

## D-027 — Risk-Based Scope

**Decision:** Do not attempt to implement every available DevSecOps control.

**Reason:** The assessment rewards security judgement rather than tool count.

**Priority:** Supply-chain integrity, workload isolation, least privilege, secrets/data protection, and meaningful enforcement are higher-value than adding low-signal scanners or complex controls without an operational owner.

---

## D-028 — Local Validation

**Decision:** Use local Kubernetes and open-source tooling to demonstrate behaviour where real AWS infrastructure is unnecessary.

**Expected environment:** kind/k3d/minikube + Kyverno/PSA + local scanners.

**AWS controls:** author the real production Terraform/IAM configuration where required and document how the local test maps to AWS.

**Reason:** The assessment explicitly permits and expects local validation without paid cloud resources.

---

## D-029 — Representative Local Service

**Decision:** Build a minimal representative `accounts-api` application/container locally even though the brief says to assume the real service exists.

**Reason:** A small working service gives us an actual object against which we can validate Docker hardening, Kubernetes policies, CI, secrets handling, and runtime controls.

**Scope:** The local implementation represents the security surface only. It does not attempt to reproduce production banking functionality.

---

## D-030 — Tool Selection Principle

**Decision:** Prefer a small number of well-integrated tools over a large scanner stack.

**Current direction:**

| Concern                  | Candidate     |
| ------------------------ | ------------- |
| SCA / container scanning | Trivy         |
| SAST                     | Semgrep       |
| Secret history           | Gitleaks      |
| Terraform/IaC            | Checkov       |
| SBOM                     | Syft          |
| Image signing            | Cosign        |
| Admission                | Kyverno + PSA |
| Runtime                  | Falco         |

**Reason:** Tool choice is secondary to the control, enforcement model, and operational ownership. Alternatives remain acceptable where they provide a materially better fit.

---

## D-031 — No Kubernetes API Permissions

**Decision:** `accounts-api` has no Kubernetes `Role` or `RoleBinding`.

**Reason:** The service has no stated requirement to read or modify Kubernetes resources. Granting Kubernetes API permissions would increase the blast radius of an application compromise without providing application value.

**Implementation:**

* dedicated `accounts-api` ServiceAccount
* no Role / RoleBinding
* `automountServiceAccountToken: false`
* AWS access provided separately through EKS Pod Identity

**Security effect:** A compromised `accounts-api` process cannot use a mounted Kubernetes ServiceAccount API token to access namespace resources.

**Mapped threats:** T2, T3.

---
## D-032 — RDS and CloudTrail Hardening

**Decision:** Treat the production customer database as private, encrypted, recoverable, and protected against accidental deletion. Use centralized, multi-Region CloudTrail with global service events and log-file validation.

**RDS controls:**
- `publicly_accessible = false`
- private DB subnet group
- ingress only from the application security group
- storage encryption enabled with a controlled KMS key
- 35-day automated backup retention
- deletion protection enabled
- final snapshot required
- Multi-AZ enabled for production resilience
- RDS-managed master password rather than a plaintext Terraform password variable

**CloudTrail controls:**
- multi-Region
- global service events
- log-file validation
- organization trail in production

**Reason:** `accounts-api` processes customer financial data. A public database creates a direct attack path; lack of encryption expands the impact of storage compromise; lack of backups/deletion protection weakens recovery; incomplete CloudTrail reduces forensic capability.

**Mapped threats:** T3, T4.

**Important distinction:** Multi-AZ and backups primarily provide resilience/recovery rather than preventing confidentiality compromise. They are included because loss of customer data availability/integrity is a material banking risk.
---
### D-033 — Risk-Based IaC Gate Scope

**Decision:** Treat custom checks that directly enforce the accounts-api threat model as blocking controls. Do not automatically block deployment on every built-in Checkov recommendation.

**Rationale:** The assessment prioritises prevention of material threats over scanner-count optimisation. Some Checkov findings improve defence-in-depth but do not represent the highest-risk paths for this workload. Blocking on every recommendation would increase noise and create pressure for unjustified exceptions.

**Current blocking scope:**
- RDS is private.
- RDS storage is encrypted.
- RDS backups are enabled.
- RDS deletion protection is enabled.
- RDS final snapshot is required.
- CloudTrail is multi-Region.
- Global service events are included.
- CloudTrail log validation is enabled.
- PostgreSQL ingress is not public.

**Trade-off:** Some additional AWS hardening recommendations remain open and should be reviewed separately rather than silently treated as equivalent risk.

**Validation:** `policy/tests/terraform/bad.tf` fails the required custom checks and `policy/tests/terraform/good.tf` passes them.

**Review trigger:** Revisit the blocking scope if the production architecture, regulatory requirements, or threat model changes.
---

## D-034 — Least-Privilege Runtime IAM

**Decision:** Replace the supplied wildcard IAM policy with a workload-specific IAM policy for `accounts-api`, assumed through EKS Pod Identity.

**Current scope:**

- `secretsmanager:GetSecretValue` on the `accounts-api` production database secret only
- `kms:Decrypt` on the specific KMS key protecting that secret
- KMS decrypt restricted with `kms:ViaService` to Secrets Manager

**Not granted:** IAM administration, EC2/EKS administration, S3, KMS administration, or unrestricted access to other Secrets Manager resources.

**Reason:** The supplied `Allow` + `NotAction` + `Resource: "*"` policy gives a compromised application unnecessarily broad AWS API access. For a financial workload, compromise of the application should not become compromise of the AWS account.

**Important limitation:** The assessment does not specify the backing AWS service or resource for the audit/event stream. No additional permissions are invented. Those permissions will be added only after the concrete dependency, required actions, and target resources are established.

**Security effect:** Application compromise is contained to the minimum AWS capability currently demonstrated as required, reducing the blast radius for T2 and T3.

**Validation:** A regression test rejects unrestricted wildcard actions/resources and verifies the intended Secrets Manager and KMS permissions remain scoped to the accounts-api resources.

**Mapped threats:** T2, T3.

---


## Open Decisions

These remain intentionally unresolved until the relevant sections are implemented and researched:

* Exact image signing/trust configuration
* Exact GitHub OIDC `sub` format for the assumed repository
* ECR tag immutability implementation
* Exact SCA/SAST/IaC blocking thresholds
* Waiver file schema and signing mechanism
* Kyverno policy/test structure
* Runtime detection rule
* KYC egress enforcement mechanism
* Secrets delivery mechanism: ESO vs CSI
* Rotation implementation and exact emergency targets
* Exact logging field classification/redaction implementation
* Local service implementation details

---

## Decision Update Rule

When later research or testing changes a decision:

**Do not silently overwrite the old reasoning.**

Record:

**Previous decision → evidence → revised decision → why the change occurred → affected controls.**

This keeps the assessment auditable and preserves the reasoning behind the final architecture.
