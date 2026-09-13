variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "personal-website"
}

variable "aws_region" {
  description = "AWS region where the infrastructure is deployed."
  type        = string
  default     = "us-east-1"
}