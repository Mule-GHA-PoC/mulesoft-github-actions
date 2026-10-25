# Architecture

## Components

- **Framework repository** (`Mule-GHA-PoC/mulesoft-github-actions`): reusable workflows, scripts, docs.
- **Application repository** (for example `Mule-GHA-PoC/mulesoft-github-actions-ci-smoke-test`): Mule
  project plus a thin caller workflow that passes flags and secrets to the framework.

## Job graph (`reusable-mule-ci.yml`)

```
1 validate ──► 2 test ──► 3 version ──► 4 package ──► 5 publish ──► 6 deploy (reusable-mule-deploy)
 (config,        (MUnit)   (version,       (JAR, sha256,   (Exchange,     (download exact Exchange JAR,
  POM, descr.)             coords)          metadata,       skipped for    verify sha256, mule:deploy,
                                            GH artifact)    publish=false) verify in Runtime Manager)
```

Every job `needs` the previous one, so a failure stops all downstream jobs. `publish` runs only when
the caller sets `publish: true`. `deploy` runs only when the caller sets `deploy: true`, and
`deploy` requires `publish`. Pull request callers set neither and pass no secrets.

## Triggers and callers

| Event | Caller job | publish | deploy | Secrets |
| --- | --- | --- | --- | --- |
| `pull_request` to `develop`/`main` | `pr-checks` | no | no | none |
| `push` to `develop` | `develop` | dev version | yes, Sandbox | inherited |
| `push` to `main` | `main-checks` | no | no | none |
| `push` tag `vX.Y.Z` | `release` | release version | no | inherited |
| `workflow_dispatch` on framework `mule-cd.yml` | — | — | yes, qa/uat/prod | environment secrets |

Concurrency: pushes are never cancelled (`cancel-in-progress: false`), so a deployment in progress is
not interrupted by a newer commit. Deploy jobs also use a per-app, per-environment concurrency group.
Pull request runs supersede older runs of the same PR.

## Versioning policy

| Kind | Trigger | Version | Exchange behaviour |
| --- | --- | --- | --- |
| Dev | any non-tag run | `X.Y.Z-dev.<GITHUB_RUN_ID>` where `X.Y.Z` is the POM base | published on `develop`; if the version already exists the publish step is skipped, not failed |
| Release | tag `vX.Y.Z` equal to POM base | `X.Y.Z` | fails fast if the version already exists; never overwritten |
| PR | `pull_request` | dev form, never published | no publication |

- The POM `<version>` is the base `X.Y.Z` (an optional `-SNAPSHOT` suffix is stripped). The workflow
  rewrites the version per run with `versions:set`; the committed POM is not changed.
- The version is calculated once in job 3 and passed to every later job as an output.
- The GitHub run number is not used as a semantic version. The run ID appears only in the dev
  pre-release identifier, which keeps each run's coordinate unique.
- Mutable snapshot coordinates are not used as proof of the deployed binary. The identity of
  deployed code is the SHA-256 of the Exchange JAR, recorded in `build-metadata.json` and the publish
  step summary, and checked again before deployment.

Identities recorded per run:

| Identity | Where |
| --- | --- |
| Git commit SHA | `build-metadata.json` `gitCommit`, GitHub run page |
| GitHub Actions run ID and attempt | `build-metadata.json` `runId`, `runAttempt` |
| Maven coordinates | `groupId:artifactId:version`, classifier `mule-application` |
| JAR SHA-256 | `<jar>.sha256`, `build-metadata.json`, publish step summary, deployment metadata |
| Deployment | Runtime Manager application name and environment; `deployment-metadata.json` artifact |

## Publication model

- Exchange is the system of record for published application versions. It is accessed through the
  Exchange Maven Facade at `https://maven.anypoint.mulesoft.com/api/v3/organizations/<ORG_ID>/maven`
  (EU control plane: `maven.eu1.anypoint.mulesoft.com`, set `EXCHANGE_MAVEN_HOST`).
