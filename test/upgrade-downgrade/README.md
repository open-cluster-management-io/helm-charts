# Upgrade and downgrade test

Installs an OCM release, upgrades to ocm `main` (`latest` images), then downgrades back to the release.
After every step it checks that:

- every OCM Deployment runs the expected image tag and has finished rolling out
- `ClusterManager` and `Klusterlet` report `Applied`
- `ManagedCluster` `cluster1` is `Available`
- an existing `ManifestWork` still applies an update (`Applied` for the new generation)

One kind cluster acts as both hub and managed cluster.

Not covered:

- The `ClusterManager` and `Klusterlet` CRDs are in the charts' `crds/` folder. Helm installs them once and never upgrades or downgrades them.
- `clusteradm upgrade --bundle-version latest` renders the operator chart built into clusteradm `$RELEASE` with `latest` images. The operator Deployment comes from the release, the hub and agent components from the `latest` operator.

| Script | Install and upgrade |
|---|---|
| `helm.sh` | `helm upgrade --install` with the release charts and the charts on ocm `main` |
| `clusteradm.sh` | `clusteradm init/join`, then `clusteradm upgrade --bundle-version` |

Both take `MODE`: `Default`, `Singleton` or `grpc`, klusterlet setups of the ocm e2e jobs.
`summary.sh` turns the results of all jobs into one table on the run page.

The workflow is [`.github/workflows/upgrade-downgrade-test.yml`](../../.github/workflows/upgrade-downgrade-test.yml).
It runs nightly and on demand.

## Run locally

Needs docker, kind, kubectl, helm, gh and git. Run from the repo root.

```sh
export KUBECONFIG=$(mktemp)    # keeps your own kubeconfig untouched
export RELEASE=1.4.0

# Helm flow
mkdir -p /tmp/ocm-charts/release /tmp/ocm-charts/main
gh release download v$RELEASE --repo open-cluster-management-io/ocm -D /tmp/ocm-charts/release \
  --pattern "cluster-manager-$RELEASE.tgz" --pattern "klusterlet-$RELEASE.tgz"
git clone --depth 1 https://github.com/open-cluster-management-io/ocm /tmp/ocm-charts/main
MODE=Singleton RELEASE_CHARTS=/tmp/ocm-charts/release MAIN_CHARTS=/tmp/ocm-charts/main \
  test/upgrade-downgrade/helm.sh

# clusteradm flow (clusteradm $RELEASE on PATH)
MODE=Default test/upgrade-downgrade/clusteradm.sh
```

After a failure, `test/upgrade-downgrade/collect-debug.sh <dir>` saves resources, events and pod logs.
