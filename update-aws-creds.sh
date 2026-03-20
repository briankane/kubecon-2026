#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required AWS credentials file
if [ ! -f "${SCRIPT_DIR}/.aws-creds" ]; then
    echo "❌ .aws-creds file not found at ${SCRIPT_DIR}/.aws-creds"
    echo ""
    echo "   Run: atmos use -e scratch-kubecon | grep AWS > .aws-creds"
    exit 1
fi

source "${SCRIPT_DIR}/.aws-creds"

# Build credentials in AWS format
AWS_CREDS_CONTENT="[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}"

if [ ! -z "${AWS_SESSION_TOKEN}" ]; then
    AWS_CREDS_CONTENT="${AWS_CREDS_CONTENT}
aws_session_token = ${AWS_SESSION_TOKEN}"
fi

echo "🔐 Updating AWS credentials secrets..."

kubectl create secret generic aws-creds \
    -n crossplane-system \
    --from-literal=creds="${AWS_CREDS_CONTENT}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aws-creds \
    -n default \
    --from-literal=creds="${AWS_CREDS_CONTENT}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secrets updated"

# Restart Crossplane providers to pick up new credentials
echo "🔄 Restarting Crossplane providers..."
kubectl rollout restart deployment \
    -n crossplane-system \
    -l pkg.crossplane.io/revision 2>/dev/null || true

# Also restart the core crossplane deployment
if kubectl get deployment crossplane -n crossplane-system >/dev/null 2>&1; then
    kubectl rollout restart deployment/crossplane -n crossplane-system
fi

echo "✅ Crossplane providers restarted"

# Restart webservice pods if present
if kubectl get deployment demo-webservice -n default >/dev/null 2>&1; then
    echo "🔄 Restarting demo-webservice..."
    kubectl rollout restart deployment/demo-webservice -n default
    echo "✅ demo-webservice restarted"
fi

echo ""
echo "Done! Crossplane will now reconcile pending deletions."
