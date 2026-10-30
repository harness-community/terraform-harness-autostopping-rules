module "rules" {
  source = "../.."

  # Rules will not stop instances until this (or a per-rule dry_run override) is false.
  dry_run = true

  # RDS requires a same-account proxy: leave cloud_connector_id unset.
  proxies = {
    shared = { id = var.proxy_access_point_id }
  }

  rds_rules = {
    orders = {
      cloud_connector_id = var.cloud_connector_id
      idle_time_mins     = 15
      database = {
        id     = var.database_arn
        region = "us-west-2"
      }
      proxy = "shared"
      forward_rules = [{
        connect_on = 5433 # proxy listener
        port       = 5432 # database port
      }]
    }
  }
}
