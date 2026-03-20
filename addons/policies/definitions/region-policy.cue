package main

"region": {
	annotations: {}
	labels: {}
	attributes: {
		scope: "Application"
	}
	description: "Sets the region property on every component in the application."
	type:        "policy"
}

template: {
	output: {
		components: [
			for c in context.appComponents {
				c & {
					properties: region: parameter.region
				}
			},
		]
	}

	parameter: {
		region: string
	}
}
