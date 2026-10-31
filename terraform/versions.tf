terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The EKS module (21.x) requires >= 6.59. Capped below 7.0 so a future
      # major provider release cannot change behaviour underneath this lab.
      version = ">= 6.59, < 7.0"
    }
  }
}
