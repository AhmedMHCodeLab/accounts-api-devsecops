# Secrets Rotation and Emergency Procedure

## Source of truth

Application database credentials are stored in AWS Secrets Manager.

The `accounts-api` workload receives the credential through AWS Secrets and Configuration Provider (ASCP), the Secrets Store CSI Driver, and EKS Pod Identity.

The credential is mounted as a read-only file. It is not stored in Git, Terraform source, or a committed Kubernetes `Secret`.

## Scheduled rotation

The application database credential is rotated every 30 days.

The application uses a dedicated database user with only the permissions required by `accounts-api`. The RDS master credential is not exposed to the application.

The 30-day interval is a risk-based operating choice. AWS Secrets Manager supports automatic rotation, including shorter schedules where required.

## Rotation flow

1. Secrets Manager creates the new secret version.
2. The database credential is changed.
3. The Secrets Store CSI / ASCP integration refreshes the mounted value.
4. The application refreshes its database connection pool and begins using the new credential.
5. The previous credential is confirmed invalid.

The application must not cache credentials indefinitely.

## Emergency rotation

Emergency rotation is triggered when a credential may have been exposed, including:

* suspected `accounts-api` compromise
* credential exposure in logs
* compromised CI/CD
* suspected unauthorised Secrets Manager access
* accidental publication of a credential

**Target:** 15 minutes from incident declaration to the new credential being active in `accounts-api`.

Procedure:

1. Record the incident ID and isolate the affected workload or credential path.
2. Rotate the database credential immediately in Secrets Manager and update the database.
3. Refresh/restart the affected application connections so the new credential is active.
4. Verify the previous credential no longer authenticates.
5. Review CloudTrail, Kubernetes audit/deployment evidence, Secrets Manager activity and application telemetry for use of the old credential.

## Availability

Rotation should not require a full application outage.

The application should use a dedicated database user and support rolling connection refresh so credential rotation can occur without unnecessarily taking the service offline.

## Evidence

Rotation activity should be attributable through:

* Secrets Manager rotation history
* AWS CloudTrail
* Kubernetes deployment/workload history
* application connection/authentication telemetry
* incident record

The incident is not closed until the previous credential has been confirmed invalid.

## Limitation

The 15-minute value is an operational target, not a guaranteed AWS execution time. The target must be validated during production rollout with the actual RDS, Secrets Manager, CSI/ASCP and application connection-refresh behaviour.
