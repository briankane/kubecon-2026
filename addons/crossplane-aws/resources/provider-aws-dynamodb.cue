package main

providerawsdynamodb: {
    type: "crossplane-provider"
    name: "provider-aws-dynamodb"
    properties: {
        namespace: parameter.namespace
        package:   "xpkg.upbound.io/upbound/provider-aws-dynamodb:" + parameter.awsDynamoDBVersion
        if parameter.irsaEnabled {
            serviceAccountAnnotations: {
                "eks.amazonaws.com/role-arn": parameter.irsaRoleArn
            }
        }
    }
}
