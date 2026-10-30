variable "proxy_access_point_id" {
  description = "Access point the proxy registered. Read it from the Harness UI or /var/lw_proxy/config.toml."
  type        = string
}

variable "proxy_cloud_connector_id" {
  description = "Connector that owns the proxy account. Required for a cross-account access point."
  type        = string
  default     = null
}

variable "cloud_connector_id" {
  description = "Connector that owns the target VM account."
  type        = string
}

variable "blue_rule_id" {
  description = "Numeric ID of the blue rule. Leave null on the first apply, then set tonumber(module.rules.rule_ids[\"blue\"]) so teal can depend on it."
  type        = number
  default     = null
}
