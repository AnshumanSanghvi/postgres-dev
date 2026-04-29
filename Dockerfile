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

# --- Step 5: PostgreSQL extensions requiring shared_preload_libraries -------
# These all hook into postgres startup, so they're loaded before the lighter
# extensions in step 6. Versions pinned for reproducibility.
RUN dnf -y install \
      "pg_cron_${PG_MAJOR}-1.6.7-1PGDG.rhel9" \
      "pgaudit_${PG_MAJOR}-17.1-1PGDG.rhel9" \
      "pg_partman_${PG_MAJOR}-5.4.3-1PGDG.rhel9.7" \
      "pldebugger_${PG_MAJOR}-1.8-1PGDG.rhel9" \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# --- Step 6: Lighter extensions (no shared_preload_libraries impact) --------
# pg_buffercache, pg_prewarm, tablefunc are already in postgresql17-contrib (S1).
RUN dnf -y install \
      "postgresql${PG_MAJOR}-plpython3-17.9-1PGDG.rhel9.7" \
      "pg_squeeze_${PG_MAJOR}-1.9.1-1PGDG.rhel9" \
      "hypopg_${PG_MAJOR}-1.4.1-2PGDG.rhel9" \
      "pg_hint_plan_${PG_MAJOR}-1.7.1-1PGDG.rhel9" \
      "wal2json_${PG_MAJOR}-2.6-2PGDG.rhel9" \
      "pgtap_${PG_MAJOR}-1.3.4-1PGDG.rhel9" \
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

# --- Step 6b: pspg (binary CLI, PGDG package) -------------------------------
RUN dnf -y install pspg \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# --- Step 6c: Python CLI tools (pgcli, pg_activity) via pip -----------------
# OL9-slim ships python3.9. Pin tool versions for reproducibility.
RUN dnf -y install python3 python3-pip \
    && pip3 install --no-cache-dir --no-compile \
         "pgcli==4.1.0" \
         "pg_activity==3.6.1" \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum /root/.cache

# --- Step 6d: pgbadger (perl, needs EPEL for perl-Text-CSV_XS) --------------
# Two separate dnf transactions: the first enables Oracle EPEL, the second
# refreshes cache and installs (single transaction misses newly-enabled repo).
RUN dnf -y install oracle-epel-release-el9 \
    && dnf makecache \
    && dnf -y install pgbadger \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# --- Step 6e: sqitch (App::Sqitch via cpanm) --------------------------------
# Heavy step (~5 min on arm64 — cpanm builds many CPAN modules from source).
# Build deps (gcc, make) are kept in the image: removing them with `dnf -y
# remove` triggers OL9's default `clean_requirements_on_remove=True` which
# transitively prunes other packages (e.g. pgbadger's perl chain). Image is
# ~150 MB heavier with build tools; acceptable for a dev environment.
# Smoke-test all five CLI tools at the end so silent failures fail the build.
RUN dnf -y install \
      perl perl-App-cpanminus perl-DBI perl-DBD-Pg \
      gcc make \
    && cpanm --quiet App::Sqitch \
    && pgcli --version > /dev/null \
    && pg_activity --version > /dev/null \
    && pgbadger --version > /dev/null \
    && pspg --version > /dev/null \
    && sqitch --version > /dev/null \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum /root/.cpanm

# Set pspg as default pager for psql output (sane scrolling for tabular data).
ENV PAGER=pspg

# --- Step 7: Filesystem + entrypoint ----------------------------------------
# PGDATA is a *subdirectory* of the volume mount so .gitkeep / lost+found etc.
# at the mount root don't trip initdb's "directory not empty" check.
RUN mkdir -p "$PGDATA" /var/log/postgresql \
    && chown -R postgres:postgres /var/lib/pgsql /var/log/postgresql \
    && chmod 700 "$PGDATA"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# .psqlrc — heavily commented; see config/psqlrc for the source.
# Placed at /etc/psqlrc and pointed to via PSQLRC env so every psql session
# (regardless of which user `docker exec` runs as) reads the same defaults.
COPY --chmod=644 config/psqlrc /etc/psqlrc
ENV PSQLRC=/etc/psqlrc

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
