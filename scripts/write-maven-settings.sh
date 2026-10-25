#!/usr/bin/env bash
# Writes ~/.m2/settings.xml with the Exchange Maven Facade server entry.
# The file references environment variables only; no secret value is written to disk.
#
# Auth mode is chosen from the environment:
#   - connected app (ANYPOINT_CLIENT_ID + ANYPOINT_CLIENT_SECRET) when both are set
#   - username/password (ANYPOINT_USERNAME + ANYPOINT_PASSWORD) otherwise
# Usage: write-maven-settings.sh <repository-server-id>
set -euo pipefail

server_id="${1:?usage: write-maven-settings.sh <repository-server-id>}"
settings_dir="${HOME}/.m2"
mkdir -p "$settings_dir"

if [[ -n "${ANYPOINT_CLIENT_ID:-}" && -n "${ANYPOINT_CLIENT_SECRET:-}" ]]; then
  mode="connected-app"
  user_xml='<username>~~~Client~~~</username>'
  pass_xml='<password>${env.ANYPOINT_CLIENT_ID}~?~${env.ANYPOINT_CLIENT_SECRET}</password>'
elif [[ -n "${ANYPOINT_USERNAME:-}" && -n "${ANYPOINT_PASSWORD:-}" ]]; then
  mode="username-password"
  user_xml='<username>${env.ANYPOINT_USERNAME}</username>'
  pass_xml='<password>${env.ANYPOINT_PASSWORD}</password>'
else
  echo "::error::No Anypoint credentials: set ANYPOINT_CLIENT_ID/ANYPOINT_CLIENT_SECRET or ANYPOINT_USERNAME/ANYPOINT_PASSWORD" >&2
  exit 1
fi

cat > "${settings_dir}/settings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
    <server>
      <id>${server_id}</id>
      ${user_xml}
      ${pass_xml}
    </server>
  </servers>
</settings>
EOF
chmod 600 "${settings_dir}/settings.xml"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "auth_mode=${mode}" >> "$GITHUB_OUTPUT"
fi
echo "Wrote Maven settings for server '${server_id}' using ${mode} authentication."
