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

variable "default_language" {
  description = "Default content language served by CloudFront."
  type        = string
  default     = "en"

  validation {
    condition     = contains(["en", "es"], var.default_language)
    error_message = "Default language must be either en or es."
  }
}

variable "enable_language_routing" {
  description = "Whether to associate the Lambda@Edge language routing function with CloudFront."
  type        = bool
  default     = true
}
