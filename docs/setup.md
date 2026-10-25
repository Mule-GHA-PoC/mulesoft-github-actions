# Setup

## Prerequisites

| Tool | Version used | Notes |
| --- | --- | --- |
| GitHub CLI (`gh`) | 2.x | `gh auth login` as the account that owns the repositories |
| Git | 2.40+ | |
| Java | 17 (Temurin) | Mule 4.10 runtime requires 17 for the application |
| Maven | 3.9+ | Use a Java 17 `JAVA_HOME` when building locally |

Local build with Java 17 on macOS:

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
mvn -B clean verify
```

## GitHub account and repositories

```bash
gh auth status            # confirm the active account
gh repo create <owner>/mulesoft-github-actions --public
gh repo create <owner>/<app-repo> --public
```

Commits in this project are authored with the repository-local identity `nsripriya731` (set with
`git config user.name` and `git config user.email` inside each repository, not globally).

## Anypoint authentication

The framework supports two modes. It uses connected app credentials when both are set, otherwise
username and password.

| Mode | Secrets | Recommended? |
| --- | --- | --- |
| Connected app (client credentials) | `ANYPOINT_CLIENT_ID`, `ANYPOINT_CLIENT_SECRET` | Yes for shared automation |
| Username and password | `ANYPOINT_USERNAME`, `ANYPOINT_PASSWORD` | Acceptable for a trial or a dedicated service user |

Caveats for username and password:

- The account's password is stored as a GitHub secret and is used by every run.
- It fails if the account requires MFA or SSO-only login. Use a dedicated service account in that case.
- The account needs the Exchange and Runtime Manager permissions described below; over-broad roles increase blast radius.
- Rotate the password by updating the secret; nothing else changes.

Connected app permissions (Anypoint Access Management, Connected Apps):

- Exchange: publish assets (Exchange contributor for the business group).
- Runtime Manager / CloudHub 2.0: deploy and read applications in the target environment.
- Business group and environment access for the Sandbox environment.

Set secrets with the GitHub CLI and enter values at the prompt. Do not put values on the command line:

```bash
gh secret set ANYPOINT_USERNAME --repo <owner>/<app-repo>
gh secret set ANYPOINT_PASSWORD --repo <owner>/<app-repo>
# or
gh secret set ANYPOINT_CLIENT_ID --repo <owner>/<app-repo>
gh secret set ANYPOINT_CLIENT_SECRET --repo <owner>/<app-repo>
```

## Repository variables and the Sandbox environment

Non-secret settings are variables. Set them on the application repository or on the `Sandbox`
environment. See [github-configuration.md](github-configuration.md) for the full list.

```bash
gh variable set ANYPOINT_ORG_ID --repo <owner>/<app-repo> --body "<organization-id>"
gh variable set ANYPOINT_ENVIRONMENT --repo <owner>/<app-repo> --body "Sandbox"
gh variable set ANYPOINT_DEPLOYMENT_TARGET --repo <owner>/<app-repo> --body "<target-name>"
gh variable set MULE_RUNTIME_VERSION --repo <owner>/<app-repo> --body "<runtime-version>"
```

Create the `Sandbox` environment (no protection rules are needed for automatic Sandbox deploys):

```bash
gh api --method PUT "repos/<owner>/<app-repo>/environments/Sandbox"
```

## Exchange publication

- `groupId` in the POM equals the Anypoint organization ID.
- The POM declares `distributionManagement` with the repository id `Repository`; the workflow writes a
  matching Maven server entry at run time.
- The Maven Facade URL is
  `https://maven.anypoint.mulesoft.com/api/v3/organizations/<ORG_ID>/maven`. For EU control planes use
  `maven.eu1.anypoint.mulesoft.com` (set `EXCHANGE_MAVEN_HOST` in a fork of `scripts/exchange.sh`).

## Branch protection (PR checks)

Require these status checks on `develop` and `main` (names are `<caller job> / <reusable job>`):

- `pr-checks / 1 Validate configuration`
- `pr-checks / 2 Unit tests (MUnit)`
- `pr-checks / 3 Calculate version`
- `pr-checks / 4 Package and verify artifact`

Pull request runs never receive secrets, so publish and deploy jobs are skipped.

## Higher environments (qa, uat, prod)

Create these environments in the framework repository only when you are ready to use them. Each
should have required reviewers. Add environment variables and secrets there. This setup does not
create or populate them, and the test in this project never runs `mule-cd.yml`.

```bash
gh api --method PUT "repos/Mule-GHA-PoC/mulesoft-github-actions/environments/prod"
```
