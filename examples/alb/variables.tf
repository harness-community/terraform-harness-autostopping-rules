variable "cloud_connector_id" {
  description = "Connector that owns the target VM account."
  type        = string
}

variable "alb_arn" {
  description = "ARN of the existing Application Load Balancer to register with AutoStopping."
  type        = string
}

variable "vpc_id" {
  description = "VPC the ALB and target VMs live in."
  type        = string
}

variable "certificate_id" {
  description = "ACM certificate ARN for HTTPS listeners."
  type        = string
  default     = null
}

variable "security_groups" {
  description = "Security groups for the ALB."
  type        = list(string)
  default     = []
}

variable "harness_api_key" {
  description = "Harness NG API key used by the AutoStopping warmup function."
  type        = string
  sensitive   = true
}
