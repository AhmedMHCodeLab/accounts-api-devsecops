# Accounts API Log Redaction Specification

## Objective

`accounts-api` handles customer financial information. Logging therefore follows data minimisation: operational telemetry is retained, but customer data and credentials are excluded from application logs.

## Prohibited data

The following must never be emitted to application logs:

* customer name
* email address
* phone number
* IBAN
* account balance
* card data, including card-related fields
* database credentials
* Secrets Manager values
* API keys
* access tokens
* `Authorization` headers
* request/response bodies containing customer data

## Redaction layer

Primary protection occurs in the application logging layer, before log events leave the process.

The application uses an allow-list of operational fields such as:

* timestamp
* request ID
* route
* HTTP method
* response status
* request latency
* service name
* error class

Request and response bodies are not logged.

Production debug configuration must not provide a path that bypasses these restrictions.

## Infrastructure telemetry

Infrastructure components such as CloudFront, ALB, Kubernetes and AWS logging services may still retain operational metadata.

Examples include:

* source IP
* request path
* timestamp
* status code
* timing
* request/correlation ID

Sensitive information must therefore also be excluded from URLs and query parameters wherever possible.

## What redaction does not prevent

Redaction is data minimisation, not proof of zero sensitive-data exposure.

An observer may still infer:

* that a customer request occurred
* when it occurred
* which endpoint was accessed
* whether it succeeded
* request timing
* source/network metadata
* correlation between related requests

Infrastructure telemetry may therefore remain sensitive even when application payloads are removed.

## Incident response

If customer data or credentials are discovered in logs:

1. Stop further emission at the application layer.
2. Identify affected log streams, accounts and retention periods.
3. Restrict access to the affected telemetry and preserve the evidence required for investigation.
4. Assess whether log deletion, retention-policy action, credential rotation or incident/breach notification is required.

## Change control

When new request or response fields are introduced, the logging configuration must be reviewed to ensure the field is not automatically emitted.

Developers must not add ad-hoc request/response-body logging in production for debugging.

## Residual risk

A compromised process can still attempt to write arbitrary data directly to stdout/stderr if application-level controls are bypassed. Runtime monitoring, restricted application permissions and central log-access controls are therefore compensating controls rather than treating redaction as a complete containment mechanism.
