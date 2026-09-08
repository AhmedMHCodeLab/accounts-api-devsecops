# syntax=docker/dockerfile:1

# Pin the base image by digest so the build input is immutable.
# The digest below must be refreshed deliberately when the Python base is updated.
FROM python:3.12-slim@sha256:78387bc3881b8273120a12ebe6c1ab22b018ccc2c9adf565ae1ac9b536e184ea AS runtime
ARG VERSION=0.1.0

LABEL \
    org.opencontainers.image.title="accounts-api" \
    org.opencontainers.image.description="Minimal accounts-api security assessment workload" \
    org.opencontainers.image.version="${VERSION}" \
    org.opencontainers.image.source="https://github.com/REPLACE_WITH_REPO" \
    org.opencontainers.image.vendor="Mal Assessment"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create an unprivileged runtime identity.
RUN useradd \
    --create-home \
    --uid 10001 \
    --shell /usr/sbin/nologin \
    appuser

COPY requirements.txt .

RUN pip install --no-cache-dir --requirement requirements.txt

COPY --chown=10001:10001 main.py .

USER 10001:10001

EXPOSE 8080

# Docker-level health signal. Kubernetes will also define its own probes.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)"

STOPSIGNAL SIGTERM

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]