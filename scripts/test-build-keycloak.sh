#!/usr/bin/env bash
#
# Tests for scripts/build-keycloak.sh.
#
# A real run of that script clones Keycloak and spends minutes in Maven, which
# is far too slow to test against. Instead each case runs the real script —
# unmodified, from a copy placed in a synthetic repo root — against a fake
# upstream git repository whose `mvnw` is a stub that fabricates the artifacts
# a real build would install. Every code path the script owns (branch
# resolution, cloning, fetching, the build invocation, staging the docker build
# context, the stamp, hydrating from a cache, the JDK search, error handling)
# therefore executes for real, in seconds, touching nothing outside a temp dir.
#
# Usage: scripts/test-build-keycloak.sh [-v]     (-v echoes failing output)
#
# Exits non-zero if any case fails.
#
set -uo pipefail

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

SUITE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_UNDER_TEST="$SUITE_DIR/build-keycloak.sh"
[ -f "$SCRIPT_UNDER_TEST" ] || { echo "cannot find build-keycloak.sh next to this suite" >&2; exit 1; }

TESTROOT=$(mktemp -d "${TMPDIR:-/tmp}/kcbuild-tests.XXXXXX")
trap 'rm -rf "$TESTROOT"' EXIT INT TERM

PASSED=0
FAILED=0
FAILED_CASES=

