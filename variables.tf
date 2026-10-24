variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "project_name" {
  type    = string
  default = "bank-balance-app"
}

variable "stage_name" {
  type    = string
  default = "dev"
}

variable "cors_allowed_origin" {
  description = "Origin allowed by API Gateway CORS. Guide uses * (development only)."
  type        = string
  default     = "*"
}
