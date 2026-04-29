# syntax=docker/dockerfile:1.7
# ============================================================================
# Postgres Dev Environment — base image
#   Slice 1: bare PostgreSQL 17 on OracleLinux 9 Slim, default config.
#   Multi-arch: built for the host's architecture automatically.
# ============================================================================
FROM oraclelinux:9-slim

ARG PG_MAJOR=17
ARG TARGETARCH

ENV PG_MAJOR=${PG_MAJOR} \
    PGDATA=/var/lib/pgsql/data \
    PATH=/usr/pgsql-17/bin:${PATH} \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install PGDG repo and PostgreSQL 17 server + contrib.
# PGDG ships separate repo RPMs per arch; the .rpm itself is noarch but lives
# under arch-specific directories. We fetch with curl (more reliable than
# microdnf URL install) then install locally. Use dnf (richer dependency
# resolution) installed alongside microdnf in the slim base.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) ARCH=x86_64 ;; \
      arm64) ARCH=aarch64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    microdnf -y install dnf; \
    curl -fsSL --retry 3 --retry-delay 5 -o /tmp/pgdg.rpm \
      "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"; \
    dnf -y install /tmp/pgdg.rpm; \
    rm -f /tmp/pgdg.rpm; \
    dnf -qy module disable postgresql; \
    dnf -y install \
      "postgresql${PG_MAJOR}-server" \
      "postgresql${PG_MAJOR}-contrib" \
      glibc-langpack-en; \
    dnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum

# postgres OS user is created by the postgresql-server package.
# Prepare data and log directories with correct ownership.
RUN mkdir -p "$PGDATA" /var/log/postgresql; \
    chown -R postgres:postgres "$PGDATA" /var/log/postgresql; \
    chmod 700 "$PGDATA"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER postgres
EXPOSE 5432
VOLUME ["/var/lib/pgsql/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["postgres", "-D", "/var/lib/pgsql/data"]
