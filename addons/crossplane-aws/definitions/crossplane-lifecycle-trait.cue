package main

"crossplane-lifecycle": {
	annotations: {}
	labels: {}
	attributes: {
		podDisruptive: false
		appliesToWorkloads: ["autodetects.core.oam.dev"]
	}
	description: "Control the Crossplane deletionPolicy on a provisioned resource. Use 'Orphan' to retain the cloud resource when the KubeVela Application is deleted, or 'Delete' to destroy it."
	type: "trait"
}

template: {
	// +patchStrategy=jsonMergePatch
	patch: {
		spec: deletionPolicy: parameter.policy
	}

	parameter: {
		// +usage=Crossplane deletion policy: Orphan retains the cloud resource after the claim is deleted; Delete removes it
		policy: *"Orphan" | "Delete"
	}
}
