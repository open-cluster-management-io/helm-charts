#!/usr/bin/env bash
# Copyright Contributors to the Open Cluster Management project
#
# clusteradm flow: init and join with the release bundle, upgrade to the latest bundle (images
# built from ocm main), then downgrade back to the release bundle. One kind cluster is both hub
# and managed cluster. Needs a clusteradm binary that knows both bundles.
# MODE is a klusterlet setup of the ocm e2e jobs: Default, Singleton or grpc (Default klusterlet
# registering through the hub gRPC server).
#
#   MODE=Default RELEASE=1.4.0 test/upgrade-downgrade/clusteradm.sh
set -euo pipefail
MODE=${MODE:-Default}
source "$(dirname "$0")/lib.sh"

: "${RELEASE:?set RELEASE, e.g. 1.4.0}"
CLUSTERADM=${CLUSTERADM:-clusteradm}
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
GRPC_HOST=cluster-manager-grpc-server.open-cluster-management-hub.svc

init_args=()
join_args=()
case $MODE in
  Default) ;;
  Singleton) join_args+=(--singleton) ;;
  grpc)
    init_args+=(--registration-drivers csr,grpc --grpc-server "$GRPC_HOST")
    join_args+=(--registration-auth grpc --grpc-server "$GRPC_HOST:8090" --grpc-ca-file "$WORK_DIR/grpc-ca.pem") ;;
  *) echo "unknown MODE $MODE" >&2; exit 1 ;;
esac

upgrade() { # upgrade <bundle version>
  "$CLUSTERADM" upgrade clustermanager --bundle-version "$1" --wait >/dev/null
  "$CLUSTERADM" upgrade klusterlet --bundle-version "$1" --wait >/dev/null
}

step setup "create kind cluster"
create_cluster
pull_images "v$RELEASE" latest
"$CLUSTERADM" version 2>&1 | grep -i client || true

step install "init, join and accept with bundle $RELEASE"
"$CLUSTERADM" init --bundle-version "$RELEASE" ${init_args[@]+"${init_args[@]}"} --wait >/dev/null
if [ "$MODE" = grpc ]; then
  wait_for "gRPC server Deployment exists" ok bash -c \
    'kubectl -n open-cluster-management-hub get deploy cluster-manager-grpc-server >/dev/null && echo ok'
  kubectl -n open-cluster-management-hub wait --for=condition=available --timeout=300s deploy/cluster-manager-grpc-server >/dev/null
  kubectl -n open-cluster-management-hub get configmap ca-bundle-configmap -o jsonpath='{.data.ca-bundle\.crt}' \
    > "$WORK_DIR/grpc-ca.pem"
fi
token=$("$CLUSTERADM" get token | grep -o 'hub-token [^ ]*' | awk '{print $2}')
apiserver=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
"$CLUSTERADM" join --hub-token "$token" --hub-apiserver "$apiserver" --cluster-name "$MANAGED_CLUSTER" \
  --bundle-version "$RELEASE" --force-internal-endpoint-lookup ${join_args[@]+"${join_args[@]}"} --wait >/dev/null
"$CLUSTERADM" accept --clusters "$MANAGED_CLUSTER" --wait >/dev/null
wait_ready "v$RELEASE"
apply_work release
report

step upgrade "upgrade to bundle latest"
upgrade latest
wait_ready latest
apply_work main
report

step downgrade "downgrade to bundle $RELEASE"
upgrade "$RELEASE"
wait_ready "v$RELEASE"
apply_work downgraded
report
