# Production Security Break-Glass Procedure

## Purpose

Provide a controlled emergency path when a security gate prevents recovery of a production-down incident and normal remediation cannot restore service within the required incident window.

Break-glass is not a mechanism for bypassing normal review because remediation is inconvenient.

## Conditions

Break-glass may only be used when:

* the production service is materially unavailable or recovery is blocked;
* the normal deployment/review path cannot restore service within the incident response target;
* an authorised production operator declares the emergency.

Security gates must not be disabled globally.

## Procedure

1. Record the incident ID, affected service, failed security control, reason for emergency action, operator identity, timestamp, and intended temporary scope.

2. Deploy only the smallest known-good artifact required for recovery. The operator must record the exact image digest and deployment revision.

3. Restore the normal security gate as soon as the incident condition is removed.

## Audit trail

The event must leave evidence in:

* the incident/ticketing system;
* GitHub workflow and deployment history;
* the AWS CloudTrail record for the emergency IAM activity;
* Kubernetes audit/deployment records where available.

The incident record links these evidence sources.

## Post-incident review

Within one business day:

* confirm exactly which security control was bypassed;
* determine why the normal path was insufficient;
* rotate or revoke credentials if the emergency path exposed them;
* remediate the underlying production defect;
* decide whether the gate or waiver process requires a design change.

A break-glass action without a post-incident review is considered incomplete.
