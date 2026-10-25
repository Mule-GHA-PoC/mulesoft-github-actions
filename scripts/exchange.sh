#!/usr/bin/env bash
# Reads from the Anypoint Exchange Maven Facade for one application version.
#
# Usage:
#   exchange.sh exists   <org_id> <artifact_id> <version>   exit 0 if the version exists, 1 if not
#   exchange.sh download <org_id> <artifact_id> <version> <dest_dir>
#                                                           download the mule-application JAR, print its sha256
#
# Requires ANYPOINT_BASE_URI-independent Exchange host (https://maven.anypoint.mulesoft.com) for the
# standard cloud; set EXCHANGE_MAVEN_HOST for other control planes (e.g. maven.eu1.anypoint.mulesoft.com).
# Credentials come from the environment (ANYPOINT_CLIENT_ID/SECRET or ANYPOINT_USERNAME/PASSWORD)
# and are passed to curl via a config read from stdin, so they never appear in process arguments.
set -euo pipefail

action="${1:?usage: exchange.sh <exists|download> ...}"
org_id="${2:?org id required}"
artifact_id="${3:?artifact id required}"
version="${4:?version required}"
host="${EXCHANGE_MAVEN_HOST:-maven.anypoint.mulesoft.com}"

if [[ -n "${ANYPOINT_CLIENT_ID:-}" && -n "${ANYPOINT_CLIENT_SECRET:-}" ]]; then
  auth_user="~~~Client~~~"
  auth_pass="${ANYPOINT_CLIENT_ID}~?~${ANYPOINT_CLIENT_SECRET}"
else
  auth_user="${ANYPOINT_USERNAME:?credentials required}"
  auth_pass="${ANYPOINT_PASSWORD:?credentials required}"
fi

base="https://${host}/api/v3/organizations/${org_id}/maven/${org_id}/${artifact_id}/${version}"
jar_name="${artifact_id}-${version}-mule-application.jar"

curl_auth() {
  printf 'user = "%s:%s"\n' "$auth_user" "$auth_pass" | curl --silent --show-error --fail-with-body -K - "$@"
}

case "$action" in
  exists)
    code=$(printf 'user = "%s:%s"\n' "$auth_user" "$auth_pass" \
      | curl --silent --output /dev/null --write-out '%{http_code}' -K - "${base}/${artifact_id}-${version}.pom") || code="000"
    case "$code" in
      200) echo "Exchange already has ${artifact_id}:${version}"; exit 0 ;;
      404) echo "Exchange has no ${artifact_id}:${version}"; exit 1 ;;
      401 | 403)
        echo "::error::Exchange rejected the credentials or permissions (HTTP ${code})" >&2
        exit 2
        ;;
      *)
        echo "::error::Unexpected Exchange response (HTTP ${code}) checking ${artifact_id}:${version}" >&2
        exit 2
        ;;
    esac
    ;;
  download)
    dest="${5:?destination directory required}"
    mkdir -p "$dest"
    curl_auth --location --output "${dest}/${jar_name}" "${base}/${jar_name}"
    if ! unzip -tq "${dest}/${jar_name}" >/dev/null 2>&1; then
      echo "::error::Downloaded ${jar_name} is not a valid archive" >&2
      exit 1
    fi
    sha256sum "${dest}/${jar_name}" | cut -d' ' -f1
    ;;
  *)
    echo "::error::Unknown action '${action}'" >&2
    exit 1
    ;;
esac
