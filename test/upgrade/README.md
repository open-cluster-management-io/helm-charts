# Upgrade test

Installs an OCM release, upgrades to ocm `main` (`latest` images), then downgrades back to the release.
After every step it checks that:

- every OCM Deployment runs the expected image tag and has finished rolling out
- `ClusterManager` and `Klusterlet` report `Applied`
- `ManagedCluster` `cluster1` is `Available`
- an existing `ManifestWork` still applies an update (`Applied` for the new generation)

One kind cluster acts as both hub and managed cluster.

| Flow | Install and upgrade | Klusterlet mode |
|---|---|---|
| `helm.sh` | `helm upgrade --install` with the release charts and the charts on ocm `main` | Singleton |
| `clusteradm.sh` | `clusteradm init/join`, then `clusteradm upgrade --bundle-version` | Default |

The workflow is [`.github/workflows/upgrade-test.yml`](../../.github/workflows/upgrade-test.yml).
It runs nightly and on demand.

## Run locally

Needs docker, kind, kubectl and helm.

```sh
export KUBECONFIG=$(mktemp)    # keeps your own kubeconfig untouched
export RELEASE=1.4.0

# Helm flow
mkdir -p /tmp/ocm-charts/release /tmp/ocm-charts/main
gh release download v$RELEASE --repo open-cluster-management-io/ocm -D /tmp/ocm-charts/release \
  --pattern "cluster-manager-$RELEASE.tgz" --pattern "klusterlet-$RELEASE.tgz"
git clone --depth 1 https://github.com/open-cluster-management-io/ocm /tmp/ocm-charts/main
RELEASE_CHARTS=/tmp/ocm-charts/release MAIN_CHARTS=/tmp/ocm-charts/main test/upgrade/helm.sh

# clusteradm flow (clusteradm $RELEASE on PATH)
test/upgrade/clusteradm.sh
```

After a failure, `test/upgrade/collect.sh <dir>` saves resources, events and pod logs.
