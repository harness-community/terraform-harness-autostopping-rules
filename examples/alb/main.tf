module "rules" {
  source = "../.."

  # Rules will not stop instances until this (or a per-rule dry_run override) is false.
  dry_run = true

  alb_api_key = var.harness_api_key

  # Import-only: registers an existing AWS ALB with Harness. The module never creates
  # or deletes the AWS load balancer.
  albs = {
    web = {
      cloud_connector_id = var.cloud_connector_id
      region             = "us-west-2"
      vpc                = var.vpc_id
      alb_arn            = var.alb_arn
      certificate_id     = var.certificate_id
      security_groups    = var.security_groups
    }
  }

  rules = {
    # cloud_connector_id and regions are omitted: they default from albs["web"].
    app = {
      vm_ids         = ["i-0123456789abcdef0"]
      custom_domains = ["app.example.com"]
      alb            = "web"
      routing = [{
        source_protocol = "https"
        source_port     = 443
        target_protocol = "http"
        target_port     = 8080
      }]
      health = { protocol = "http", port = 8080, path = "/healthz" }
    }
  }
}
