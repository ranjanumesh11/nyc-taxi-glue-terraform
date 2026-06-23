terraform {
  required_version = ">= 1.6"

  # Workspace is selected via TF_WORKSPACE env var in GitHub Actions.
  # dev branch  → TF_WORKSPACE=nyc-taxi-glue-dev
  # main branch → TF_WORKSPACE=nyc-taxi-glue-prod
  # Both workspaces must have the tag "nyc-taxi-glue" set in TFC UI.
  cloud {
    organization = "demo-kt-101"
    workspaces {
      tags = ["nyc-taxi-glue"]
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
}
