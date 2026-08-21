#!/usr/bin/env bash
#
# Build Keycloak from source and install it into the local Maven repository.
#
# Keycloak tags patch releases that never get artifacts published to Maven
# Central or images pushed to quay.io (26.6.5 and 26.6.6, for example), so
# `libs/` cannot compile against them and the Dockerfile has no base image to
# start from. This script closes that gap: it builds the CockroachDB-patched
# fork at `p2-inc/keycloak` branch `<version>_crdb` and `mvn install`s the
# whole reactor into ~/.m2, which is exactly what the rest of the build
# expects to find.
#
# The build is architecture-independent (JVM-mode Quarkus), so the same
# artifacts work on x86 and arm laptops and for both linux/amd64 and
# linux/arm64 image builds.
#
# Usage:
#   scripts/build-keycloak.sh [VERSION] [options]
#
# VERSION defaults to <keycloak.version> in libs/pom.xml.
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# --- defaults (all overridable by env or flag) ------------------------------
KEYCLOAK_REPO=${KEYCLOAK_REPO:-https://github.com/p2-inc/keycloak.git}
KEYCLOAK_SRC=${KEYCLOAK_SRC:-$REPO_ROOT/.keycloak-build/src}
KEYCLOAK_OUT=${KEYCLOAK_OUT:-$REPO_ROOT/.keycloak-build/out}
MAVEN_REPO_LOCAL=${MAVEN_REPO_LOCAL:-$HOME/.m2/repository}
KEYCLOAK_MVN_ARGS=${KEYCLOAK_MVN_ARGS:-}
QUICK=${KEYCLOAK_QUICK:-0}
VERSION=${KEYCLOAK_VERSION:-}
BRANCH=${KEYCLOAK_BRANCH:-}
FORCE=${KEYCLOAK_FORCE:-0}

usage() {
    # Print the leading comment block (everything from line 2 up to the first
    # non-comment line) as the help text, so docs live in exactly one place.
    awk 'NR>1 && /^#/ { sub(/^#[[:space:]]?/, ""); print; next } NR>1 { exit }' \
        "${BASH_SOURCE[0]}"
    cat <<'USAGE_EOF'
Options:
  -b, --branch NAME   Branch to build (default: <VERSION>_crdb)
  -s, --src DIR       Source checkout dir (default: .keycloak-build/src)
  -o, --out DIR       Docker build context / cache dir (default: .keycloak-build/out)
  -r, --repo URL      Git remote (default: https://github.com/p2-inc/keycloak.git)
      --quick         Build only `quarkus/dist -am` — the server distribution
                      and its dependencies (49 of 136 modules). Produces
                      everything this image and libs/ need, verified against an
                      empty local repository. Note that it installs a subset of
                      org.keycloak (~73 jars vs ~177), so if you also want to
                      build another repo against this version locally, do a
                      full run instead.
  -f, --force         Rebuild even if this commit is already installed
  -h, --help          Show this help

Environment equivalents: KEYCLOAK_VERSION, KEYCLOAK_BRANCH, KEYCLOAK_SRC,
KEYCLOAK_OUT, KEYCLOAK_REPO, KEYCLOAK_FORCE, MAVEN_REPO_LOCAL,
KEYCLOAK_QUICK, KEYCLOAK_JAVA_HOME (pin the JDK; a 21 is found automatically),
KEYCLOAK_MVN_ARGS (extra mvn flags, e.g. -T1C).

Note: the server distribution embeds one platform-specific native jar
(com.aayushatharva.brotli4j.native-*), selected by OS-activated Maven profiles
in brotli4j's own pom and therefore not overridable from the command line. A
Linux/x86_64 build — which is what CI does — matches the published images; a
build on an arm Mac stages native-osx-aarch64 instead, leaving brotli
compression unavailable in locally built images. Nothing else in the
distribution differs by build host.
USAGE_EOF
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- argument parsing ------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -b|--branch) BRANCH=${2:-}; shift 2 ;;
        -s|--src)    KEYCLOAK_SRC=${2:-}; shift 2 ;;
        -o|--out)    KEYCLOAK_OUT=${2:-}; shift 2 ;;
        -r|--repo)   KEYCLOAK_REPO=${2:-}; shift 2 ;;
        --quick)     QUICK=1; shift ;;
        -f|--force)  FORCE=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          die "unknown option: $1 (try --help)" ;;
        *)
            [ -n "$VERSION" ] && die "unexpected argument: $1"
            VERSION=$1; shift ;;
    esac
