# Decisions and Trade-offs

## 1. Biggest decisions

### D-01 · Trust the build, not the tag

**Decision:** production admission requires an image produced by the approved GitHub Actions workflow and carrying the expected signature; the deployment reference is immutable.

**Why:** a mutable `latest` tag allows the artifact referenced by deployment to change independently of the build that was reviewed.

**Trade-off:** signing and admission introduce operational dependencies and require a defined failure/waiver path.

**Important limitation:** the signature proves artifact provenance/integrity under the configured trust policy. It does **not** prove the source is safe, the image is vulnerability-free, or the running application is trustworthy. Current Kyverno supports verification of both image signatures and signed attestations.

### D-02 · Use EKS Pod Identity for workload AWS access

**Decision:** use EKS Pod Identity rather than IRSA for this new workload.

**Why:** AWS currently recommends Pod Identity for EKS workloads and it avoids per-cluster OIDC provider configuration while supporting workload-specific IAM roles.

**Trade-off:** it introduces the Pod Identity Agent dependency and requires a supported AWS SDK. It does not replace least-privilege IAM.

### D-03 · Do not block every security finding on day one

**Decision:** only findings above the defined risk threshold block the merge initially; lower-confidence/lower-impact findings warn.

**Why:** an indiscriminate gate creates developer friction and false-positive fatigue. The goal is a gate engineers continue to trust.

**Compensating controls:** lower-severity findings remain visible, owned, tracked to remediation SLAs, and can be promoted to blocking once their signal quality and operational impact are understood.

## 2. Enforcement posture

**Block on day one:**

* leaked secrets
* critical/high-confidence exploitable SCA findings
* high-confidence critical IaC misconfigurations
* unsigned/untrusted production images
* admission violations of the workload baseline

**Warn initially:**

* lower-confidence SAST findings
* medium/low vulnerabilities
* non-production policy deviations

**Promotion criteria:**

A warning becomes blocking when we have evidence of acceptable false-positive volume, an owner for failures, documented remediation/waiver handling, and a demonstrated fix path for affected teams.

The waiver mechanism is therefore part of the control rather than an exception to it.

## 3. Blast radius

### Scenario A — `accounts-api` is compromised via RCE

**Attacker reaches:** the process and data available to `accounts-api`; potentially AWS APIs allowed by its Pod Identity and any network destinations permitted to the workload.

**Design denies:** host filesystem access, Docker socket access, privileged execution, unnecessary Kubernetes API access, broad IAM actions/resources, and unrestricted egress.

**Evidence afterwards:** Kubernetes audit events, admission decisions, runtime alerts, AWS CloudTrail, Secrets Manager access, and application/SIEM telemetry.

**Evidence goes dark:** activity performed entirely inside the application process that generates no detectable syscall/network/IAM anomaly, and any data exfiltration that uses an explicitly permitted destination.

### Scenario B — GitHub maintainer account is compromised and workflow modified

**Attacker reaches:** repository code/workflow execution and whatever AWS permissions the trusted workflow can obtain.

**Design denies:** arbitrary GitHub repositories/workflows assuming the production role through tightly scoped OIDC trust; long-lived AWS credentials; deployment of unsigned/untrusted images.

**Evidence afterwards:** GitHub audit/workflow history, AWS CloudTrail, registry events, image signature/attestation metadata, and admission decisions.

**Evidence goes dark:** a compromised maintainer using their legitimate repository permissions can still make changes that satisfy the repository's normal trust path. This is why repository governance and independent detection remain necessary.

## 4. Detection coverage gap

One attack path I would **not claim to fully detect** is data exfiltration over an explicitly permitted KYC HTTPS connection.

Once the workload is allowed to communicate with that destination, L3/L4 controls cannot determine whether the traffic is legitimate KYC traffic or attacker-controlled data travelling over the same channel.

Closing that gap requires application-aware outbound inspection or a proxy/control point capable of validating request semantics. I would not introduce that complexity in this four-hour build without evidence that the risk justifies the operational and latency cost.

## 5. Regulatory framing

| Technical control                        | Regulatory/security purpose                                       |
| ---------------------------------------- | ----------------------------------------------------------------- |
| Immutable signed artefacts + audit trail | Demonstrable software-change integrity and release accountability |
| Least-privilege IAM                      | Access control and reduction of unauthorised data access          |
| Secrets Manager + rotation               | Credential protection and incident response readiness             |
| Log redaction                            | Data minimisation and reduction of sensitive-data exposure        |
| Audit logging                            | Traceability of privileged/security-relevant activity             |
| Network isolation / egress restriction   | Reduction of unauthorised data transfer paths                     |

## 6. What was cut

I deliberately did not attempt to build every possible DevSecOps control.

The cut items are broad runtime detection coverage, a full service-mesh/proxy egress architecture, exhaustive DLP, and organisation-wide policy rollout.

The first production rollout after this exercise would be to establish **central policy enforcement and the waiver/exception workflow across the rest of the EKS estate**, because one secure service is not a platform security programme.

## 7. Implementation principle

The submission is intentionally biased toward controls that fail closed at a trust boundary:

**source → build → artifact → admission → workload → identity → data → egress**

A control is considered successful only when its failure mode, owner, evidence, and waiver path are explicit.
