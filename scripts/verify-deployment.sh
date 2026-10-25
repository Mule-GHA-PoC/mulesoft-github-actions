#!/usr/bin/env bash
# Polls CloudHub 2.0 Runtime Manager until the application reports a running state.
# Runtime Manager is the authoritative source; a successful `mvn mule:deploy` alone is not enough.
#
# Usage: verify-deployment.sh <org_id> <environment_name> <application_name> <timeout_seconds>
# Credentials come from ANYPOINT_CLIENT_ID/SECRET or ANYPOINT_USERNAME/PASSWORD and are sent to
# curl through stdin config, never as process arguments. Writes a sanitized summary to
# $GITHUB_STEP_SUMMARY when set.
set -euo pipefail

org_id="${1:?org id required}"
env_name="${2:?environment name required}"
app_name="${3:?application name required}"
timeout_s="${4:?timeout seconds required}"
base="${ANYPOINT_BASE_URI:?ANYPOINT_BASE_URI required}"

api_post_json() { # url, json body -> stdout
  curl --silent --show-error --fail-with-body -H 'Content-Type: application/json' \
    --data-binary "$2" "$1"
}

if [[ -n "${ANYPOINT_CLIENT_ID:-}" && -n "${ANYPOINT_CLIENT_SECRET:-}" ]]; then
  token=$(curl --silent --show-error --fail-with-body \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=${ANYPOINT_CLIENT_ID}" \
    --data-urlencode "client_secret=${ANYPOINT_CLIENT_SECRET}" \
    "${base}/accounts/api/v2/oauth2/token" \
    | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
else
  login_body=$(python3 -I -c '
import json, os
print(json.dumps({"username": os.environ["ANYPOINT_USERNAME"], "password": os.environ["ANYPOINT_PASSWORD"]}))
')
  token=$(api_post_json "${base}/accounts/login" "$login_body" \
    | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
fi

auth_config() { printf 'header = "Authorization: Bearer %s"\n' "$token"; }

env_id=$(auth_config | curl --silent --show-error --fail-with-body -K - \
  "${base}/accounts/api/organizations/${org_id}/environments" \
  | python3 -I -c '
import json, sys
name = sys.argv[1]
for env in json.load(sys.stdin)["data"]:
    if env["name"] == name:
        print(env["id"])
        break
' "$env_name")

if [[ -z "$env_id" ]]; then
  echo "::error::Environment '${env_name}' not found in organization ${org_id}" >&2
  exit 1
fi

deadline=$(( $(date +%s) + timeout_s ))
while true; do
  status_json=$(auth_config | curl --silent --show-error --fail-with-body -K - \
    "${base}/amc/application-manager/api/v2/organizations/${org_id}/environments/${env_id}/deployments?name=${app_name}" \
    || echo '{}')

  state=$(python3 -I -c '
import json, sys
data = json.load(sys.stdin)
items = data.get("items") or data.get("data") or []
match = [item for item in items if item.get("name") == sys.argv[1]]
if not match:
    print("NOT_FOUND")
else:
    item = match[0]
    status = (item.get("application") or {}).get("status") or item.get("status") or "UNKNOWN"
    print(status)
' "$app_name" <<< "$status_json")

  echo "Runtime Manager state for ${app_name} in ${env_name}: ${state}"
  case "$state" in
    RUNNING | STARTED | APPLIED)
      summary="Runtime Manager reports ${app_name} as ${state} in ${env_name}."
      break ;;
    FAILED | DEPLOY_FAILED | UNDEPLOYED)
      echo "::error::Runtime Manager reports ${app_name} as ${state}" >&2
      exit 1 ;;
  esac

  if (( $(date +%s) >= deadline )); then
    echo "::error::Timed out after ${timeout_s}s waiting for ${app_name} to run (last state: ${state})" >&2
    exit 1
  fi
  sleep 15
done

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "- ${summary}" >> "$GITHUB_STEP_SUMMARY"
fi
echo "$summary"
