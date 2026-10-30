module "rules" {
  source = "../.."

  # Rules will not stop instances until this (or a per-rule dry_run override) is false.
  dry_run = true

  proxies = {
    shared = {
      id                 = var.proxy_access_point_id
      cloud_connector_id = var.proxy_cloud_connector_id
    }
  }

  rules = {
    # HTTP through the self-managed proxy, plus proxyless SSH intent on the same rule.
    blue = {
      cloud_connector_id = var.cloud_connector_id
      vm_ids             = ["i-0123456789abcdef0"]
      regions            = ["us-west-2"]
      custom_domains     = ["blue.example.com"]
      ssh                = true
      proxy              = "shared"
      routing = [{
        source_protocol = "http"
        source_port     = 80
        target_protocol = "http"
        target_port     = 80
      }]
      health = {
        protocol = "http"
        port     = 80
      }
    }

    # SSH only: the Harness rule just targets the instance. No tcp block, port, or proxy.
    bastion = {
      cloud_connector_id = var.cloud_connector_id
      vm_ids             = ["i-0aaaabbbbccccdddd"]
      regions            = ["us-west-2"]
      ssh                = true
    }

    # Proxy-backed raw TCP (RDP and a forwarded port).
    windows = {
      cloud_connector_id = var.cloud_connector_id
      vm_ids             = ["i-0badc0ffee0ddf00d"]
      regions            = ["us-west-2"]
      tcp = {
        proxy = "shared"
        rdp   = { connect_on = 3390 }
        forward = [{
          connect_on = 8443
          port       = 443
        }]
      }
    }

    teal = {
      cloud_connector_id = var.cloud_connector_id
      vm_ids             = ["i-0fedcba9876543210"]
      regions            = ["us-west-2"]
      custom_domains     = ["teal.example.com"]
      depends = var.blue_rule_id == null ? null : {
        rule_id      = var.blue_rule_id
        delay_in_sec = 60
      }
      proxy = "shared"
      routing = [{
        source_protocol = "http"
        source_port     = 80
        target_protocol = "http"
        target_port     = 80
      }]
    }
  }
}
