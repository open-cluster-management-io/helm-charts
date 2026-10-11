#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# Helm flow: install the release charts, upgrade to the charts on ocm main (images :latest),
# then downgrade back to the release charts. One kind cluster is both hub and managed cluster.
# MODE is a klusterlet setup of the ocm e2e jobs: Default, Singleton or grpc (Default klusterlet
# registering through the hub gRPC server).
#
#   MODE=Singleton RELEASE=1.4.0 RELEASE_CHARTS=<dir with cluster-manager-1.4.0.tgz and klusterlet-1.4.0.tgz> \
#   MAIN_CHARTS=<ocm checkout> test/upgrade-downgrade/helm.sh
set -euo pipefail
MODE=${MODE:-Default}
source "$(dirname "$0")/lib.sh"

: "${RELEASE:?set RELEASE, e.g. 1.4.0}"
: "${RELEASE_CHARTS:?set RELEASE_CHARTS}"
: "${MAIN_CHARTS:?set MAIN_CHARTS}"
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
NS=open-cluster-management

# Hub and klusterlet values per mode, the same as deploy-hub-helm and deploy-spoke-operator-helm
# in ocm test/e2e-test.mk.
hub_values=(--set replicaCount=1)
klusterlet_values=(--set-file bootstrapHubKubeConfig="$WORK_DIR/hub-kubeconfig" --set klusterlet.clusterName="$MANAGED_CLUSTER")
case $MODE in
  Default | Singleton)
    klusterlet_values+=(--set klusterlet.mode="$MODE") ;;
  grpc)
    hub_values+=(--set createBootstrapSA=true
      --set 'clusterManager.registrationConfiguration.registrationDrivers[0].authType=csr'
      --set 'clusterManager.registrationConfiguration.registrationDrivers[1].authType=grpc'
      --set 'clusterManager.serverConfiguration.endpointsExposure[0].protocol=grpc'
      --set 'clusterManager.serverConfiguration.endpointsExposure[0].grpc.type=hostname'
      --set 'clusterManager.serverConfiguration.endpointsExposure[0].grpc.hostname.host=cluster-manager-grpc-server.open-cluster-management-hub.svc')
    klusterlet_values+=(--set klusterlet.mode=Default --set-file grpcConfig="$WORK_DIR/grpc-config"
      --set klusterlet.registrationConfiguration.registrationDriver.authType=grpc) ;;
  *) echo "unknown MODE $MODE" >&2; exit 1 ;;
esac

# Values are passed on every upgrade with --reset-values, so nothing is carried over from the
# previous release (helm upgrade reuses old values when none are given).
deploy_hub() { # deploy_hub <cluster-manager chart>
  helm upgrade --install cluster-manager "$1" --namespace "$NS" --create-namespace --reset-values \
    "${hub_values[@]}" >/dev/null
}

deploy_klusterlet() { # deploy_klusterlet <klusterlet chart>
  helm upgrade --install klusterlet "$1" --namespace "$NS" --create-namespace --reset-values \
    "${klusterlet_values[@]}" >/dev/null
}

deploy() { # deploy <cluster-manager chart> <klusterlet chart>
  deploy_hub "$1"
  deploy_klusterlet "$2"
}

# grpc-config in ocm test/e2e-test.mk: the hub CA, a bootstrap token and the gRPC server address.
write_grpc_config() {
  wait_for "gRPC server Deployment exists" ok bash -c \
    'kubectl -n open-cluster-management-hub get deploy cluster-manager-grpc-server >/dev/null && echo ok'
  kubectl -n open-cluster-management-hub wait --for=condition=available --timeout=300s deploy/cluster-manager-grpc-server >/dev/null
  {
    echo "caData: $(kubectl -n open-cluster-management-hub get configmap ca-bundle-configmap -o jsonpath='{.data.ca-bundle\.crt}' | base64 | tr -d '\n')"
    echo "token: $(kubectl -n "$NS" create token agent-registration-bootstrap --duration=24h)"
    echo "url: cluster-manager-grpc-server.open-cluster-management-hub.svc:8090"
  } > "$WORK_DIR/grpc-config"
}

# Accept the cluster as an admin or clusteradm accept would: once the ManagedCluster shows up on
# the hub, approve its CSR and set hubAcceptsClient. Approving the CSR before the ManagedCluster
# exists can end the agent's bootstrap without the ManagedCluster ever being created (seen once
# in 180 soak jobs, when the hub webhook was not ready for the agent's first create).
accept_cluster() {
  wait_for "ManagedCluster $MANAGED_CLUSTER created by the agent" "$MANAGED_CLUSTER" \
    kubectl get managedcluster "$MANAGED_CLUSTER" -o jsonpath='{.metadata.name}'
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

step setup "create kind cluster"
create_cluster
pull_images "v$RELEASE" latest

# The klusterlet reaches the hub through the in-cluster service address.
kubectl config view --minify --flatten > "$WORK_DIR/hub-kubeconfig"
kubectl config set "clusters.kind-$CLUSTER_NAME.server" \
  "https://$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')" \
  --kubeconfig "$WORK_DIR/hub-kubeconfig" >/dev/null

step install "install release $RELEASE"
deploy_hub "$release_cm"
[ "$MODE" != grpc ] || write_grpc_config
deploy_klusterlet "$release_kl"
accept_cluster
wait_ready "v$RELEASE"
apply_work release
report

step upgrade "upgrade to main"
deploy "$main_cm" "$main_kl"
wait_ready latest
apply_work main
report

step downgrade "downgrade to release $RELEASE"
deploy "$release_cm" "$release_kl"
wait_ready "v$RELEASE"
apply_work downgraded
report

