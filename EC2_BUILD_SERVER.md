# Temporary EC2 build server for the Operator image

The runtime architecture does not require a build server. This is only an optional workaround for environments such as AWS CloudShell where Docker builds can exhaust local storage.

## Recommended pattern

1. Run Terraform far enough to create the ECR repository.
2. Launch a small temporary Amazon Linux 2023 EC2 instance.
3. Attach an EC2 instance role that can authenticate to and push to ECR (for a lab, `AmazonEC2ContainerRegistryPowerUser` is sufficient).
4. Restrict administrative access to your IP or use your preferred SSM access pattern.
5. Run `scripts/build-operator-ec2.sh` on the instance.
6. Verify the image exists in ECR.
7. Terminate the build instance.

`t3.small` or `t3.medium` is usually sufficient for this short build. Give the instance enough root-disk space for Docker layers (for example 16-20 GiB).

## On the EC2 instance

Clone this repository, then run:

```bash
export AWS_REGION=us-west-2
export ECR_REPO_NAME=ai-k8s-ops/devops-agent-operator
./scripts/build-operator-ec2.sh
```

The helper:

- installs Docker/Git when needed on Amazon Linux 2023;
- starts Docker;
- gets the AWS account ID from the instance role;
- logs Docker into ECR;
- fetches the pinned upstream Operator commit;
- builds `linux/amd64`;
- pushes the deterministic tag used by `scripts/build-operator.sh`.

Verify:

```bash
aws ecr describe-images \
  --region us-west-2 \
  --repository-name ai-k8s-ops/devops-agent-operator \
  --output table
```

After the image is safely in ECR, terminate the build server. EKS pulls the Operator image directly from ECR; the build server has no runtime responsibility.
