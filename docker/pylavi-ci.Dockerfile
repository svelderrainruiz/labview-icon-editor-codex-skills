FROM python:3.11-slim

ARG PYLAVI_URL
ARG PYLAVI_SHA256

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN set -eux; \
    if [ -z "${PYLAVI_URL}" ] || [ -z "${PYLAVI_SHA256}" ]; then \
      echo "Both PYLAVI_URL and PYLAVI_SHA256 are required." >&2; \
      exit 2; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL "${PYLAVI_URL}" -o /tmp/pylavi.tar.gz; \
    echo "${PYLAVI_SHA256}  /tmp/pylavi.tar.gz" | sha256sum -c -; \
    python -m pip install --no-cache-dir --upgrade pip; \
    python -m pip install --no-cache-dir /tmp/pylavi.tar.gz; \
    command -v vi_validate >/dev/null 2>&1; \
    rm -f /tmp/pylavi.tar.gz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