- Publication uses `mule-maven-plugin` with classifier `mule-application`, not `maven-deploy-plugin`.
- `groupId` must equal the Anypoint organization ID. The publish job checks this before publishing.
- After publication, the publish job downloads the Exchange copy and records its SHA-256. Deployment
  downloads the Exchange copy again and compares it with that value.
- **GitHub Actions artifacts are not a release repository.** They expire (14 days here) and belong to
  one run. The authoritative binary for promotion is the immutable Exchange asset.

## Deployment model

- Deployment never compiles. `write-deploy-pom.sh` generates a deploy-only POM, the Exchange JAR is
  placed at `target/<artifactId>-<version>-mule-application.jar`, and `mvn mule:deploy` runs against
  that POM. This follows the documented "deploy without rebuilding" approach
  (`mvn mule:deploy`).
- Target settings come from environment variables (`${env.*}`) so no value is hard-coded in a POM.
  Credentials are referenced the same way and never written to disk in the POM.
- Success is verified against Runtime Manager (`verify-deployment.sh`), not against the exit code of
  `mule:deploy`.

### Environment promotion

| Environment | Where configured | Automatic? | Who triggers |
| --- | --- | --- | --- |
| Sandbox | `Sandbox` GitHub Environment in the app repository | yes, on `develop` push | CI |
| qa, uat, prod | GitHub Environments in the framework repository, with required reviewers | no | `mule-cd.yml` (manual) |

`mule-cd.yml` accepts only `qa`, `uat` or `prod`, requires an immutable `X.Y.Z` version, rejects
dev versions, and requires the expected SHA-256. It has no push trigger.

## Failure handling

- Any failing job stops the run; downstream jobs are skipped. Publication never runs before validation,
  tests and packaging succeed. Deployment never runs before publication succeeds.
- A release version that already exists in Exchange fails the release run; it is not treated as success.
- A SHA-256 mismatch between the expected value and the downloaded Exchange JAR stops deployment.
- Missing or invalid configuration is reported by `validate-config.sh` with the variable name.

## Key decisions

| Decision | Reason |
| --- | --- |
| Reusable workflows in a framework repository | One place for logic; applications only carry a short caller |
| Two reusable files (`reusable-mule-ci.yml`, `reusable-mule-deploy.yml`) | The deploy job is also used by manual CD, so it lives in one place |
| No `pull_request_target` | It would run untrusted PR code with secrets |
| Dev versions are unique per run | Exchange rejects re-publishing a fixed snapshot coordinate |
| Deploy the Exchange copy, not a rebuild | Makes the deployed binary the published one |
| Sandbox is the only auto-deploy target | Higher environments need explicit approval |
| Username/password support alongside connected app | Requested; see caveats in [setup.md](setup.md#anypoint-authentication) |
| No security or code scanning jobs | Out of scope for this iteration by request |

## Versions and sources (verified at implementation time)

| Component | Version | Source checked |
| --- | --- | --- |
| Mule Maven Plugin | 4.10.3 | `https://repository.mulesoft.org/nexus/content/repositories/releases/org/mule/tools/maven/mule-maven-plugin/` (metadata latest/release) |
| Mule runtime | 4.10.3 (`app.runtime` in smoke-test POM) | MuleSoft repository metadata for `mule-runtime-bom` |
| MUnit runner and Maven plugin | 3.7.5 | MuleSoft repository metadata |
| Java | 17 | Mule 4.10 runtime requirement; the build failed with a Java 17 error message until `javaSpecificationVersions` was set |
| Mule Maven Plugin CloudHub 2.0 config | `<cloudhub2Deployment>` | https://docs.mulesoft.com/mule-runtime/latest/deploy-to-cloudhub-2 |
| Exchange publishing | classifier `mule-application`, distributionManagement URL | https://docs.mulesoft.com/exchange/to-publish-assets-maven |
| GitHub Actions artifacts | `actions/upload-artifact@v4`, `actions/download-artifact` not used | https://github.com/actions/upload-artifact |

Documentation examples used an older plugin version (3.7.x) and runtime (4.6.0). The current
MuleSoft repository lists 4.10.3, and that is what this framework pins.
