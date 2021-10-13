#! /bin/bash
# source setup_kubeconfig.sh
source helper.sh

# setting up gossip encryption
if [ ! -s gossipEncryptionKey ]; then
    consul keygen > gossipEncryptionKey
fi
LICENSE_PATH=$HOME/licenses/consul_v2lic.hclic

CONSUL_HELM_VERSION=0.33.0
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

c1_kctx
kubectl create secret generic consul-gossipencryptionkey --from-file=key=gossipEncryptionKey
kubectl create secret generic consul-license \
    --from-file=license=$LICENSE_PATH

if helm status consul 2>&1 1>/dev/null; then
helm upgrade consul hashicorp/consul -f values1_consul.yaml \
    --set global.datacenter=cluster-1 \
    --version $CONSUL_HELM_VERSION \
    --wait
else
helm install consul hashicorp/consul -f values1_consul.yaml \
    --set global.datacenter=cluster-1 \
    --version $CONSUL_HELM_VERSION \
    --wait
fi
kubectl wait --for=condition=available --timeout=5m deployment.apps/consul-mesh-gateway

kubectl get secret consul-federation -o yaml > consul-federation-secret.yaml
kubectl get secrets consul-acl-replication-acl-token -o yaml > consul-acl-replication-acl-token.yaml
echo ".: waiting for Cluster-1 IP address"
while ! kubectl get svc consul-ui -o jsonpath={..ip} --allow-missing-template-keys=false 2>/dev/null; do
    sleep 5
done
echo ""

c2_kctx
kubectl create secret generic consul-gossipencryptionkey --from-file=key=gossipEncryptionKey
kubectl create secret generic consul-license \
    --from-file=license=$LICENSE_PATH

if helm status consul 2>&1 1>/dev/null; then
helm upgrade consul hashicorp/consul -f values2_consul.yaml \
    --set global.datacenter=cluster-2 \
    --version $CONSUL_HELM_VERSION \
    --wait
else
kubectl delete -f consul-federation-secret.yaml
kubectl apply -f consul-federation-secret.yaml
kubectl delete -f consul-acl-replication-acl-token.yaml
kubectl apply -f consul-acl-replication-acl-token.yaml

helm install consul hashicorp/consul -f values2_consul.yaml \
    --set global.datacenter=cluster-2 \
    --version $CONSUL_HELM_VERSION \
    --wait
fi
kubectl wait --for=condition=available --timeout=1m deployment.apps/consul-mesh-gateway
echo ".: waiting for Cluster-2 IP address"
while ! kubectl get svc consul-ui -o jsonpath={..ip} --allow-missing-template-keys=false 2>/dev/null; do
    sleep 5
done
echo ""

setup-consul 2>&1 1>/dev/null

detect_endpoints;
c1_kctx;
