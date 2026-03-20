package main

"dynamodb-table": {
	annotations: {}
	labels: {}
	attributes: {
		workload: definition: {
			apiVersion: "dynamodb.aws.upbound.io/v1beta1"
			kind:       "Table"
		}
		status: {
			healthPolicy: {
				isHealth: context.output.status.atProvider.arn != _|_
			}
			details: {
				tableArn:    context.output.status.atProvider.arn
				tableName:   context.output.status.atProvider.id
				tableStatus: context.output.status.atProvider.tableStatus
			}
			customStatus: {
				message: *"Synced: \(context.output.status.atProvider.arn)" | "Syncing DynamoDB Table"
			}
		}
	}
	description: "AWS DynamoDB Table managed by Crossplane"
	type:        "component"
}

template: {
	output: {
		apiVersion: "dynamodb.aws.upbound.io/v1beta1"
		kind:       "Table"
		metadata: {
			if context.custom.tenant != _|_ {
				name: "\(context.custom.tenant)-\(context.appName)-\(context.name)-\(parameter.region)"
			}
			if context.custom.tenant == _|_ {
				name: "\(context.appName)-\(context.name)-\(parameter.region)"
			}
		}
		spec: {
			forProvider: {
				region:      parameter.region
				billingMode: parameter.billingMode
				attribute: [
					{
						name: parameter.hashKeyName
						type: parameter.hashKeyType
					},
				]
				hashKey: parameter.hashKeyName
				tags: {
					"crossplane-kind":           "table.dynamodb.aws.upbound.io"
					"crossplane-name":           context.name
					"crossplane-providerconfig": parameter.providerConfigRef
					"managed-by":                "crossplane"
					if context.custom.tenant != _|_ {
						"tenant": context.custom.tenant
					}
				}
			}
			deletionPolicy: "Delete"
			providerConfigRef: {
				name: parameter.providerConfigRef
			}
		}
	}

	parameter: {
		// Required: AWS region for the table
		region: string

		// Billing mode: PAY_PER_REQUEST (on-demand) or PROVISIONED
		billingMode: *"PAY_PER_REQUEST" | "PROVISIONED"

		// Name of the partition key attribute
		hashKeyName: *"id" | string

		// Data type of the partition key: S (String), N (Number), B (Binary)
		hashKeyType: *"S" | "N" | "B"

		// Provider configuration reference
		providerConfigRef: string | *"default"
	}
}
