#!/usr/bin/env bash
# Generates a deploy-only POM for CloudHub 2.0 with the mule-maven-plugin.
# The deploy job never compiles the application: it places the already-published JAR under
# target/ and runs `mvn mule:deploy` against this POM.
#
# Usage: write-deploy-pom.sh <out_dir> <group_id> <artifact_id> <version> <auth_mode>
#   auth_mode: connected-app | username-password
#
# All target settings come from environment variables (see docs/github-configuration.md).
# Credential values are referenced as ${env.*}, so they are not written into the POM.
set -euo pipefail

out_dir="${1:?out dir required}"
group_id="${2:?group id required}"
artifact_id="${3:?artifact id required}"
version="${4:?version required}"
auth_mode="${5:?auth mode required}"

case "$auth_mode" in
  connected-app)
    auth_xml='<connectedAppClientId>${env.ANYPOINT_CLIENT_ID}</connectedAppClientId>
          <connectedAppClientSecret>${env.ANYPOINT_CLIENT_SECRET}</connectedAppClientSecret>
          <connectedAppGrantType>client_credentials</connectedAppGrantType>' ;;
  username-password)
    auth_xml='<username>${env.ANYPOINT_USERNAME}</username>
          <password>${env.ANYPOINT_PASSWORD}</password>' ;;
  *)
    echo "::error::Unknown auth mode '${auth_mode}'" >&2
    exit 1 ;;
esac

business_group_xml=""
if [[ -n "${ANYPOINT_BUSINESS_GROUP_ID:-}" ]]; then
  business_group_xml='<businessGroupId>${env.ANYPOINT_BUSINESS_GROUP_ID}</businessGroupId>'
fi

mkdir -p "$out_dir"
cat > "${out_dir}/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>${group_id}</groupId>
  <artifactId>${artifact_id}</artifactId>
  <version>${version}</version>
  <packaging>mule-application</packaging>
  <build>
    <plugins>
      <plugin>
        <groupId>org.mule.tools.maven</groupId>
        <artifactId>mule-maven-plugin</artifactId>
        <version>${MULE_MAVEN_PLUGIN_VERSION:?MULE_MAVEN_PLUGIN_VERSION is required}</version>
        <extensions>true</extensions>
        <configuration>
          <classifier>mule-application</classifier>
          <cloudhub2Deployment>
            <uri>\${env.ANYPOINT_BASE_URI}</uri>
            <provider>MC</provider>
            <environment>\${env.ANYPOINT_ENVIRONMENT}</environment>
            <target>\${env.ANYPOINT_DEPLOYMENT_TARGET}</target>
            <applicationName>\${env.MULE_APPLICATION_NAME}</applicationName>
            <muleVersion>\${env.MULE_RUNTIME_VERSION}</muleVersion>
            <releaseChannel>\${env.MULE_RELEASE_CHANNEL}</releaseChannel>
            <javaVersion>\${env.MULE_JAVA_VERSION}</javaVersion>
            <vCores>\${env.MULE_VCORES}</vCores>
            <replicas>\${env.MULE_REPLICAS}</replicas>
            <deploymentTimeout>\${env.MULE_DEPLOYMENT_TIMEOUT}</deploymentTimeout>
            ${business_group_xml}
            ${auth_xml}
          </cloudhub2Deployment>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF
echo "Wrote deploy POM to ${out_dir}/pom.xml (auth: ${auth_mode})"
