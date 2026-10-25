# MuleSoft GitHub Actions framework

One reusable workflow, `.github/workflows/mule-pipeline.yml`, builds, publishes, releases and deploys
Mule 4 applications. Each stage is a job; the caller's event enables it or shows it as skipped.

| Trigger | Unit test | Package | Publish | Deploy Sandbox | Release |
|---|---|---|---|---|---|
| Pull request | yes | yes | - | - | - |
| Merge to `develop` | yes | yes | yes (SNAPSHOT) | yes | - |
| Merge to `main` | yes | - | - | - | yes |
| Manual run (CD) | - | - | - | - | - |

A manual run only deploys: a published Exchange version to the chosen environment, with no build.

## Versions and release

The POM holds `X.Y.Z-SNAPSHOT`.

- **`develop`** publishes that SNAPSHOT to Exchange (Exchange accepts a republished SNAPSHOT) and deploys it.
- **`main`** runs `maven-release-plugin` `prepare` and `perform`: it publishes `X.Y.Z` to Exchange, tags
  `vX.Y.Z`, and commits the next `X.Y.(Z+1)-SNAPSHOT` to `main`. The Release stage then merges `main` back
  into `develop` so both branches carry the next version. Release commits are authored by `github-actions[bot]`.

The release pushes directly to `main`, so `main` must not require pull requests for the Actions bot.
The back-merge conflicts only if the POM version line was edited on `develop` in the meantime.

## Use it in an application repository

Copy `pipeline.yml` from the sample app (`mulesoft-github-actions-ci-smoke-test`). It calls this workflow
with `secrets: inherit` and `contents: write` (the Release stage needs it). The POM needs the SNAPSHOT
version, an `scm` block for the release plugin, and the Exchange repository with the same id in
`distributionManagement`, so one credential entry covers resolve and publish:

```xml
<scm>
  <connection>scm:git:https://github.com/<org>/<repo>.git</connection>
  <developerConnection>scm:git:https://github.com/<org>/<repo>.git</developerConnection>
  <tag>HEAD</tag>
</scm>
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
Manager reports that version as running. Automatic and manual deployments use the same script.
