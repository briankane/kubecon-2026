package main

"s3-versioning": {
	annotations: {}
	labels: {}
	attributes: {
		appliesToWorkloads: ["*"]
	}
	description: "Enable versioning for S3 bucket"
	type:        "trait"
}

template: {
	// +patchStrategy=jsonMergePatch
	patch: {
		spec: forProvider: versioning: [{
			enabled: parameter.enabled
		}]
	}

	parameter: {
		// Enable or disable versioning
		enabled: bool | *true
	}
}