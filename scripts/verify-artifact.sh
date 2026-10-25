#!/usr/bin/env bash
# Verifies that a JAR is a genuine Mule application archive, writes its SHA-256 checksum
# and build metadata next to it.
#
# Usage: verify-artifact.sh <jar> <group_id> <artifact_id> <version>
# Reads GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_REPOSITORY, GITHUB_REF.
set -euo pipefail

jar="${1:?usage: verify-artifact.sh <jar> <group_id> <artifact_id> <version>}"
group_id="${2:?group id required}"
artifact_id="${3:?artifact id required}"
version="${4:?version required}"

if [[ ! -f "$jar" ]]; then
  echo "::error::Expected artifact not found: ${jar}" >&2
  exit 1
fi

if ! unzip -tq "$jar" >/dev/null; then
  echo "::error::${jar} is not a valid ZIP archive" >&2
  exit 1
fi

entries=$(unzip -Z1 "$jar")

# A Mule application archive carries its descriptor and at least one Mule XML config.
if ! grep -q 'mule-artifact.json$' <<< "$entries"; then
  echo "::error::${jar} has no mule-artifact.json descriptor; it is not a Mule application" >&2
  exit 1
fi
if ! grep -qE '^[^/]+\.xml$|^src/main/mule/.+\.xml$' <<< "$entries"; then
  echo "::error::${jar} contains no top-level Mule XML configuration" >&2
  exit 1
fi

jar_dir=$(dirname "$jar")
jar_name=$(basename "$jar")
sha256=$(sha256sum "$jar" | cut -d' ' -f1)
printf '%s  %s\n' "$sha256" "$jar_name" > "${jar_dir}/${jar_name}.sha256"

META_GROUP="$group_id" META_ARTIFACT="$artifact_id" META_VERSION="$version" \
META_JAR="$jar_name" META_SHA256="$sha256" \
python3 -I - "$jar_dir/build-metadata.json" <<'PY'
import json, os, sys
metadata = {
    "groupId": os.environ["META_GROUP"],
    "artifactId": os.environ["META_ARTIFACT"],
    "version": os.environ["META_VERSION"],
    "classifier": "mule-application",
    "jarFile": os.environ["META_JAR"],
    "sha256": os.environ["META_SHA256"],
    "gitCommit": os.environ.get("GITHUB_SHA", "unknown"),
    "gitRef": os.environ.get("GITHUB_REF", "unknown"),
    "repository": os.environ.get("GITHUB_REPOSITORY", "unknown"),
    "runId": os.environ.get("GITHUB_RUN_ID", "unknown"),
    "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT", "unknown"),
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, indent=2)
    handle.write("\n")
PY

echo "Verified Mule application archive ${jar_name}"
echo "SHA-256: ${sha256}"