done

# Single source of truth for the version: libs/pom.xml. Keeping it there means
# a Keycloak bump is one edit that the script, the image build and the Maven
# build all follow.
if [ -z "$VERSION" ]; then
    VERSION=$(sed -n 's|.*<keycloak\.version>\(.*\)</keycloak\.version>.*|\1|p' \
        "$REPO_ROOT/libs/pom.xml" | head -1)
    [ -n "$VERSION" ] || die "could not read <keycloak.version> from libs/pom.xml; pass VERSION explicitly"
    log "version not given, using <keycloak.version> from libs/pom.xml: $VERSION"
fi

case "$VERSION" in
    *[!0-9.a-zA-Z-]*|"") die "implausible version: '$VERSION'" ;;
esac

BRANCH=${BRANCH:-${VERSION}_crdb}
DIST_TARBALL="keycloak-${VERSION}.tar.gz"
STAMP="$KEYCLOAK_OUT/installed-${VERSION}.sha"
EXPORT_M2="$KEYCLOAK_OUT/m2/repository"
EXPORT_DIST="$KEYCLOAK_OUT/dist"

# --- toolchain checks ------------------------------------------------------
command -v git >/dev/null || die "git not found on PATH"
command -v java >/dev/null || die "java not found on PATH; Keycloak $VERSION needs JDK 21+"

# Keycloak 26.x is built on JDK 21, and the jars in the published images say
# `Build-Jdk-Spec: 21`. A newer JDK does build successfully but emits different
# bytecode, so actively look for a 21 rather than trusting JAVA_HOME — version
# managers (jenv, SDKMAN, asdf) normally point it at the newest install. Set
# KEYCLOAK_JAVA_HOME to override this and pin a specific JDK.
java_major_of() {
    [ -n "${1:-}" ] && [ -x "$1/bin/java" ] || return 1
    "$1/bin/java" -version 2>&1 \
        | sed -n 's/^[a-zA-Z()]* version "\([0-9]*\).*/\1/p' | head -1
}

if [ -n "${KEYCLOAK_JAVA_HOME:-}" ]; then
    export JAVA_HOME=$KEYCLOAK_JAVA_HOME
elif [ "$(java_major_of "${JAVA_HOME:-}" || true)" != "21" ]; then
    MACOS_JAVA_21=
    if [ -x /usr/libexec/java_home ]; then
        MACOS_JAVA_21=$(/usr/libexec/java_home -v 21 2>/dev/null || true)
    fi
    # JAVA_HOME_21_* are set by GitHub-hosted runners and actions/setup-java.
    for candidate in "${JAVA_HOME_21_X64:-}" "${JAVA_HOME_21_ARM64:-}" "$MACOS_JAVA_21"; do
        if [ "$(java_major_of "$candidate" || true)" = "21" ]; then
            log "using JDK 21 at $candidate"
            export JAVA_HOME=$candidate
            break
        fi
    done
fi

# Put JAVA_HOME on PATH so the check below reports the JDK Maven will use.
if [ -n "${JAVA_HOME:-}" ]; then
    export PATH="$JAVA_HOME/bin:$PATH"
fi

JAVA_MAJOR=$(java -version 2>&1 | sed -n 's/^[a-zA-Z()]* version "\([0-9]*\).*/\1/p' | head -1)
if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -lt 21 ]; then
    die "JDK 21+ required to build Keycloak $VERSION (found $JAVA_MAJOR)"
fi
if [ "$JAVA_MAJOR" != "21" ]; then
    warn "no JDK 21 found — building with JDK $JAVA_MAJOR, which produces"
    warn "different bytecode than the published Keycloak jars. Install a JDK 21"
    warn "or set KEYCLOAK_JAVA_HOME to one."
fi

