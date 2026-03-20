#!/bin/bash

set -e

# Parse command line arguments
DEPLOY_WORKFLOW=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy-workflow)
            DEPLOY_WORKFLOW=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--deploy-workflow]"
            exit 1
            ;;
    esac
done

echo "🚀 Installing Kubecon Demo..."

# Get script directory first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required AWS credentials file
if [ ! -f "${SCRIPT_DIR}/.aws-creds" ]; then
    echo "❌ .aws-creds file not found at ${SCRIPT_DIR}/.aws-creds"
    echo ""
    echo "   Please create .aws-creds file with your AWS credentials:"
    echo "   export AWS_ACCESS_KEY_ID=your-access-key"
    echo "   export AWS_SECRET_ACCESS_KEY=your-secret-key"
    echo "   export AWS_SESSION_TOKEN=your-session-token  # (if using temporary credentials)"
    echo ""
    exit 1
fi

echo "✅ Found .aws-creds file"

# Check if vela CLI is available
if ! command -v vela &> /dev/null; then
    echo "❌ vela CLI not found. Please install KubeVela CLI first."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if KubeVela is installed and running
if ! kubectl get deployment kubevela-vela-core -n vela-system >/dev/null 2>&1; then
    echo "📦 KubeVela is not running. Installing KubeVela..."
    vela install
    
    echo "⏳ Waiting for KubeVela to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/kubevela-vela-core -n vela-system
    
    echo "✅ KubeVela installed successfully"
else
    echo "✅ KubeVela is already running"
fi

# Remove webhooks and scale down vela-core (use vela-dev binary instead)
echo "🔧 Removing KubeVela webhooks..."
kubectl delete mutatingwebhookconfiguration kubevela-vela-core-admission --ignore-not-found=true
kubectl delete validatingwebhookconfiguration kubevela-vela-core-admission --ignore-not-found=true

echo "🔧 Scaling down kubevela-vela-core..."
kubectl scale deployment kubevela-vela-core -n vela-system --replicas=0

vela-dev def apply definitions

# Check if ChartMuseum is already running
if ! kubectl get deployment chartmuseum -n vela-system >/dev/null 2>&1; then
    echo "📚 Installing ChartMuseum addon..."
    vela addon enable chartmuseum
    
    echo "⏳ Waiting for ChartMuseum to be ready..."
    sleep 10
else
    echo "✅ ChartMuseum addon already available"
fi

# Kill any existing port forwards on 8081
echo "🔄 Cleaning up any existing port forwards..."
pkill -f "port-forward.*8081" 2>/dev/null || true
sleep 2

# Override env trait
vela-dev def apply definitions/env.cue 

# Start port forwarding in background
echo "🔗 Starting port forwarding for ChartMuseum..."
kubectl port-forward -n vela-system deployment/chartmuseum 8081:8080 --address 0.0.0.0 &
PORT_FORWARD_PID=$!

# Wait for port forward to be ready
sleep 5

# Add ChartMuseum as addon registry
echo "📋 Adding ChartMuseum as addon registry..."
vela addon registry add localcm --type helm --endpoint=http://localhost:8081 || {
    echo "ℹ️  Registry might already exist, continuing..."
}

# Package and push demo-resources addon
echo "📦 Packaging and pushing demo-resources addon..."
cd "${SCRIPT_DIR}/addons"
vela addon push demo-resources localcm

# Package and push crossplane addon  
echo "📦 Packaging and pushing crossplane addon..."
vela addon push crossplane localcm

# Package and push crossplane addon  
echo "📦 Packaging and pushing crossplane-aws addon..."
vela addon push crossplane-aws localcm

# Package and push tenant addon
echo "📦 Packaging and pushing tenant addon..."
vela addon push tenant localcm

# Package and push policies addon
echo "📦 Packaging and pushing policies addon..."
vela addon push policies localcm

cd "${SCRIPT_DIR}"

# Check if vela-workflow is already running
if ! kubectl get deployment vela-workflow -n vela-system >/dev/null 2>&1; then
    echo "🔧 Installing vela-workflow addon..."
    vela addon enable vela-workflow
    
    echo "⏳ Waiting for vela-workflow addon to be ready..."
    sleep 10
