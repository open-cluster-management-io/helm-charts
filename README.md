# Open Cluster Management Helm Charts

[![License](https://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![Download Helm Chart](https://github.com/open-cluster-management-io/helm-charts/actions/workflows/download-chart.yml/badge.svg)](https://github.com/open-cluster-management-io/helm-charts/actions/workflows/download-chart.yml)
[![Release Charts](https://github.com/open-cluster-management-io/helm-charts/actions/workflows/chart-release.yml/badge.svg)](https://github.com/open-cluster-management-io/helm-charts/actions/workflows/chart-release.yml)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/ocm-helm-charts)](https://artifacthub.io/packages/search?repo=ocm-helm-charts)

This repository stores and publishes Helm chart packages for Open Cluster Management (OCM) components. OCM is a Kubernetes-native project that provides multi-cluster management capabilities, enabling you to manage multiple clusters from a central hub cluster.

The repository contains Helm charts for various OCM components including:

- **cluster-manager** - The hub cluster controller that manages multiple clusters
- **klusterlet** - The agent component deployed on managed clusters
- **cluster-proxy** - Provides secure connectivity between hub and managed clusters
- **multicluster-controlplane** - Lightweight controlplane for multi-cluster scenarios
- **managed-serviceaccount** - Manages service accounts across clusters
- **argocd-pull-integration** - Integration with ArgoCD for GitOps workflows
- **fleetconfig-controller** - Manages fleet configurations across clusters

The configured workflows automatically sync and index uploaded chart packages to the OCM chart repository.

## Install

```shell
$ helm repo add ocm https://open-cluster-management.io/helm-charts
$ helm repo update
$ helm search repo ocm
```

## Upload

Any file changes in the `main` branch will trigger the workflow
[chart-release.yml](./.github/workflows/chart-release.yml)
to publish all chart packages in the `charts/` folder to the
[gh-pages](https://github.com/open-cluster-management-io/helm-charts/tree/gh-pages)
branch, which serves as the source for the OCM Helm charts repository hosted by
[Netlify](https://ocm-helm-charts.netlify.app/).

User requests from the main documentation site [open-cluster-management.io](https://open-cluster-management.io/) are
redirected here through [Netlify redirects](https://github.com/open-cluster-management-io/open-cluster-management-io.github.io/blob/main/netlify.toml).

### 1. Manual upload via pull request

After forking this repository, you can upload chart packages to your forked
repository either through the GitHub web interface or using git command-line
tools, then open a pull request to merge your changes.

### 2. Automatic upload via GitHub Action

The workflow [download-chart.yml](./.github/workflows/download-chart.yml)
can be invoked from your own repository using the following action step:

```
- name: submit charts to OCM chart repo
  uses: actions/github-script@v6
  with:
    github-token: ${{ secrets.OCM_BOT_PAT }}
    script: |
      try {
        const result = await github.rest.actions.createWorkflowDispatch({
          owner: 'open-cluster-management-io',
          repo: 'helm-charts',
          workflow_id: 'download-chart.yml',
          ref: 'main',
          inputs: {
            # repo is the target repo to download chart package
            repo: "${{ github.repository }}",
            # version is the target release version to download (without "v" prefix)
            version: "${{ env.TRIMED_RELEASE_VERSION }}",
            # chart-name is the name of the chart package, e.g. a chart-name "foo"
            # and version "1.1.1" will trigger the download action to download a
            # file named "foo-1.1.1.tgz" from the corresponding github release.
            "chart-name": "${{ env.CHART_NAME }}",
          },
        })
        console.log(result);
      } catch(error) {
        console.error(error);
        core.setFailed(error);
      }
```

Note: Please verify that your source code repository publishes chart
package tarballs in the release assets. It is recommended to use the
following action to publish charts:

```
- name: publish release
  uses: softprops/action-gh-release@v0.1.5
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    files: |
      # Note: RELEASE_VERSION should not have "v" prefix.
      ${{ env.CHART_NAME }}-${{ env.RELEASE_VERSION }}.tgz
```

## Workflow

![Arch](./static/arch.png)

### Process Description

1. A code repository admin creates a new release tag and pushes it, which triggers the release
   job flow including Docker image build and chart packaging.
2. At the end of the release job, the code repository invokes the chart repository's
   "download-chart.yml" workflow to notify that a new release is available. The released
   chart package should be listed in the GitHub release asset files following the Helm
   chart naming convention: `<chart-name>-<release-version>.tgz`
3. The chart repository downloads the chart package from the code repository's release assets
   and commits it to the "main" branch.
4. A post-commit job in the chart repository named "chart-release.yml" uploads the
   latest artifacts to remote blob storage along with an updated index file.

## Contributing

We welcome contributions to the Open Cluster Management Helm Charts repository! Please read our [Contributing Guide](CONTRIBUTING.md) for information on how to contribute charts and improvements.

All contributors must follow our [Code of Conduct](CODE_OF_CONDUCT.md) to ensure a welcoming and inclusive environment for everyone.

## Community

Open Cluster Management is an active open source project with a growing community. Get involved:

- **Website**: [open-cluster-management.io](https://open-cluster-management.io/)
- **GitHub Organization**: [open-cluster-management-io](https://github.com/open-cluster-management-io)
- **Slack**: Join the [#open-cluster-management](https://kubernetes.slack.com/channels/open-cluster-management) channel on Kubernetes Slack
- **Community Meetings**: Check the [community repository](https://github.com/open-cluster-management-io/community) for meeting schedules and agendas

## Security

Security issues should be reported following our [Security Response Process](SECURITY.md). Please do not file public issues for security vulnerabilities.

## Support

For questions and support:

- **Documentation**: Visit [open-cluster-management.io](https://open-cluster-management.io/) for comprehensive documentation
- **GitHub Issues**: Use the [issue tracker](https://github.com/open-cluster-management-io/helm-charts/issues) for chart-specific issues
- **Community Support**: Ask questions in the Kubernetes Slack #open-cluster-management channel

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