# The js/ modules download their own node + pnpm via frontend-maven-plugin, so
# no host node install is needed, but the build is heap-hungry.
export MAVEN_OPTS=${MAVEN_OPTS:--Xmx4g}

# --- resolve the target commit --------------------------------------------
# Resolved up front so an already-installed build is a no-op without cloning.
log "resolving $BRANCH in $KEYCLOAK_REPO"
REMOTE_SHA=$(git ls-remote --heads "$KEYCLOAK_REPO" "refs/heads/$BRANCH" 2>/dev/null | cut -f1 || true)

if [ -z "$REMOTE_SHA" ]; then
    if [ -f "$STAMP" ]; then
        # Offline or transient failure, but we have a previous build to trust.
        warn "cannot reach $KEYCLOAK_REPO; falling back to the installed build"
        REMOTE_SHA=$(cat "$STAMP")
    else
        printf '\033[1;31merror:\033[0m branch %s not found in %s\n' "$BRANCH" "$KEYCLOAK_REPO" >&2
        printf 'available *_crdb branches:\n' >&2
        git ls-remote --heads "$KEYCLOAK_REPO" '*_crdb' 2>/dev/null \
            | sed 's|.*refs/heads/|  |' | tail -15 >&2 || true
        exit 1
    fi
fi

# --- skip if this exact commit is already in the local repository ----------
jars_installed() {
    local a
    for a in keycloak-common keycloak-core keycloak-server-spi keycloak-server-spi-private; do
        [ -f "$MAVEN_REPO_LOCAL/org/keycloak/$a/$VERSION/$a-$VERSION.jar" ] || return 1
    done
    return 0
}

# The export under $KEYCLOAK_OUT is what `docker build --build-context` reads,
# and it is the only thing CI needs to cache: the dist tarball the image is
# built from, plus the org.keycloak artifacts libs/ compiles against.
export_present() {
    [ -f "$EXPORT_DIST/$DIST_TARBALL" ] || return 1
    [ -f "$EXPORT_M2/org/keycloak/keycloak-common/$VERSION/keycloak-common-$VERSION.jar" ] || return 1
    return 0
}

# Refresh the export from the local repo / source tree. Cheap no-op once it is
# populated, so it is safe to call on the already-built path too.
ensure_export() {
    export_present && return 0
    log "staging build context in $KEYCLOAK_OUT"
    mkdir -p "$EXPORT_DIST" "$EXPORT_M2/org/keycloak"

    if [ -f "$KEYCLOAK_SRC/quarkus/dist/target/$DIST_TARBALL" ]; then
        cp "$KEYCLOAK_SRC/quarkus/dist/target/$DIST_TARBALL" "$EXPORT_DIST/"
    elif [ ! -f "$EXPORT_DIST/$DIST_TARBALL" ]; then
        warn "no dist tarball at quarkus/dist/target/$DIST_TARBALL (image build will need it)"
    fi

    # The fork carries the CockroachDB JDBC driver that the runtime image needs
    # in providers/; it is not a Maven artifact, so it travels with the dist.
    cp "$KEYCLOAK_SRC"/quarkus/container/cockroachdb-jdbc-driver-*.jar "$EXPORT_DIST/" 2>/dev/null \
        || warn "no cockroachdb-jdbc-driver jar in quarkus/container/"

    # Only org/keycloak, and only this version. Copying the whole org/keycloak
    # tree pulls in every Keycloak ever built on this machine plus the dist
    # archives Maven installs alongside the jars — 18GB on a developer laptop,
    # all of it useless to the image build.
    if [ -d "$MAVEN_REPO_LOCAL/org/keycloak" ]; then
        find "$MAVEN_REPO_LOCAL/org/keycloak" -type d -name "$VERSION" -print \
        | while read -r versiondir; do
            parent=$(dirname "${versiondir#"$MAVEN_REPO_LOCAL"/}")
            mkdir -p "$EXPORT_M2/$parent"
            cp -R "$versiondir" "$EXPORT_M2/$parent/"
        done
        # The dist archives are what `dist/` carries; libs/ only ever resolves
        # jars and poms from here.
        find "$EXPORT_M2/org/keycloak" -type f \( -name '*.tar.gz' -o -name '*.zip' \) -delete
    fi
}

