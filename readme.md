# Create Credentials

`atmos use -e scratch-kubecon | grep AWS > .aws-creds`

# Run a local cluster

`k3d cluster create kubecon-demo`

# Run install.sh

`./install.sh --deploy-workflow`

# Wait for all addons

The last to install will be crossplane-aws

# Run the app

kubectl apply -f apps/webservice-s3-app.yaml