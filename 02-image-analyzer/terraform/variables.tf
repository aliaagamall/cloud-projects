variable "aws_region" {
  description = "AWS region where the Image Analyzer infrastructure is deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for AWS resource naming."
  type        = string
  default     = "image-analyzer"
}