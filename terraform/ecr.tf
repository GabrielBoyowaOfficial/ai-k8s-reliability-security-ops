locals {
  ecr_repositories = {
    operator = var.operator_ecr_repository_name
    demo     = var.demo_ecr_repository_name
  }
}

resource "aws_ecr_repository" "this" {
  for_each = local.ecr_repositories

  name = each.value

  # Immutable tags make an image reference (repo:tag) mean exactly one image,
  # which is what an investigation or a rollback later needs. The build
  # scripts skip the push when a tag already exists.
  image_tag_mutability = "IMMUTABLE"

  # Disposable lab: allow `terraform destroy` to delete repos that still hold images.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
