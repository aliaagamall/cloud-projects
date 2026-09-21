provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "content-translation"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
