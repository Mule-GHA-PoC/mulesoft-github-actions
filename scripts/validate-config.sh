#!/usr/bin/env bash
# Validates the configuration needed for a CI mode before any Anypoint call is made.
# Usage: validate-config.sh <ci|publish|deploy>
#   ci      - build/test only; no Anypoint configuration required
#   publish - Exchange publication; org ID, base URI and credentials required
#   deploy  - CloudHub 2.0 deployment; publish settings plus target settings required
set -euo pipefail

mode="${1:?usage: validate-config.sh <ci|publish|deploy>}"
errors=0

fail() {
  echo "::error::$1" >&2
  errors=$((errors + 1))
}

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing required variable or secret: ${name}"
  fi
}

check_pattern() {
  local name="$1" pattern="$2" hint="$3"
  if [[ -n "${!name:-}" && ! "${!name}" =~ ${pattern} ]]; then
    fail "${name} is invalid: ${hint}"
  fi
}

case "$mode" in
  ci) ;;
  publish | deploy)
    require ANYPOINT_BASE_URI
    require ANYPOINT_ORG_ID
    check_pattern ANYPOINT_ORG_ID '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "expected a UUID"
    check_pattern ANYPOINT_BASE_URI '^https://[A-Za-z0-9.-]+$' "expected https://host without a path"
    require ANYPOINT_USERNAME
    require ANYPOINT_PASSWORD
    ;;
  *)
    fail "Unknown mode '${mode}'. Use ci, publish or deploy."
    ;;
esac

if [[ "$mode" == "deploy" ]]; then
  require ANYPOINT_ENVIRONMENT
  require ANYPOINT_DEPLOYMENT_TARGET
  require MULE_APPLICATION_NAME
  require MULE_RUNTIME_VERSION
  check_pattern MULE_APPLICATION_NAME '^[a-z][a-z0-9-]{1,40}$' "lowercase letters, digits and hyphens, 2-41 characters, starting with a letter"
  check_pattern MULE_VCORES '^[0-9]+(\.[0-9]+)?$' "expected a number such as 0.1 or 1"
  check_pattern MULE_REPLICAS '^[1-9][0-9]*$' "expected a positive integer"
  check_pattern MULE_DEPLOYMENT_TIMEOUT '^[1-9][0-9]*$' "expected a positive number of seconds"
  check_pattern MULE_RELEASE_CHANNEL '^(LTS|EDGE)$' "expected LTS or EDGE"
  check_pattern MULE_JAVA_VERSION '^(8|11|17)$' "expected 8, 11 or 17"
fi

if (( errors > 0 )); then
  echo "Configuration validation failed with ${errors} error(s)." >&2
  exit 1
fi

echo "Configuration valid for mode '${mode}'."
