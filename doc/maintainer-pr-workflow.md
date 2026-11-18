# Maintaining pull requests

## Run the checks

Use the Flutter version and commands in the [contributor guide](../CONTRIBUTING.md) for local feedback. The [CI workflow](../.github/workflows/ci.yml) runs on pull requests and pushes to `main`. It checks changed Dart formatting, analyzes and tests the package and example, reports line coverage, audits the workflow, and verifies the supported Flutter versions and example builds. It reports the aggregate result as **Required checks**. Keep that job name stable and unique so GitHub can associate it with the default-branch rule.

For a pull request from a fork, look for its checks in the base repository. GitHub may ask a maintainer to approve the workflow run, especially for first-time contributors. Review proposed workflow changes before approving the run. Approving a run and approving the pull request are separate actions. The PR workflow uses a read-only token and public dependencies, which also allows Dependabot PRs to run it. [GitHub Actions pull request events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request)

## Enable merge requirements on GitHub

1. Land the CI workflow and open a pull request that reports a successful **Required checks** run. Confirm GitHub Actions is the source of the check.
2. With repository admin access, open **Settings → Rulesets → New ruleset → Import a ruleset** and select [default-branch.json](../.github/rulesets/default-branch.json). Review the imported rules and save with enforcement **Disabled**. The target follows the repository's default branch. If you rename `main`, update the CI branch filters to match.
3. Confirm a second maintainer with write access can approve pull requests. Review the status check source, one required approval, stale approval dismissal, and conversation resolution in the imported ruleset.
4. When the check and approval are available, edit the ruleset and switch enforcement to **Active**. Open or update a test PR and confirm GitHub requires the CI result, a human approval, and resolved conversations before merging.

The JSON in the repository is the import template. The repository settings control enforcement after import. GitHub documents ruleset availability by plan and repository visibility. [GitHub ruleset import and enforcement](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#importing-prebuilt-rulesets)

If **Required checks** is waiting for a status, check that the workflow ran for the current PR commit and that any fork approval is complete. Compare the check name and source with the imported rule. [Troubleshooting required status checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/troubleshooting-rules)

## Optionally install CodeRabbit

A repository admin can connect the repository using the CodeRabbit GitHub App and grant it access to this repository. The [repository config](../.coderabbit.yaml) enables advisory review comments on ready PRs once the app is installed and applies the [project review guidelines](review-guidelines.md). CodeRabbit's automatic approvals and status publishing are disabled. Leave **Required checks** as the CI gate and have a maintainer review the change and resolve review conversations before merging. [CodeRabbit setup](https://docs.coderabbit.ai/getting-started/quickstart)

## Review dependency updates

[Dependabot](../.github/dependabot.yml) checks Pub dependencies in the package and example and action references in GitHub workflows weekly, with a seven-day cooldown for version updates. The config takes effect on the default branch. A fork needs its own explicit opt-in if its owner wants dependency update PRs there. The CodeRabbit GitHub App and repository ruleset can be set up independently. [Dependabot configuration](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-version-updates)

Review dependency PRs like other changes. For updates to Sherpa, verify the format and loading of the pinned Nemotron assets, including the Web worker, with a real Persian sample before merging.
