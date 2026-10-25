#!/usr/bin/env bash
# Calculates the artifact version and writes it to $GITHUB_OUTPUT.
#
# Policy (see docs/architecture.md):
#   - Release: a tag vX.Y.Z whose X.Y.Z equals the POM base version -> version X.Y.Z (immutable)
#   - Dev:     any other run (push, PR, rerun) -> X.Y.Z-dev.<run_id> (unique per workflow run)
#
# Usage: calculate-version.sh <path/to/pom.xml>
# Reads GITHUB_REF_TYPE, GITHUB_REF_NAME, GITHUB_RUN_ID, GITHUB_SHA, GITHUB_EVENT_NAME.
set -euo pipefail

pom="${1:?usage: calculate-version.sh <pom.xml>}"

base=$(python3 -I -c '
import sys, xml.etree.ElementTree as ET
ns = {"m": "http://maven.apache.org/POM/4.0.0"}
version = ET.parse(sys.argv[1]).getroot().find("m:version", ns)
print(version.text.strip() if version is not None and version.text else "")
' "$pom")

base="${base%-SNAPSHOT}"
if [[ ! "$base" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::POM <version> must be X.Y.Z (optionally -SNAPSHOT); found '${base}'" >&2
  exit 1
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  release="${BASH_REMATCH[1]}"
  if [[ "$release" != "$base" ]]; then
    echo "::error::Tag ${GITHUB_REF_NAME} does not match POM base version ${base}" >&2
    exit 1
  fi
  kind="release"
  version="$release"
else
  kind="dev"
  version="${base}-dev.${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
fi

short_sha="${GITHUB_SHA:0:7}"
echo "Calculated version ${version} (${kind}) for commit ${short_sha}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=${version}"
    echo "kind=${kind}"
    echo "base_version=${base}"
    echo "short_sha=${short_sha}"
  } >> "$GITHUB_OUTPUT"
fi
