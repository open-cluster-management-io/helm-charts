[comment]: # ( Copyright Contributors to the Open Cluster Management project )**Table of Contents**

- [Contributing guidelines](#contributing-guidelines)
    - [Terms](#terms)
    - [Certificate of Origin](#certificate-of-origin)
    - [Contributing a patch](#contributing-a-patch)
    - [Issue and pull request management](#issue-and-pull-request-management)
    - [Requirements](#requirements)
    - [Develop new commands](#Develop-new-commands)

# Contributing guidelines

## Terms

All contributions to the repository must be submitted under the terms of the [Apache Public License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Certificate of Origin

By contributing to this project, you agree to the Developer Certificate of Origin (DCO). This document was created by the Linux Kernel community and is a simple statement that you, as a contributor, have the legal right to make the contribution. See the [DCO](DCO) file for details.

## Contributing a patch

1. Submit an issue describing your proposed change to the repository in question. The repository owners will respond to your issue promptly.
2. Fork the desired repository, then develop and test your code changes.
3. Submit a pull request.

## Issue and pull request management

Anyone can comment on issues and submit reviews for pull requests. In order to be assigned an issue or pull request, you can leave a `/assign <your Github ID>` comment on the issue or pull request.
# Requirements for Chart Contributors

- Helm 3.x
- Understanding of Kubernetes and Helm chart development
- Chart packages must follow Helm best practices

## Chart Development Guidelines

All Helm charts in this repository should follow these guidelines:

- Follow Helm chart naming conventions
- Include proper versioning using semantic versioning
- Provide comprehensive values.yaml with sensible defaults
- Include proper chart documentation (README.md, NOTES.txt)
- Follow Kubernetes resource naming conventions
- Include appropriate labels and annotations

## Chart Testing

Before submitting charts:

- Test chart installation and upgrades using `helm install` and `helm upgrade`
- Validate chart templates using `helm template`
- Lint charts using `helm lint`
- Test with different values configurations

## Submitting Charts

When submitting new charts or updates:

1. Package your chart using `helm package`
2. Place the packaged chart (.tgz file) in the `charts/` directory
3. Follow the naming convention: `<chart-name>-<version>.tgz`
4. Submit a pull request with your changes

## Automated Testing

- Chart validation is performed automatically on pull requests
- Charts are tested for proper formatting and structure
- Release workflows automatically publish approved charts to the repository