else
    echo "✅ vela-workflow addon already available"
fi

# Install demo-resources addon (required for wait-deployment workflow step)
# Do this while registry still points to localhost
echo "📦 Installing demo-resources addon from registry..."
vela addon enable demo-resources --override-definitions

echo "⏳ Waiting for demo-resources addon to be ready..."
sleep 5

echo "📦 Installing policies addon from registry..."
vela addon enable policies --override-definitions

# Install kube-trigger CRD definitions
echo "📦 Installing kube-trigger CRD definitions..."
kubectl apply -f https://raw.githubusercontent.com/kubevela/kube-trigger/main/config/crd/core.oam.dev_definitions.yaml || {
    echo "⚠️  Failed to install kube-trigger CRD, continuing..."
}

# Update registry to use service endpoint for workflow execution
echo "🔄 Updating registry to use service endpoint..."
vela addon registry update localcm --type helm --endpoint=http://chartmuseum.vela-system.svc.cluster.local:8080

# Clean up port forward - no longer needed
echo "🔄 Stopping port forward..."
kill $PORT_FORWARD_PID 2>/dev/null || true

# Delete any existing WorkflowRun to avoid conflicts
echo "🔄 Cleaning up any existing WorkflowRun..."
kubectl delete workflowrun install -n vela-system --ignore-not-found=true

# Apply app ConfigMaps
echo "📦 Applying app ConfigMaps..."
kubectl apply -f "${SCRIPT_DIR}/apps/configmaps/"

# Create AWS credentials secret (required)
echo "🔐 Creating AWS credentials secret..."

# Source the environment variables from .aws-creds
source "${SCRIPT_DIR}/.aws-creds"


# Build the credentials in AWS format
AWS_CREDS_CONTENT="[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}"

# Add session token if it exists
if [ ! -z "${AWS_SESSION_TOKEN}" ]; then
    AWS_CREDS_CONTENT="${AWS_CREDS_CONTENT}
aws_session_token = ${AWS_SESSION_TOKEN}"
fi

# Create namespaces and secrets with literal value
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic aws-creds \
    -n crossplane-system \
    --from-literal=creds="${AWS_CREDS_CONTENT}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Also create the secret in default namespace for webservice
kubectl create secret generic aws-creds \
    -n default \
    --from-literal=creds="${AWS_CREDS_CONTENT}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Validate the secrets were created
if kubectl get secret aws-creds -n crossplane-system >/dev/null 2>&1 && kubectl get secret aws-creds -n default >/dev/null 2>&1; then
    echo "✅ AWS credentials secrets created successfully in both namespaces"
else
    echo "❌ Failed to create AWS credentials secret"
    exit 1
fi

# Apply the workflow (which will install crossplane addon)
if [ "$DEPLOY_WORKFLOW" = true ]; then
    echo "📋 Applying workflow: install..."
    kubectl apply -f "${SCRIPT_DIR}/workflows/install.yaml"

    echo "⏳ Waiting for workflow to start..."
    sleep 2

    # Validate workflow was created
    echo "⏳ Validating WorkflowRun was created..."
    if ! kubectl get workflowrun install -n vela-system >/dev/null 2>&1; then
        echo "❌ WorkflowRun 'install' was not created"
        exit 1
    fi

    echo "✅ WorkflowRun created successfully"

    # Show workflow status
    echo "📊 You can monitor progress with:"
    echo "   vela workflow logs install -n vela-system"
    echo "   kubectl get workflowrun install -n vela-system"
else
    echo ""
    echo "⏭️  Skipping workflow deployment (use --deploy-workflow flag to enable)"
    echo ""
    echo "📋 To deploy the workflow manually, run:"
    echo "   kubectl apply -f ${SCRIPT_DIR}/workflows/install.yaml"
    echo ""
    echo "   Then monitor progress with:"
    echo "   vela workflow logs install -n vela-system"
    echo "   kubectl get workflowrun install -n vela-system"
fi
echo ""