#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# Helm flow: install the release charts, upgrade to the charts on ocm main (images :latest),
# then downgrade back to the release charts. One kind cluster is both hub and managed cluster.
#
#   RELEASE=1.4.0 RELEASE_CHARTS=<dir with cluster-manager-1.4.0.tgz and klusterlet-1.4.0.tgz> \
#   MAIN_CHARTS=<ocm checkout> test/upgrade/helm.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${RELEASE:?set RELEASE, e.g. 1.4.0}"
: "${RELEASE_CHARTS:?set RELEASE_CHARTS}"
: "${MAIN_CHARTS:?set MAIN_CHARTS}"
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
NS=open-cluster-management

# Values are passed on every upgrade with --reset-values, so nothing is carried over from the
# previous release (helm upgrade reuses old values when none are given).
deploy() { # deploy <cluster-manager chart> <klusterlet chart>
  helm upgrade --install cluster-manager "$1" --namespace "$NS" --create-namespace --reset-values \
    --set replicaCount=1 >/dev/null
  helm upgrade --install klusterlet "$2" --namespace "$NS" --create-namespace --reset-values \
    --set-file bootstrapHubKubeConfig="$WORK_DIR/hub-kubeconfig" \
    --set klusterlet.clusterName="$MANAGED_CLUSTER" >/dev/null
}

# Approve the klusterlet CSRs and accept the cluster, as clusteradm accept does.
accept_cluster() {
  for _ in $(seq 60); do
    kubectl get csr -l open-cluster-management.io/cluster-name="$MANAGED_CLUSTER" -o name \
      | xargs -r kubectl certificate approve >/dev/null 2>&1 || true
    kubectl patch managedcluster "$MANAGED_CLUSTER" --type=merge \
      -p '{"spec":{"hubAcceptsClient":true}}' >/dev/null 2>&1 || true
    if [ "$(condition ManagedClusterConditionAvailable "managedcluster/$MANAGED_CLUSTER" 2>/dev/null)" = True ]; then
      echo "ok: $MANAGED_CLUSTER accepted"
      return 0
    fi
    sleep 5
  done
  echo "FAIL: $MANAGED_CLUSTER was not accepted" >&2
  return 1
}

release_cm=$RELEASE_CHARTS/cluster-manager-$RELEASE.tgz
release_kl=$RELEASE_CHARTS/klusterlet-$RELEASE.tgz
main_cm=$MAIN_CHARTS/deploy/cluster-manager/chart/cluster-manager
main_kl=$MAIN_CHARTS/deploy/klusterlet/chart/klusterlet

summary_start "Upgrade test (helm): release $RELEASE → main → release $RELEASE"
step "create kind cluster"
create_cluster
pull_images "v$RELEASE" latest

# The klusterlet reaches the hub through the in-cluster service address.
kubectl config view --minify --flatten > "$WORK_DIR/hub-kubeconfig"
kubectl config set "clusters.kind-$CLUSTER_NAME.server" \
  "https://$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')" \
  --kubeconfig "$WORK_DIR/hub-kubeconfig" >/dev/null

step "install release $RELEASE"
deploy "$release_cm" "$release_kl"
accept_cluster
wait_ready "v$RELEASE"
apply_work release
report

step "upgrade to main"
deploy "$main_cm" "$main_kl"
wait_ready latest
apply_work main
report

step "downgrade to release $RELEASE"
deploy "$release_cm" "$release_kl"
wait_ready "v$RELEASE"
apply_work downgraded
report

