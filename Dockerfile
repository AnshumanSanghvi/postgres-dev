# syntax=docker/dockerfile:1.7
# ============================================================================
# Postgres Dev Environment — base image
#   Step-wise build: each RUN is a logical unit so layer caching is effective.
#   Multi-arch: built for the host's architecture automatically (amd64/arm64).
#
# Layer order (least → most likely to change):
#   1. dnf bootstrap                  (essentially never changes)
#   2. PGDG repo                      (changes only on PG major upgrade)
#   3. PostgreSQL core packages       (changes on minor upgrades)
#   4. (later slices) OS utilities    (occasional)
#   5. (later slices) Extensions      (changes most often)
#   6. (later slices) Python/CLI      (changes most often)
#   7. directory setup + entrypoint   (changes rarely, but cheap to rebuild)
# ============================================================================
FROM oraclelinux:9-slim

ARG PG_MAJOR=17
ARG TARGETARCH

ENV PG_MAJOR=${PG_MAJOR} \
    PGDATA=/var/lib/pgsql/data/pgdata \
    PATH=/usr/pgsql-17/bin:${PATH} \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LESS=-iMRSx4

# --- Step 1: Bootstrap dnf ---------------------------------------------------
# OL9-slim ships microdnf only. dnf gives us richer dependency resolution and
# more reliable URL/local-file installs.
RUN microdnf -y install dnf && microdnf clean all

# --- Step 2: PGDG repository -------------------------------------------------
# PGDG ships per-arch repo RPMs; the .rpm is noarch but lives under
# arch-specific paths. Fetch with curl (already in OL9-slim) for reliability.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) ARCH=x86_64 ;; \
      arm64) ARCH=aarch64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 3 --retry-delay 5 -o /tmp/pgdg.rpm \
      "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"; \
    dnf -y install /tmp/pgdg.rpm; \
    rm -f /tmp/pgdg.rpm; \
    dnf -qy module disable postgresql; \
    dnf clean all

# --- Step 3: PostgreSQL 17 core ---------------------------------------------
RUN dnf -y install \
      "postgresql${PG_MAJOR}-server" \
      "postgresql${PG_MAJOR}-contrib" \
      glibc-langpack-en \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# --- Step 4: OS terminal utilities (in-container debugging) -----------------
RUN dnf -y install \
      procps-ng \
      less \
      vim-minimal \
      iputils \
      bind-utils \
      lsof \
      jq \
      tar \
      gzip \
      findutils \
      strace \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# --- Step 7: Filesystem + entrypoint ----------------------------------------
# PGDATA is a *subdirectory* of the volume mount so .gitkeep / lost+found etc.
# at the mount root don't trip initdb's "directory not empty" check.
RUN mkdir -p "$PGDATA" /var/log/postgresql \
    && chown -R postgres:postgres /var/lib/pgsql /var/log/postgresql \
    && chmod 700 "$PGDATA"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Entrypoint starts as root so it can fix bind-mount ownership,
# then drops to the postgres user via runuser before exec'ing postgres.
EXPOSE 5499
VOLUME ["/var/lib/pgsql/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Custom config files are expected at /etc/postgresql (volume-mounted).
# Subsequent slices can override CMD without modifying the image.
CMD ["postgres", "-D", "/var/lib/pgsql/data/pgdata", \
     "-c", "config_file=/etc/postgresql/postgresql.conf", \
     "-c", "hba_file=/etc/postgresql/pg_hba.conf"]
