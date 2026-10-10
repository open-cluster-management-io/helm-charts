#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# clusteradm flow: init and join with the release bundle, upgrade to the latest bundle (images
# built from ocm main), then downgrade back to the release bundle. One kind cluster is both hub
# and managed cluster. Needs a clusteradm binary that knows both bundles.
#
#   RELEASE=1.4.0 test/upgrade/clusteradm.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${RELEASE:?set RELEASE, e.g. 1.4.0}"
CLUSTERADM=${CLUSTERADM:-clusteradm}

upgrade() { # upgrade <bundle version>
  "$CLUSTERADM" upgrade clustermanager --bundle-version "$1" --wait >/dev/null
  "$CLUSTERADM" upgrade klusterlet --bundle-version "$1" --wait >/dev/null
}

summary_start "Upgrade test (clusteradm): release $RELEASE → main → release $RELEASE"
step "create kind cluster"
create_cluster
pull_images "v$RELEASE" latest
"$CLUSTERADM" version 2>&1 | grep -i client || true

step "init, join and accept with bundle $RELEASE"
"$CLUSTERADM" init --bundle-version "$RELEASE" --wait >/dev/null
token=$("$CLUSTERADM" get token | grep -o 'hub-token [^ ]*' | awk '{print $2}')
apiserver=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
"$CLUSTERADM" join --hub-token "$token" --hub-apiserver "$apiserver" --cluster-name "$MANAGED_CLUSTER" \
  --bundle-version "$RELEASE" --force-internal-endpoint-lookup --wait >/dev/null
"$CLUSTERADM" accept --clusters "$MANAGED_CLUSTER" --wait >/dev/null
wait_ready "v$RELEASE"
apply_work release
report

step "upgrade to bundle latest"
upgrade latest
wait_ready latest
apply_work main
report

step "downgrade to bundle $RELEASE"
upgrade "$RELEASE"
wait_ready "v$RELEASE"
apply_work downgraded
report

