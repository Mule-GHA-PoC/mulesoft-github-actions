# mulesoft-github-actions

Reusable GitHub Actions CI/CD for MuleSoft Mule 4 applications: validation, MUnit tests, packaging,
GitHub Actions artifacts, Anypoint Exchange publication, Sandbox auto-deploy on `develop`, and a
manual, approval-gated promotion workflow for higher environments.

- Architecture, versioning and job graph: [docs/architecture.md](docs/architecture.md)
- Setup (GitHub CLI, Java, Maven, Anypoint, GitHub variables and secrets): [docs/setup.md](docs/setup.md)
- End-to-end test evidence: [docs/test-report.md](docs/test-report.md)

## What is in this repository

| Path | Purpose |
| --- | --- |
| `.github/workflows/reusable-mule-ci.yml` | Reusable pipeline: validate → test → version → package → publish → deploy |
| `.github/workflows/reusable-mule-deploy.yml` | Reusable deploy-only job: exact Exchange artifact → SHA-256 check → `mule:deploy` → Runtime Manager check |
| `.github/workflows/mule-cd.yml` | Manual (`workflow_dispatch`) promotion to `qa`, `uat` or `prod` |
| `scripts/validate-config.sh` | Fails fast on missing or invalid variables/secrets |
| `scripts/calculate-version.sh` | Deterministic version: `X.Y.Z` for release tags, `X.Y.Z-dev.<run_id>` otherwise |
| `scripts/write-maven-settings.sh` | Writes Maven `settings.xml` referencing env vars (no secret values on disk) |
| `scripts/exchange.sh` | Exchange Maven Facade reads: existence check and exact-artifact download |
| `scripts/verify-artifact.sh` | Confirms a JAR is a real Mule application; writes SHA-256 and `build-metadata.json` |
| `scripts/write-deploy-pom.sh` | Generates the deploy-only POM for CloudHub 2.0 |
| `scripts/verify-deployment.sh` | Polls Runtime Manager until the application is running |

## Onboarding a Mule application

1. Make the app a Mule 4 Maven project whose `pom.xml` `groupId` is the Anypoint organization ID and whose
   `packaging` is `mule-application` (see the smoke-test repository for a working POM).
2. Add a caller workflow (the smoke-test repository has one, `.github/workflows/ci.yml`).
3. Configure the variables and secrets in [docs/setup.md](docs/setup.md) for that repository.

## Reusing the framework

Callers reference `nsripriya731/mulesoft-github-actions/.github/workflows/reusable-mule-ci.yml@main`.
Note that `uses:` cannot contain expressions, and the framework checks itself out at `ref: main`
inside the workflow files. To pin a release, change those refs to a tag in both reusable workflows.
