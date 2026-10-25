# MuleSoft GitHub Actions framework

One reusable workflow, `.github/workflows/mule-pipeline.yml`, builds, publishes and deploys Mule 4
applications. The caller's event decides which stages run:

| Trigger | Unit tests | Package | Publish to Exchange | Deploy |
|---|---|---|---|---|
| Pull request | yes | yes | - | - |
| Merge to `develop` | yes | yes | `X.Y.Z-dev.<run number>` | Sandbox (automatic) |
| Merge to `main` | yes | yes | `X.Y.Z` (release) | - |
| Manual run (CD) | - | - | - | chosen environment, from Exchange |

## Versions

The base version is the POM `<version>` without `-SNAPSHOT`.

- `develop`: `<base>-dev.<GitHub run number>`, for example `1.0.0-dev.57`. Unique per run.
- `main`: `<base>` exactly. Exchange versions are immutable, so bump the POM version before merging
  to `main`; publishing an existing version fails.

The version is set in the build only (`versions:set`); the POM in the repository is not changed.

## Use it in an application repository

Copy `pipeline.yml` from the sample app (`mulesoft-github-actions-ci-smoke-test`). It calls this
workflow with `secrets: inherit`. The POM needs the Exchange repository and the same id in
`distributionManagement`, so one credential entry covers resolve and publish:

```xml
<repositories>
  <repository>
    <id>anypoint-exchange-v3</id>
    <url>https://maven.anypoint.mulesoft.com/api/v3/maven</url>
  </repository>
</repositories>
<distributionManagement>
  <repository>
    <id>anypoint-exchange-v3</id>
    <url>https://maven.anypoint.mulesoft.com/api/v3/organizations/${anypoint.org.id}/maven</url>
  </repository>
</distributionManagement>
```

The POM `groupId` must be the Anypoint organization ID.

## Configuration (set once at the GitHub organization)

```bash
gh secret set ANYPOINT_USERNAME --org <org> --visibility all
gh secret set ANYPOINT_PASSWORD --org <org> --visibility all
gh variable set ANYPOINT_ORG_ID --org <org> --visibility all --body "<root organization id>"
gh variable set ANYPOINT_ENVIRONMENT --org <org> --visibility all --body "Sandbox"
gh variable set ANYPOINT_DEPLOYMENT_TARGET --org <org> --visibility all --body "<target id>"
gh variable set MULE_RUNTIME_VERSION --org <org> --visibility all --body "4.13.0"
```

Optional variables: `ANYPOINT_BASE_URI`, `MULE_APPLICATION_NAME` (default: artifactId),
`MULE_RELEASE_CHANNEL` (`EDGE`), `MULE_JAVA_VERSION` (`17`), `MULE_VCORES` (`0.1`), `MULE_REPLICAS` (`1`).

Target ids come from `GET /runtimefabric/api/organizations/<org>/targets` (for a shared space, for
example `cloudhub-us-east-2`). For `qa`, `uat` and `prod`, create a GitHub Environment of that name
in the application repository and set `ANYPOINT_ENVIRONMENT`, `ANYPOINT_DEPLOYMENT_TARGET` (and
credentials if they differ) there; environment values override organization ones, and the
environment's protection rules gate the deployment.

## Deploying

`scripts/deploy.sh` calls the Runtime Manager API: it creates the deployment, or updates the one with
the same application name, pointing it at the published Exchange asset, then waits until Runtime
Manager reports that version as running. Manual deployments use the same script.