red()   { printf '\033[1;31m%s\033[0m' "$1"; }
green() { printf '\033[1;32m%s\033[0m' "$1"; }

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A stub Maven wrapper. Records how it was called (so tests can assert on the
# flags the script passes, and on how many times it ran) and creates exactly
# the outputs the script looks for afterwards: the four `provided`-scope jars
# it checks for, a couple of extra artifacts, an installed dist archive (which
# the export must drop), and the server distribution tarball.
write_fake_mvnw() {
    cat > "$1" <<'MVNW'
#!/bin/sh
set -e
version=$(cat "$(dirname "$0")/VERSION")
repo=
for arg in "$@"; do
    case "$arg" in -Dmaven.repo.local=*) repo=${arg#-Dmaven.repo.local=} ;; esac
done
[ -n "${MVNW_LOG:-}" ] && echo "JAVA_HOME=${JAVA_HOME:-} ARGS=$*" >> "$MVNW_LOG"
[ -n "$repo" ] || { echo "fake mvnw: no -Dmaven.repo.local" >&2; exit 1; }

for a in keycloak-common keycloak-core keycloak-server-spi keycloak-server-spi-private keycloak-services; do
    mkdir -p "$repo/org/keycloak/$a/$version"
    echo "fake $a $version" > "$repo/org/keycloak/$a/$version/$a-$version.jar"
    echo "<project/>"       > "$repo/org/keycloak/$a/$version/$a-$version.pom"
done
# Maven installs the distribution archives next to the jars; the export is
# expected to strip them.
mkdir -p "$repo/org/keycloak/keycloak-quarkus-dist/$version"
echo "archive" > "$repo/org/keycloak/keycloak-quarkus-dist/$version/keycloak-quarkus-dist-$version.tar.gz"
echo "archive" > "$repo/org/keycloak/keycloak-quarkus-dist/$version/keycloak-quarkus-dist-$version.zip"

mkdir -p quarkus/dist/target
echo "fake dist $version" > "quarkus/dist/target/keycloak-$version.tar.gz"
MVNW
    chmod +x "$1"
}

# The fake upstream: real git repo, branches named like the fork's, each
# carrying its own VERSION so the stub build produces matching artifacts.
FAKE_REMOTE="$TESTROOT/fake-keycloak"
build_fake_remote() {
    mkdir -p "$FAKE_REMOTE"
    git -C "$FAKE_REMOTE" init -q
    git -C "$FAKE_REMOTE" symbolic-ref HEAD refs/heads/main
    mkdir -p "$FAKE_REMOTE/quarkus/container"
    write_fake_mvnw "$FAKE_REMOTE/mvnw"
    echo "fake crdb driver" > "$FAKE_REMOTE/quarkus/container/cockroachdb-jdbc-driver-1.2.1.jar"
    echo "0.0.0" > "$FAKE_REMOTE/VERSION"
    _commit_all "initial"
    for spec in "1.2.3_crdb:1.2.3" "4.5.6_crdb:4.5.6" "custom-branch:7.8.9"; do
        branch=${spec%%:*}; version=${spec##*:}
        git -C "$FAKE_REMOTE" checkout -q -b "$branch" main
        echo "$version" > "$FAKE_REMOTE/VERSION"
        _commit_all "version $version"
    done
    git -C "$FAKE_REMOTE" checkout -q main
}

_commit_all() {
    git -C "$FAKE_REMOTE" add -A
    git -C "$FAKE_REMOTE" \
        -c user.email=test@example.com -c user.name=test \
        commit -q -m "$1"
}

remote_sha() { git -C "$FAKE_REMOTE" rev-parse "$1"; }

# A JDK whose `java -version` reports whatever major we want, so the JDK search
# can be tested without installing anything.
make_fake_jdk() {
    dir=$1; version=$2
    mkdir -p "$dir/bin"
    cat > "$dir/bin/java" <<JAVA
#!/bin/sh
echo "openjdk version \"$version\" 2026-01-01" >&2
echo "OpenJDK Runtime Environment (build $version)" >&2
JAVA
    chmod +x "$dir/bin/java"
}

# ---------------------------------------------------------------------------
# Case scaffolding
# ---------------------------------------------------------------------------

CASE_N=0
new_case() {
    CASE_NAME=$1
    CASE_N=$((CASE_N + 1))
    CASE_DIR="$TESTROOT/case-$CASE_N"
    # Synthetic repo root: a copy of the script plus the libs/pom.xml it reads
    # the default version out of.
    REPO="$CASE_DIR/repo"
    mkdir -p "$REPO/scripts" "$REPO/libs"
    cp "$SCRIPT_UNDER_TEST" "$REPO/scripts/build-keycloak.sh"
    printf '<project>\n  <properties>\n    <keycloak.version>%s</keycloak.version>\n  </properties>\n</project>\n' \
        "${POM_VERSION:-1.2.3}" > "$REPO/libs/pom.xml"
    M2="$CASE_DIR/m2"
    SRC="$CASE_DIR/src"
    OUT="$CASE_DIR/out"
    MVNW_LOG="$CASE_DIR/mvnw.log"
    : > "$MVNW_LOG"
}

# Runs the script under test with everything pointed at this case's temp dirs.
# JAVA_HOME* are scrubbed so a developer's shell (jenv and friends) cannot
# influence the result, and the JDK is a fake reporting 21 unless overridden.
run_build() {
    env -u JAVA_HOME -u JAVA_HOME_21_X64 -u JAVA_HOME_21_ARM64 \
        -u KEYCLOAK_VERSION -u KEYCLOAK_BRANCH -u KEYCLOAK_FORCE -u KEYCLOAK_QUICK \
        -u KEYCLOAK_MVN_ARGS -u MAVEN_OPTS \
        PATH="$FAKEBIN:$PATH" \
        KEYCLOAK_REPO="file://$FAKE_REMOTE" \
        KEYCLOAK_SRC="$SRC" \
        KEYCLOAK_OUT="$OUT" \
        MAVEN_REPO_LOCAL="$M2" \
        KEYCLOAK_JAVA_HOME="${TEST_JAVA_HOME:-$JDK21}" \
        MVNW_LOG="$MVNW_LOG" \
        ${TEST_ENV:+$TEST_ENV} \
        bash "$REPO/scripts/build-keycloak.sh" "$@" \
        > "$CASE_DIR/stdout" 2> "$CASE_DIR/stderr"
    STATUS=$?
    OUTPUT=$(cat "$CASE_DIR/stdout" "$CASE_DIR/stderr" 2>/dev/null)
    return $STATUS
}

mvnw_runs() { count=$(grep -c 'ARGS=' "$MVNW_LOG" 2>/dev/null); echo "${count:-0}"; }

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

FAILURES_THIS_CASE=
check() {  # check <description> <condition-result> — call as: check "msg" $?
    if [ "$2" -ne 0 ]; then
        FAILURES_THIS_CASE="$FAILURES_THIS_CASE
    - $1"
    fi
}
expect_status()   { [ "$STATUS" = "$1" ]; check "expected exit $1, got $STATUS" $?; }
expect_output()   { grep -qF -- "$1" <<<"$OUTPUT"; check "expected output to contain: $1" $?; }
expect_no_output(){ ! grep -qF -- "$1" <<<"$OUTPUT"; check "expected output NOT to contain: $1" $?; }
expect_file()     { [ -f "$1" ]; check "expected file: ${1#$CASE_DIR/}" $?; }
expect_no_file()  { [ ! -f "$1" ]; check "expected no file: ${1#$CASE_DIR/}" $?; }
expect_builds()   { [ "$(mvnw_runs)" = "$1" ]; check "expected $1 maven run(s), got $(mvnw_runs)" $?; }
expect_eq()       { [ "$2" = "$3" ]; check "$1: expected '$3', got '$2'" $?; }
expect_file_or_dir(){ [ -e "$1" ]; check "expected to exist: ${1#$CASE_DIR/}" $?; }

end_case() {
    if [ -z "$FAILURES_THIS_CASE" ]; then
        PASSED=$((PASSED + 1))
        printf '  %s %s\n' "$(green ok)" "$CASE_NAME"
    else
        FAILED=$((FAILED + 1))
        FAILED_CASES="$FAILED_CASES $CASE_NAME"
        printf '  %s %s%s\n' "$(red FAIL)" "$CASE_NAME" "$FAILURES_THIS_CASE"
        if [ "$VERBOSE" = 1 ]; then
            printf '    --- output ---\n'; sed 's/^/    /' <<<"$OUTPUT"
        fi
    fi
    FAILURES_THIS_CASE=
    unset POM_VERSION TEST_JAVA_HOME TEST_ENV
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
build_fake_remote
JDK21="$TESTROOT/jdk21"; make_fake_jdk "$JDK21" "21.0.9"
# The script requires *some* java on PATH before it starts choosing one, so put
# a fake there too: the suite then depends on nothing but git and coreutils.
FAKEBIN="$TESTROOT/bin"; mkdir -p "$FAKEBIN"; cp "$JDK21/bin/java" "$FAKEBIN/java"
JDK25="$TESTROOT/jdk25"; make_fake_jdk "$JDK25" "25.0.1"
JDK17="$TESTROOT/jdk17"; make_fake_jdk "$JDK17" "17.0.14"

echo "build-keycloak.sh test suite"

# ---------------------------------------------------------------------------
# Argument handling and validation
# ---------------------------------------------------------------------------

new_case "--help prints usage and exits 0"
run_build --help
expect_status 0
expect_output "Usage:"
expect_output "--quick"
expect_builds 0
end_case

new_case "rejects unknown options"
run_build --bogus
expect_status 1
expect_output "unknown option: --bogus"
expect_builds 0
end_case

new_case "rejects a second positional argument"
run_build 1.2.3 4.5.6
expect_status 1
expect_output "unexpected argument: 4.5.6"
expect_builds 0
end_case

new_case "rejects an implausible version string"
run_build '1.2.3; rm -rf /'
expect_status 1
expect_output "implausible version"
expect_builds 0
end_case

new_case "fails clearly when libs/pom.xml has no keycloak.version"
printf '<project/>\n' > "$REPO/libs/pom.xml"
run_build
expect_status 1
expect_output "could not read <keycloak.version>"
end_case

# ---------------------------------------------------------------------------
# Version and branch resolution
# ---------------------------------------------------------------------------

POM_VERSION=4.5.6 new_case "defaults the version to keycloak.version in libs/pom.xml"
run_build
expect_status 0
expect_output "using <keycloak.version> from libs/pom.xml: 4.5.6"
expect_file "$OUT/dist/keycloak-4.5.6.tar.gz"
end_case

new_case "an explicit version argument wins over libs/pom.xml"
run_build 4.5.6
expect_status 0
expect_no_output "using <keycloak.version>"
expect_file "$OUT/dist/keycloak-4.5.6.tar.gz"
expect_no_file "$OUT/dist/keycloak-1.2.3.tar.gz"
end_case

new_case "derives the branch as <version>_crdb"
run_build 1.2.3
expect_status 0
expect_output "1.2.3_crdb"
expect_eq "stamp" "$(cat "$OUT/installed-1.2.3.sha" 2>/dev/null)" "$(remote_sha 1.2.3_crdb)"
end_case

new_case "--branch overrides the derived branch name"
run_build -b custom-branch 7.8.9
expect_status 0
expect_output "custom-branch"
expect_file "$OUT/dist/keycloak-7.8.9.tar.gz"
end_case

new_case "unknown branch fails and lists the available _crdb branches"
run_build 9.9.9
expect_status 1
expect_output "branch 9.9.9_crdb not found"
expect_output "1.2.3_crdb"
expect_output "4.5.6_crdb"
expect_builds 0
end_case

# ---------------------------------------------------------------------------
# The build and the staged context
# ---------------------------------------------------------------------------

new_case "installs the jars libs/ compiles against"
run_build 1.2.3
expect_status 0
expect_builds 1
for a in keycloak-common keycloak-core keycloak-server-spi keycloak-server-spi-private; do
    expect_file "$M2/org/keycloak/$a/1.2.3/$a-1.2.3.jar"
done
end_case

new_case "stages the dist, the crdb driver and the m2 subset"
run_build 1.2.3
expect_status 0
expect_file "$OUT/dist/keycloak-1.2.3.tar.gz"
expect_file "$OUT/dist/cockroachdb-jdbc-driver-1.2.1.jar"
expect_file "$OUT/m2/repository/org/keycloak/keycloak-common/1.2.3/keycloak-common-1.2.3.jar"
expect_file "$OUT/installed-1.2.3.sha"
end_case

new_case "stages only the version being built, not the whole org/keycloak tree"
# Seed the local repo with another version, as a developer's ~/.m2 would have.
mkdir -p "$M2/org/keycloak/keycloak-common/9.9.9"
echo other > "$M2/org/keycloak/keycloak-common/9.9.9/keycloak-common-9.9.9.jar"
run_build 1.2.3
expect_status 0
expect_file "$OUT/m2/repository/org/keycloak/keycloak-common/1.2.3/keycloak-common-1.2.3.jar"
expect_no_file "$OUT/m2/repository/org/keycloak/keycloak-common/9.9.9/keycloak-common-9.9.9.jar"
end_case

new_case "keeps distribution archives out of the staged m2"
run_build 1.2.3
expect_status 0
expect_file "$M2/org/keycloak/keycloak-quarkus-dist/1.2.3/keycloak-quarkus-dist-1.2.3.tar.gz"
expect_no_file "$OUT/m2/repository/org/keycloak/keycloak-quarkus-dist/1.2.3/keycloak-quarkus-dist-1.2.3.tar.gz"
expect_no_file "$OUT/m2/repository/org/keycloak/keycloak-quarkus-dist/1.2.3/keycloak-quarkus-dist-1.2.3.zip"
end_case

new_case "passes -pl quarkus/dist -am only with --quick"
run_build 1.2.3
grep -q 'ARGS=.*-pl quarkus/dist -am' "$MVNW_LOG"; check "default run should not restrict modules" $((1 - $?))
run_build --quick --force 1.2.3
expect_status 0
grep -q 'ARGS=.*-pl quarkus/dist -am' "$MVNW_LOG"; check "--quick should pass -pl quarkus/dist -am" $?
expect_output "--quick"
end_case

new_case "forwards KEYCLOAK_MVN_ARGS to maven"
TEST_ENV="KEYCLOAK_MVN_ARGS=-DextraFlag=yes"
run_build 1.2.3
expect_status 0
grep -q 'ARGS=.*-DextraFlag=yes' "$MVNW_LOG"; check "extra mvn args should reach maven" $?
end_case

# ---------------------------------------------------------------------------
# Idempotency, staleness and the cache-hit path
# ---------------------------------------------------------------------------

new_case "a second run with nothing changed is a no-op"
run_build 1.2.3
run_build 1.2.3
expect_status 0
expect_output "nothing to do"
expect_builds 1
end_case

new_case "rebuilds when the staged context is incomplete"
# Regression: the stamp matches and the jars are installed, but the dist
# tarball is gone and the source tree can no longer supply it. Reporting
# success here leaves the image build to fail on a missing context.
run_build 1.2.3
rm -f "$OUT/dist/keycloak-1.2.3.tar.gz"
rm -rf "$SRC/quarkus/dist/target"
run_build 1.2.3
expect_status 0
expect_output "incomplete"
expect_builds 2
expect_file "$OUT/dist/keycloak-1.2.3.tar.gz"
end_case

new_case "restores the local repository from a cached export without building"
run_build 1.2.3
rm -rf "$M2/org/keycloak"
run_build 1.2.3
expect_status 0
expect_output "restored from the export"
expect_builds 1
expect_file "$M2/org/keycloak/keycloak-common/1.2.3/keycloak-common-1.2.3.jar"
end_case

new_case "--force rebuilds even when everything is in place"
run_build 1.2.3
run_build --force 1.2.3
expect_status 0
expect_builds 2
expect_no_output "nothing to do"
end_case

new_case "rebuilds when the stamp does not match the branch head"
run_build 1.2.3
echo "0000000000000000000000000000000000000000" > "$OUT/installed-1.2.3.sha"
run_build 1.2.3
expect_status 0
expect_builds 2
expect_eq "stamp" "$(cat "$OUT/installed-1.2.3.sha")" "$(remote_sha 1.2.3_crdb)"
end_case

new_case "switching versions restages the context for the new version"
run_build 1.2.3
run_build 4.5.6
expect_status 0
expect_builds 2
expect_file "$OUT/dist/keycloak-4.5.6.tar.gz"
expect_no_file "$OUT/dist/keycloak-1.2.3.tar.gz"
expect_file "$M2/org/keycloak/keycloak-common/4.5.6/keycloak-common-4.5.6.jar"
end_case

# ---------------------------------------------------------------------------
# Working copy safety and offline behaviour
# ---------------------------------------------------------------------------

new_case "refuses to touch a checkout with uncommitted changes"
run_build 1.2.3
echo "local edit" >> "$SRC/VERSION"
run_build --force 1.2.3
expect_status 1
expect_output "uncommitted changes"
expect_builds 1
end_case

new_case "ignores untracked files in the checkout"
run_build 1.2.3
touch "$SRC/some-untracked-build-output"
run_build --force 1.2.3
expect_status 0
expect_builds 2
end_case

new_case "falls back to the installed build when the remote is unreachable"
run_build 1.2.3
TEST_ENV="KEYCLOAK_REPO=file://$TESTROOT/does-not-exist"
run_build 1.2.3
expect_status 0
expect_output "cannot reach"
expect_output "nothing to do"
expect_builds 1
end_case

new_case "fails when the remote is unreachable and nothing is installed"
TEST_ENV="KEYCLOAK_REPO=file://$TESTROOT/does-not-exist"
run_build 1.2.3
expect_status 1
expect_output "not found"
expect_builds 0
end_case

# ---------------------------------------------------------------------------
# JDK selection — the difference between JDK 21 and a newer JDK is different
# bytecode, so this is load-bearing rather than cosmetic.
# ---------------------------------------------------------------------------

new_case "KEYCLOAK_JAVA_HOME pins the JDK maven runs with"
TEST_JAVA_HOME="$JDK21"
run_build 1.2.3
expect_status 0
grep -q "JAVA_HOME=$JDK21 " "$MVNW_LOG"; check "maven should run with the pinned JDK" $?
end_case

new_case "prefers a JDK 21 over a newer JAVA_HOME"
# Regression: JAVA_HOME pointing at a newer JDK (jenv, SDKMAN) must not decide
# the build. JAVA_HOME_21_X64 is what GitHub runners expose.
env -u JAVA_HOME -u JAVA_HOME_21_X64 -u JAVA_HOME_21_ARM64 -u KEYCLOAK_JAVA_HOME \
    PATH="$FAKEBIN:$PATH" JAVA_HOME="$JDK25" JAVA_HOME_21_X64="$JDK21" \
    KEYCLOAK_REPO="file://$FAKE_REMOTE" KEYCLOAK_SRC="$SRC" KEYCLOAK_OUT="$OUT" \
    MAVEN_REPO_LOCAL="$M2" MVNW_LOG="$MVNW_LOG" \
    bash "$REPO/scripts/build-keycloak.sh" 1.2.3 > "$CASE_DIR/stdout" 2> "$CASE_DIR/stderr"
STATUS=$?; OUTPUT=$(cat "$CASE_DIR/stdout" "$CASE_DIR/stderr")
expect_status 0
expect_output "using JDK 21 at $JDK21"
grep -q "JAVA_HOME=$JDK21 " "$MVNW_LOG"; check "maven should run with the JDK 21, not JAVA_HOME" $?
end_case

new_case "warns when no JDK 21 is available"
TEST_JAVA_HOME="$JDK25"
run_build 1.2.3
expect_status 0
expect_output "building with JDK 25"
end_case

new_case "refuses to build on a JDK older than 21"
TEST_JAVA_HOME="$JDK17"
run_build 1.2.3
expect_status 1
expect_output "JDK 21+ required"
expect_builds 0
end_case

# ---------------------------------------------------------------------------
# Output location
# ---------------------------------------------------------------------------

new_case "--out relocates the staged build context"
ALT="$CASE_DIR/elsewhere"
run_build -o "$ALT" 1.2.3
expect_status 0
expect_file "$ALT/dist/keycloak-1.2.3.tar.gz"
expect_file "$ALT/installed-1.2.3.sha"
expect_no_file "$OUT/dist/keycloak-1.2.3.tar.gz"
end_case

new_case "reports the docker build command with the staged context path"
run_build 1.2.3
expect_status 0
expect_output "--build-context keycloak="
end_case

# ---------------------------------------------------------------------------
# Containment: everything the script writes must land under the directories it
# was pointed at. A stray write into a developer's ~/.m2 or the repo would be
# invisible in every assertion above.
# ---------------------------------------------------------------------------

new_case "writes nothing outside the directories it was given"
CANARY_HOME="$CASE_DIR/home"
mkdir -p "$CANARY_HOME"
before=$(find "$REPO" -type f | sort)
TEST_ENV="HOME=$CANARY_HOME"
run_build 1.2.3
expect_status 0
expect_eq "repo tree" "$(find "$REPO" -type f | sort)" "$before"
[ ! -d "$CANARY_HOME/.m2" ]; check "must not create a maven repo under HOME" $?
for d in dist m2 installed-1.2.3.sha; do
    expect_file_or_dir "$OUT/$d"
done
end_case

# ---------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASSED" "$FAILED"
if [ "$FAILED" -gt 0 ]; then
    printf 'failed:%s\n' "$FAILED_CASES"
    exit 1
fi
