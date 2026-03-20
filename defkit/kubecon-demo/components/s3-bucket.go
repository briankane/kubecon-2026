/*
Copyright 2026 The KubeVela Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package components

import (
	"github.com/oam-dev/kubevela/pkg/definition/defkit"
)

func init() {
	defkit.Register(S3Bucket())
}

// S3Bucket creates the s3-bucket component definition.
func S3Bucket() *defkit.ComponentDefinition {
	vela := defkit.VelaCtx()

	region := defkit.String("region").
		Description("AWS region for the bucket (immutable)")

	bucketName := defkit.String("bucketName").
		Description("Optional bucket name prefix (immutable)").
		Optional()

	providerConfigRef := defkit.String("providerConfigRef").
		Description("Provider configuration reference").
		Default("default")

	return defkit.NewComponent("s3-bucket").
		Description("AWS S3 Bucket managed by Crossplane").
		Workload("s3.aws.upbound.io/v1beta2", "Bucket").
		Params(region, bucketName, providerConfigRef).
		HealthPolicyExpr(
			defkit.Health().Exists("status.atProvider.arn"),
		).
		StatusDetails(`
            bucketName:               context.output.status.atProvider.id
            bucketArn:                context.output.status.atProvider.arn
            region:                   context.output.status.atProvider.region
            hostedZoneId:             context.output.status.atProvider.hostedZoneId
            bucketDomainName:         context.output.status.atProvider.bucketDomainName
            bucketRegionalDomainName: context.output.status.atProvider.bucketRegionalDomainName
            syncStatus:               context.output.status.conditions[0].type
            syncReason:               context.output.status.conditions[0].reason
            lastModified:             context.output.status.conditions[0].lastTransitionTime
        `).
		CustomStatus(defkit.CustomStatusExpr(
			defkit.Status().Switch(
				defkit.Status().Case(
					defkit.Status().Condition("Synced").Is("True"),
					defkit.Status().Concat("Synced: ", defkit.Status().Field("status.atProvider.arn")),
				),
				defkit.Status().Default("Syncing S3 Bucket"),
			),
		)).
		Template(func(tpl *defkit.Template) {
			tenantExists := defkit.PathExists("context.custom.tenant")
			tenant := defkit.Reference("context.custom.tenant")

			bucket := defkit.NewResource("s3.aws.upbound.io/v1beta2", "Bucket").
				SetIf(tenantExists, "metadata.name",
					defkit.Interpolation(tenant, defkit.Lit("-"), vela.AppName(), defkit.Lit("-"), vela.Name(), defkit.Lit("-"), region)).
				SetIf(defkit.Not(tenantExists), "metadata.name",
					defkit.Interpolation(vela.AppName(), defkit.Lit("-"), vela.Name(), defkit.Lit("-"), region)).
				Set("spec.forProvider.region", region).
				SetIf(bucketName.IsSet(), "spec.forProvider.bucketPrefix",
					defkit.Plus(bucketName, defkit.Lit("-"))).
				Set(`spec.forProvider.tags[crossplane-kind]`, defkit.Lit("bucket.s3.aws.upbound.io")).
				Set(`spec.forProvider.tags[crossplane-name]`, vela.Name()).
				Set(`spec.forProvider.tags[crossplane-providerconfig]`, providerConfigRef).
				Set(`spec.forProvider.tags[managed-by]`, defkit.Lit("crossplane")).
				SetIf(tenantExists, `spec.forProvider.tags[tenant]`, tenant).
				Set("spec.deletionPolicy", defkit.Lit("Delete")).
				Set("spec.providerConfigRef.name", providerConfigRef)

			tpl.Output(bucket)
		})
}
