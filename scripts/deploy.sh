#!/usr/bin/env bash
# Deploys a published Exchange asset to CloudHub 2.0 through the Anypoint Runtime Manager API and
# waits until it runs. Creates the deployment, or updates it when one with the same name exists.
#
# Required env: ANYPOINT_ORG_ID, ANYPOINT_ENVIRONMENT, ANYPOINT_DEPLOYMENT_TARGET, MULE_RUNTIME_VERSION,
#               ANYPOINT_USERNAME, ANYPOINT_PASSWORD, ARTIFACT_ID, VERSION
# Optional env: ANYPOINT_BASE_URI, MULE_APPLICATION_NAME (default ARTIFACT_ID), MULE_RELEASE_CHANNEL (EDGE),
#               MULE_JAVA_VERSION (17), MULE_VCORES (0.1), MULE_REPLICAS (1)
set -euo pipefail

for v in ANYPOINT_ORG_ID ANYPOINT_ENVIRONMENT ANYPOINT_DEPLOYMENT_TARGET MULE_RUNTIME_VERSION \
         ANYPOINT_USERNAME ANYPOINT_PASSWORD ARTIFACT_ID VERSION; do
  [[ -n "${!v:-}" ]] || { echo "::error::Missing required variable or secret: $v"; exit 1; }
done

base="${ANYPOINT_BASE_URI:-https://anypoint.mulesoft.com}"
app="${MULE_APPLICATION_NAME:-$ARTIFACT_ID}"
api="$base/amc/application-manager/api/v2/organizations/$ANYPOINT_ORG_ID"

token=$(jq -n --arg u "$ANYPOINT_USERNAME" --arg p "$ANYPOINT_PASSWORD" '{username: $u, password: $p}' \
  | curl -fsS -X POST "$base/accounts/login" -H 'Content-Type: application/json' -d @- | jq -r .access_token)
echo "::add-mask::$token"
call() { curl -fsS -H "Authorization: Bearer $token" -H 'Content-Type: application/json' "$@"; }

env_id=$(call "$base/accounts/api/organizations/$ANYPOINT_ORG_ID/environments" \
  | jq -r --arg n "$ANYPOINT_ENVIRONMENT" '.data[] | select(.name == $n) | .id')
[[ -n "$env_id" ]] || { echo "::error::Environment '$ANYPOINT_ENVIRONMENT' not found"; exit 1; }
deployments="$api/environments/$env_id/deployments"

body=$(jq -n \
  --arg app "$app" --arg group "$ANYPOINT_ORG_ID" --arg artifact "$ARTIFACT_ID" --arg version "$VERSION" \
  --arg target "$ANYPOINT_DEPLOYMENT_TARGET" --arg runtime "$MULE_RUNTIME_VERSION" \
  --arg channel "${MULE_RELEASE_CHANNEL:-EDGE}" --arg java "${MULE_JAVA_VERSION:-17}" \
  --argjson vcores "${MULE_VCORES:-0.1}" --argjson replicas "${MULE_REPLICAS:-1}" '{
    name: $app,
    labels: [],
    target: {
      provider: "MC",
      targetId: $target,
      replicas: $replicas,
      deploymentSettings: {
        runtimeVersion: $runtime,
        runtime: {version: $runtime, releaseChannel: $channel, java: $java},
        updateStrategy: "rolling"
      }
    },
    application: {
      ref: {groupId: $group, artifactId: $artifact, version: $version, packaging: "jar"},
      assets: [],
      desiredState: "STARTED",
      vCores: $vcores,
      configuration: {
        "mule.agent.application.properties.service": {applicationName: $app, properties: {}, secureProperties: {}}
      }
    }
  }')

id=$(call "$deployments" | jq -r --arg n "$app" '(.items // [])[] | select(.name == $n) | .id' | head -n1)
if [[ -n "$id" ]]; then
  echo "Updating deployment $app ($id) to $ARTIFACT_ID:$VERSION"
  call -X PATCH "$deployments/$id" -d "$body" > /dev/null
else
  echo "Creating deployment $app for $ARTIFACT_ID:$VERSION"
  id=$(call -X POST "$deployments" -d "$body" | jq -r .id)
fi

for _ in $(seq 1 60); do
  state=$(call "$deployments/$id" | jq -r '[.status, .application.status, .application.ref.version] | join(" / ")')
  echo "Runtime Manager: $state"
  case "$state" in
    *FAILED*) echo "::error::Deployment of $app failed"; exit 1 ;;
    "APPLIED / RUNNING / $VERSION") echo "$app is running ($ARTIFACT_ID:$VERSION)"; exit 0 ;;
  esac
  sleep 15
done
echo "::error::Timed out waiting for $app to run"
exit 1
