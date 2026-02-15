ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:8.0
FROM ${DOTNET_SDK_IMAGE}

ARG PYLAVI_URL
ARG PYLAVI_SHA256

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

RUN set -eux; \
    if [ -z "${PYLAVI_URL}" ] || [ -z "${PYLAVI_SHA256}" ]; then \
      echo "Both PYLAVI_URL and PYLAVI_SHA256 are required." >&2; \
      exit 2; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl git python3 python3-venv python3-pip; \
    curl -fsSL "${PYLAVI_URL}" -o /tmp/pylavi.tar.gz; \
    echo "${PYLAVI_SHA256}  /tmp/pylavi.tar.gz" | sha256sum -c -; \
    python3 -m venv /opt/pylavi-venv; \
    /opt/pylavi-venv/bin/pip install --no-cache-dir --upgrade pip; \
    /opt/pylavi-venv/bin/pip install --no-cache-dir /tmp/pylavi.tar.gz; \
    ln -s /opt/pylavi-venv/bin/vi_validate /usr/local/bin/vi_validate; \
    command -v vi_validate >/dev/null 2>&1; \
    rm -f /tmp/pylavi.tar.gz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
