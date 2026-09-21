variable "region" {
  description = "AWS region where the infrastructure will be deployed."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either dev or prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "content-translation"
}
