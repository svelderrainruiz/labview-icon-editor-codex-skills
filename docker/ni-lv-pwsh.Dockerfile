FROM nationalinstruments/labview:2026q1-linux

ENV DEBIAN_FRONTEND=noninteractive
ARG PESTER_VERSION=5.7.1
ARG VIPM_CLI_URL=
ARG VIPM_CLI_SHA256=
ARG VIPM_CLI_ARCHIVE_TYPE=tar.gz

ENV VIPM_CLI_URL=${VIPM_CLI_URL}
ENV VIPM_CLI_SHA256=${VIPM_CLI_SHA256}
ENV VIPM_CLI_ARCHIVE_TYPE=${VIPM_CLI_ARCHIVE_TYPE}

RUN apt-get update \
  && apt-get install -y wget apt-transport-https software-properties-common ca-certificates tar gzip unzip xz-utils \
  && wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb \
  && dpkg -i /tmp/packages-microsoft-prod.deb \
  && apt-get update \
  && apt-get install -y powershell \
  && pwsh -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name Pester -Scope AllUsers -Force -SkipPublisherCheck -RequiredVersion ${PESTER_VERSION}" \
  && if [ -n "${VIPM_CLI_URL}" ] || [ -n "${VIPM_CLI_SHA256}" ]; then \
       if [ -z "${VIPM_CLI_URL}" ] || [ -z "${VIPM_CLI_SHA256}" ]; then \
         echo "Both VIPM_CLI_URL and VIPM_CLI_SHA256 must be provided together." >&2; \
         exit 1; \
       fi; \
       wget -q "${VIPM_CLI_URL}" -O /tmp/vipm-cli.pkg; \
       echo "${VIPM_CLI_SHA256}  /tmp/vipm-cli.pkg" | sha256sum -c -; \
       mkdir -p /opt/vipm-cli; \
       case "${VIPM_CLI_ARCHIVE_TYPE}" in \
         tar.gz|tgz) tar -xzf /tmp/vipm-cli.pkg -C /opt/vipm-cli ;; \
         zip) unzip -q /tmp/vipm-cli.pkg -d /opt/vipm-cli ;; \
         *) echo "Unsupported VIPM_CLI_ARCHIVE_TYPE '${VIPM_CLI_ARCHIVE_TYPE}'. Use tar.gz, tgz, or zip." >&2; exit 1 ;; \
       esac; \
       vipm_candidate=""; \
       if [ -x /opt/vipm-cli/vipm ]; then vipm_candidate=/opt/vipm-cli/vipm; fi; \
       if [ -z "${vipm_candidate}" ] && [ -x /opt/vipm-cli/bin/vipm ]; then vipm_candidate=/opt/vipm-cli/bin/vipm; fi; \
       if [ -z "${vipm_candidate}" ]; then \
         vipm_candidate=$(find /opt/vipm-cli -type f -name vipm -perm -111 | head -n 1 || true); \
       fi; \
       if [ -z "${vipm_candidate}" ]; then \
         echo "No executable 'vipm' binary found in downloaded archive." >&2; \
         exit 1; \
       fi; \
       install -m 0755 "${vipm_candidate}" /usr/local/bin/vipm; \
       /usr/local/bin/vipm --version >/dev/null 2>&1 || /usr/local/bin/vipm version >/dev/null 2>&1 || true; \
       rm -f /tmp/vipm-cli.pkg; \
     fi \
  && rm -f /tmp/packages-microsoft-prod.deb \
  && rm -rf /opt/vipm-cli \
  && rm -rf /var/lib/apt/lists/*