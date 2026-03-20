package main

"tenant-context": {
	annotations: {}
	labels: {}
	attributes: {
		scope:  "Application"
		global: true
	}
	description: "Inject tenant name into workflow context for use by components and traits."
	type:        "policy"
}

template: {
	parameter: {}

	output: {
		ctx: {
			tenant: "kubevela"
		}
	}
}
