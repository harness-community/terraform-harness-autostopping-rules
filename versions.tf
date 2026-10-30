terraform {
  # 1.9 allows variable validations to reference other variables (proxies, albs).
  required_version = ">= 1.9.0"

  required_providers {
    harness = {
      source = "harness/harness"
      # harness_autostopping_aws_alb and harness_autostopping_rule_rds schemas verified against 0.47.2.
      version = ">= 0.47.2"
    }
  }
}
