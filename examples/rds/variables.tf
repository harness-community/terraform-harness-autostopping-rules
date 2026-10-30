variable "proxy_access_point_id" {
  description = "Same-account access point the proxy registered."
  type        = string
}

variable "cloud_connector_id" {
  description = "Connector that owns the database account."
  type        = string
}

variable "database_arn" {
  description = "ARN of the RDS database."
  type        = string
}
