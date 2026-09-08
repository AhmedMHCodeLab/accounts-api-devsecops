# Threat Model: accounts-api

**Status:** Draft for assessment submission.

**Scope:** `accounts-api` on EKS in `ap-south-1`, its GitHub Actions build path, ECR, Kubernetes identity/RBAC, RDS PostgreSQL, Secrets Manager, KYC egress, and shared-cluster boundaries.

**Method:** Five threats ranked by likelihood and impact in this environment. Controls are selected against realistic attack paths rather than for tool coverage.

**Assumptions:** ECR is the production container registry; `accounts-api` has a dedicated Kubernetes ServiceAccount; EKS Pod Identity is used for AWS workload identity; RDS is intended to be private; GitHub Actions is the supported deployment path.

## 1. Trust boundaries

```text
Developer / maintainer
        │
        ▼
┌────────────────────┐
│ GitHub repository  │
│ + Actions runner   │
└─────────┬──────────┘
          │ build / OIDC
          ▼
┌────────────────────┐
│ ECR                │
│ image + attestations│
│ + signature        │
└─────────┬──────────┘
          │ deployment
          ▼
════════════ TB-1: CI / registry → EKS ════════════

┌──────────────────────────────────────────────────────────────┐
│ Shared EKS cluster                                          │
│                                                              │
│  ┌─────────────────────┐                                    │
│  │ accounts-api Pod    │                                    │
│  │ ServiceAccount      │                                    │
│  └──────┬──────────────┘                                    │
│         │                                                    │
│    ┌────┴──────┐        ┌────────────────┐                   │
│    │ AWS IAM   │        │ KYC provider  │                   │
│    │ / Pod ID  │        │ public HTTPS  │                   │
│    └────┬──────┘        └────────────────┘                   │
└─────────┼────────────────────────────────────────────────────┘
          │
   ═══════╪════ TB-2: workload → AWS / data ═══════
          │
     ┌────┴─────┐
     │ RDS      │
     │ Postgres │
     └──────────┘

══════════ TB-3: accounts-api ↔ other workloads ═══════════

══════════ TB-4: accounts-api → public internet ═══════════
```

## 2. Ranked threats

### T-01 · Compromised repository or CI deploys attacker-controlled code

**Entry point:** compromised maintainer account, modified workflow, malicious dependency, or compromised third-party action.

**Reaches:** CI credentials, ECR, and ultimately the production `accounts-api` workload.

**Control:** GitHub OIDC trust scoped to the intended repository/ref; actions pinned to immutable commit SHAs; immutable image references; SBOM attestation; image signing; admission verification.

**Why ranked first:** CI is a direct control-plane path from source to production. GitHub recommends pinning actions to full commit SHAs, and OIDC `sub` should be explicitly constrained rather than trusting any workflow from the organisation.

### T-02 · Application RCE becomes a Kubernetes, node, or AWS compromise

**Entry point:** vulnerable dependency, malicious image, application exploit, or runtime compromise.

**Reaches:** the container first; then Kubernetes API, node resources, other workloads, or AWS APIs depending on privileges and network access.

**Control:** non-root execution, no privilege escalation, no host networking, no host filesystem mounts, no Docker socket, minimal RBAC, dedicated ServiceAccount, least-privilege AWS identity, admission enforcement, and network isolation.

**Reasoning:** the shared cluster makes post-compromise lateral movement a material concern, so reducing workload privilege and host access is more valuable than relying on detection alone.

### T-03 · Compromised workload or credentials reach customer data

**Entry point:** stolen Pod Identity credentials, database credentials, application secrets, or access obtained through a compromised workload.

**Reaches:** RDS customer records, Secrets Manager, KMS-protected material, and the KYC integration according to granted permissions.

**Control:** EKS Pod Identity with a workload-specific IAM role; narrowly scoped IAM actions/resources; Secrets Manager as the source of truth; credential rotation; private database connectivity; no plaintext credentials in Git or Kubernetes manifests.

**Reasoning:** EKS recommends Pod Identity for new workload identity designs and recommends application-specific IAM roles with least privilege.

### T-04 · Sensitive customer data is exposed through logs or telemetry

**Entry point:** application logging, exception handling, debugging, CI artefacts, or overly broad operational access.

**Reaches:** customer PII and financial data replicated into logging/SIEM systems.

**Control:** structured application logging with sensitive-field redaction before emission; no request/response bodies by default; restricted log access; retention limits; redaction tests.

**Residual risk:** upstream infrastructure may still retain operational metadata and identifiers. Redaction is therefore treated as a minimisation control, not proof that no sensitive information can ever appear in telemetry.

### T-05 · Compromised workload uses egress for command-and-control or exfiltration

**Entry point:** RCE or malicious dependency execution inside the pod.

**Reaches:** public internet destinations and any permitted AWS/third-party endpoint.

**Control:** default-deny egress for `accounts-api`, with explicit allowance for DNS and the KYC provider plus only the AWS dependencies required by the service.

**Limitation:** network policy restricts reachable destinations at the network layer; it does not establish that an allowed endpoint is benign or prevent malicious data from travelling over an otherwise permitted connection.

## 3. Overrated threat

**Volumetric DDoS against the public API.**

It remains an availability concern, but this submission should not spend its limited engineering budget primarily on volumetric protection because AWS edge services provide substantial platform-level absorption. The higher-value risks in this environment are software-supply-chain compromise, workload privilege escalation, customer-data access, and post-compromise movement.

Application-layer abuse remains relevant and belongs in authentication, rate limiting, monitoring, and incident response.

## 4. Control traceability

| Threat | Controls implemented elsewhere                                       |
| ------ | -------------------------------------------------------------------- |
| T-01   | Sections 3–5: OIDC, artifact integrity, SBOM, signing, admission     |
| T-02   | Sections 4–5: workload hardening, RBAC, admission, runtime detection |
| T-03   | Sections 4 and 6: least-privilege IAM, Secrets Manager, rotation     |
| T-04   | Section 6: log redaction and data protection                         |
| T-05   | Section 5: egress restriction and runtime detection                  |

Controls that do not directly map to T-01 through T-05 are included only where they provide a necessary defence-in-depth, auditability, or governance property.

## Sources

* AWS EKS Security Best Practices: https://docs.aws.amazon.com/eks/latest/best-practices/security.html
* AWS EKS IAM Best Practices: https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html
* AWS EKS Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
* GitHub Actions security hardening: https://docs.github.com/en/actions/reference/security/secure-use
* GitHub Actions OIDC reference: https://docs.github.com/en/actions/reference/security/oidc
* Kyverno ImageValidatingPolicy: https://kyverno.io/docs/policy-types/image-validating-policy/
