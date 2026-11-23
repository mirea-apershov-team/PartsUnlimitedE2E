# Coursework CI

This fork retains the original Microsoft ASP.NET application and its tests.
The website targets .NET Framework 4.5.1, and its unit tests target 4.5.2.

The `PartsUnlimited CI` workflow runs automatically on pushes to `master` or
`main`, and can also be started manually.

- A GitHub-hosted Windows 2022 runner restores the original pinned dependencies,
  obtains the legacy reference assemblies, builds and publishes the website,
  and executes the original MSTest unit tests. Zero executed tests fail CI.
- The published website and test results are uploaded as build artifacts with
  three-day retention. Publishing these files does not deploy or start IIS.
- A separate, restricted Linux ARM64 self-hosted runner downloads and verifies
  the published files. It does not check out or execute the repository code.
- The self-hosted job accepts only trusted default-branch pushes or manual runs.
  Pull requests do not trigger this workflow. Actions are pinned to commit IDs,
  and workflow permissions are read-only.

The separate Selenium project needs an external browser and deployed website;
it is not part of this unit-test build. The inherited dependencies are obsolete
and this coursework configuration is not a production deployment template.
