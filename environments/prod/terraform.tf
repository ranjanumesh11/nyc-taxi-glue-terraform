terraform {
  required_version = ">= 1.6"

  cloud {
    organization = "demo-kt-101"
    workspaces {
      name = "nyc-taxi-glue-prod"
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
