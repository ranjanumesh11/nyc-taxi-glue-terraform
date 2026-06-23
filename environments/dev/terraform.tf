terraform {
  required_version = ">= 1.6"

  # Terraform Cloud as remote backend — all plan/apply runs happen in TFC,
  # not on the GitHub Actions runner. The runner just calls the TFC API.
  cloud {
    organization = "demo-kt-101"
    workspaces {
      name = "nyc-taxi-glue-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # No credentials here — Terraform Cloud injects them at runtime
  # via the TFC_AWS_PROVIDER_AUTH dynamic credentials mechanism (OIDC).
}