# Inverse of ensure_export: seed the local repo from a restored cache so a CI
# run that got a cache hit can skip the build entirely.
hydrate_from_export() {
    log "hydrating $MAVEN_REPO_LOCAL from the cached export"
    mkdir -p "$MAVEN_REPO_LOCAL/org/keycloak"
    cp -R "$EXPORT_M2/org/keycloak/." "$MAVEN_REPO_LOCAL/org/keycloak/"
}

if [ "$FORCE" != "1" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$REMOTE_SHA" ]; then
    if jars_installed; then
        log "Keycloak $VERSION ($BRANCH @ ${REMOTE_SHA:0:8}) already installed in $MAVEN_REPO_LOCAL"
        ensure_export
        log "nothing to do; re-run with --force to rebuild"
        exit 0
    elif export_present; then
        hydrate_from_export
        jars_installed || die "export at $KEYCLOAK_OUT is incomplete; re-run with --force"
        log "Keycloak $VERSION ($BRANCH @ ${REMOTE_SHA:0:8}) restored from the export; no build needed"
        exit 0
    fi
fi

# --- check out the source -------------------------------------------------
mkdir -p "$KEYCLOAK_OUT"

if [ ! -d "$KEYCLOAK_SRC/.git" ]; then
    log "cloning $BRANCH into $KEYCLOAK_SRC"
    mkdir -p "$(dirname "$KEYCLOAK_SRC")"
    git clone --depth 1 --branch "$BRANCH" --single-branch "$KEYCLOAK_REPO" "$KEYCLOAK_SRC"
else
    # An existing checkout may be a developer's working copy (KEYCLOAK_SRC can
    # point at one). Never discard uncommitted work silently.
    if [ -n "$(git -C "$KEYCLOAK_SRC" status --porcelain --untracked-files=no)" ]; then
        die "$KEYCLOAK_SRC has uncommitted changes; commit/stash them, or point --src elsewhere"
    fi
    log "fetching $BRANCH into existing checkout $KEYCLOAK_SRC"
    git -C "$KEYCLOAK_SRC" fetch --depth 1 "$KEYCLOAK_REPO" "refs/heads/$BRANCH"
    git -C "$KEYCLOAK_SRC" checkout --detach FETCH_HEAD
fi

SRC_SHA=$(git -C "$KEYCLOAK_SRC" rev-parse HEAD)
log "building Keycloak $VERSION from $BRANCH @ ${SRC_SHA:0:8}"

# --- build ----------------------------------------------------------------
# `install` (not `package`) is the point of the exercise: it puts the
# org.keycloak:* artifacts into the local repository so libs/ can compile
# against a version that was never published to Central.
QUICK_ARGS=
if [ "$QUICK" = "1" ]; then
    QUICK_ARGS="-pl quarkus/dist -am"
    log "--quick: building quarkus/dist and its dependencies only"
fi

(
    cd "$KEYCLOAK_SRC"
    # shellcheck disable=SC2086
    ./mvnw -B -ntp clean install -DskipTests \
        -Dmaven.repo.local="$MAVEN_REPO_LOCAL" \
        $QUICK_ARGS $KEYCLOAK_MVN_ARGS
)

jars_installed || die "build finished but org.keycloak:$VERSION jars are missing from $MAVEN_REPO_LOCAL"

# --- stage the docker build context ---------------------------------------
rm -rf "$EXPORT_DIST" "$EXPORT_M2/org/keycloak"
ensure_export

printf '%s' "$SRC_SHA" > "$STAMP"

log "done"
printf '  version:      %s\n' "$VERSION"
printf '  branch:       %s @ %s\n' "$BRANCH" "${SRC_SHA:0:8}"
printf '  maven repo:   %s\n' "$MAVEN_REPO_LOCAL"
printf '  build context: %s\n' "$KEYCLOAK_OUT"
printf '\nbuild the image with:\n  docker buildx build --build-context keycloak=%s .\n' \
    "$(cd "$KEYCLOAK_OUT" && pwd)"
