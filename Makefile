.PHONY: help fmt validate deploy build-operator build-demo webhook test watch verify destroy

help:
	@echo "make deploy          full deploy (needs DEVOPS_AGENT_WEBHOOK_URL / _SECRET exported)"
	@echo "make build-operator  build + push the pinned upstream Operator image"
	@echo "EC2 fallback:       docs/EC2_BUILD_SERVER.md + scripts/build-operator-ec2.sh"
	@echo "make build-demo      build + push the memory-leak-demo image"
	@echo "make webhook         create/update the webhook Kubernetes Secret"
	@echo "make watch           watch the demo pod until OOMKilled"
	@echo "make verify          verify every stage of the incident pipeline"
	@echo "make destroy         remove workloads and destroy all AWS resources"
	@echo "make fmt validate    Terraform format / validate"

fmt:
	terraform -chdir=terraform fmt -recursive

validate:
	terraform -chdir=terraform init -backend=false -input=false
	terraform -chdir=terraform validate

deploy:
	./scripts/deploy.sh

build-operator:
	./scripts/build-operator.sh

build-demo:
	./scripts/build-demo.sh

webhook:
	./scripts/configure-webhook.sh

watch:
	./scripts/test-oom.sh watch

verify:
	./scripts/test-oom.sh verify

destroy:
	./scripts/destroy.sh
