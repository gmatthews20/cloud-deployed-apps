#!/bin/bash

set -euo pipefail

if [ -z "$1" ]; then
  echo "Please provide the cluster name as an argument."
  echo "Usage: $0 <cluster-name>"
  exit 1
fi


CLUSTER_NAME=$1
ARGOCD_NAMESPACE="argocd"

echo "Adding the ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm

echo "Installing ArgoCD on cluster $CLUSTER_NAME using Helm..."
helm upgrade --install argocd argo/argo-cd \
  --create-namespace \
  --namespace $ARGOCD_NAMESPACE \
  --wait

echo "Waiting for ArgoCD to be ready..."
while ! kubectl get pods -n $ARGOCD_NAMESPACE -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; do
  sleep 5
done

# Get the initial admin password
ARGOCD_PWD=$(kubectl -n $ARGOCD_NAMESPACE get secrets argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "THIS IS THE ARGOCD PASSWORD - CHANGE IT AFTER CREATION $ARGOCD_PWD"

if [ ! -f /usr/local/bin/argocd ]; then
  echo "Installing ArgoCD CLI..."
  curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
  rm argocd-linux-amd64
fi

echo "Creating App of Apps for cluster $CLUSTER_NAME..."
helm upgrade --install argocd-self-app ../charts/argocd -n argocd -f ../charts/argocd/values.yaml -f ../clusters/$CLUSTER_NAME/argocd-values.yaml  --wait
helm upgrade --install argocd-apps ../charts/base-apps -n argocd -f ../charts/argocd-apps/values.yaml -f ../clusters/$CLUSTER_NAME/app-values.yaml --wait

if [ -f "../cluster/$CLUSTER_NAME/infra-values.yaml" ]; then
  helm upgrade --install argocd-infra ../charts/base-infra -n argocd -f ../charts/base-infra/values.yaml -f ../clusters/$CLUSTER_NAME/infra-values.yaml  --wait
fi

echo "ArgoCD installation and configuration completed for cluster $CLUSTER_NAME."
