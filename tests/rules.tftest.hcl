mock_provider "harness" {
  mock_resource "harness_autostopping_aws_alb" {
    defaults = {
      identifier = "alb-created-id"
    }
  }
  mock_resource "harness_autostopping_rule_vm" {
    defaults = {
      id         = "101"
      identifier = "vm_rule"
      connect    = {}
    }
  }
  mock_resource "harness_autostopping_rule_rds" {
    defaults = {
      id         = "201"
      identifier = "rds_rule"
    }
  }
}

variables {
  proxies = {
    same  = { id = "ap-same" }
    cross = { id = "ap-cross", cloud_connector_id = "proxy-account" }
  }
}

run "ssh_only_emits_no_tcp" {
  command = plan

  variables {
    rules = {
      bastion = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        ssh                = true
      }
    }
  }

  assert {
    condition     = length(harness_autostopping_rule_vm.this["bastion"].tcp) == 0
    error_message = "ssh = true must not emit a tcp block"
  }
  assert {
    condition     = length(harness_autostopping_rule_vm.this["bastion"].http) == 0
    error_message = "ssh-only rule must not emit http"
  }
  assert {
    condition     = one(harness_autostopping_rule_vm.this["bastion"].filter).vm_ids == tolist(["i-1"]) || one(harness_autostopping_rule_vm.this["bastion"].filter).vm_ids == toset(["i-1"])
    error_message = "filter must target the instance"
  }
}

run "mixed_http_and_ssh" {
  command = plan

  variables {
    rules = {
      blue = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        ssh                = true
        proxy              = "same"
        routing = [{
          source_protocol = "http"
          source_port     = 80
          target_protocol = "http"
          target_port     = 80
        }]
      }
    }
  }

  assert {
    condition     = length(harness_autostopping_rule_vm.this["blue"].tcp) == 0
    error_message = "ssh must add no tcp block next to http"
  }
  assert {
    condition     = one(harness_autostopping_rule_vm.this["blue"].http).proxy_id == "ap-same"
    error_message = "http should use the same-account proxy"
  }
  assert {
    condition     = !contains(["proxy-account", "cc"], one(harness_autostopping_rule_vm.this["blue"].http).proxy_cloud_connector_id)
    error_message = "same-account proxy must not forward a connector"
  }
}

run "cross_account_direct_proxy_http" {
  command = plan

  variables {
    rules = {
      web = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        proxy              = "cross"
        routing = [{
          source_protocol = "http"
          source_port     = 80
          target_protocol = "http"
          target_port     = 80
        }]
      }
    }
  }

  assert {
    condition     = one(harness_autostopping_rule_vm.this["web"].http).proxy_id == "ap-cross"
    error_message = "proxy id mismatch"
  }
  assert {
    condition     = one(harness_autostopping_rule_vm.this["web"].http).proxy_cloud_connector_id == "proxy-account"
    error_message = "cross-account connector must be forwarded"
  }
}

run "created_alb_used_by_http" {
  command = apply

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = {
        cloud_connector_id = "cc"
        region             = "us-west-2"
        vpc                = "vpc-1"
        alb_arn            = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc"
      }
    }
    rules = {
      app = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        alb                = "web"
        routing = [{
          source_protocol = "https"
          source_port     = 443
          target_protocol = "http"
          target_port     = 80
        }]
      }
    }
  }

  assert {
    condition     = harness_autostopping_aws_alb.this["web"].delete_cloud_resources_on_destroy == false
    error_message = "ALB destroy must never delete the AWS ALB"
  }
  assert {
    condition     = one(harness_autostopping_rule_vm.this["app"].http).proxy_id == "alb-created-id"
    error_message = "http must use the created ALB identifier"
  }
  assert {
    condition     = !contains(["proxy-account", "cc"], one(harness_autostopping_rule_vm.this["app"].http).proxy_cloud_connector_id)
    error_message = "ALB http must not forward a connector"
  }
  assert {
    condition     = output.alb_identifiers["web"] == "alb-created-id"
    error_message = "alb_identifiers output mismatch"
  }
}

run "alb_requires_api_key" {
  command = plan

  variables {
    albs = {
      web = {
        cloud_connector_id = "cc"
        region             = "us-west-2"
        vpc                = "vpc-1"
        alb_arn            = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc"
      }
    }
  }

  expect_failures = [var.alb_api_key]
}

run "reject_tcp_through_alb" {
  command = plan

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = {
        cloud_connector_id = "cc"
        region             = "us-west-2"
        vpc                = "vpc-1"
        alb_arn            = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc"
      }
    }
    rules = {
      db = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        tcp                = { proxy = "web", forward = [{ connect_on = 9000, port = 22 }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "reject_alb_and_proxy_together" {
  command = plan

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = { cloud_connector_id = "cc", region = "us-west-2", vpc = "vpc-1", alb_arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc" }
    }
    rules = {
      web = {
        vm_ids  = ["i-1"]
        alb     = "web"
        proxy   = "same"
        routing = [{ source_protocol = "http", source_port = 80, target_protocol = "http", target_port = 80 }]
      }
    }
  }

  expect_failures = [var.rules]
}

run "reject_alb_without_routing" {
  command = plan

  variables {
    proxies = { same = { id = "ap-same" } }
    rules = {
      web = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        proxy              = "same"
      }
    }
  }

  expect_failures = [var.rules]
}

run "reject_no_access_type" {
  command = plan

  variables {
    rules = {
      web = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
      }
    }
  }

  expect_failures = [var.rules]
}

run "reject_missing_connector_without_alb" {
  command = plan

  variables {
    rules = {
      web = {
        vm_ids = ["i-1"]
        ssh    = true
      }
    }
  }

  expect_failures = [var.rules]
}

run "reject_alb_missing_arn" {
  command = plan

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = { cloud_connector_id = "cc", region = "us-west-2", vpc = "vpc-1", alb_arn = "" }
    }
  }

  expect_failures = [var.albs]
}

run "alb_rule_defaults_connector_and_regions" {
  command = plan

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = { cloud_connector_id = "alb-cc", region = "us-west-2", vpc = "vpc-1", alb_arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc" }
    }
    rules = {
      app = {
        vm_ids  = ["i-1"]
        alb     = "web"
        routing = [{ source_protocol = "https", source_port = 443, target_protocol = "http", target_port = 80 }]
      }
    }
  }

  assert {
    condition     = harness_autostopping_rule_vm.this["app"].cloud_connector_id == "alb-cc"
    error_message = "cloud_connector_id must default from the ALB"
  }
  assert {
    condition     = contains(one(harness_autostopping_rule_vm.this["app"].filter).regions, "us-west-2")
    error_message = "regions must default from the ALB"
  }
  assert {
    condition     = harness_autostopping_aws_alb.this["web"].delete_cloud_resources_on_destroy == false
    error_message = "ALB destroy must never delete the AWS ALB"
  }
}

run "reject_duplicate_connect_on_per_proxy" {
  command = plan

  variables {
    rules = {
      a = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        tcp                = { proxy = "same", forward = [{ connect_on = 9000, port = 22 }] }
      }
      b = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-2"]
        tcp                = { proxy = "same", forward = [{ connect_on = 9000, port = 22 }] }
      }
    }
  }

  expect_failures = [var.rules]
}

run "same_connect_on_on_different_proxies_allowed" {
  command = plan

  variables {
    rules = {
      a = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        tcp                = { proxy = "same", forward = [{ connect_on = 9000, port = 22 }] }
      }
      b = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-2"]
        tcp                = { proxy = "cross", forward = [{ connect_on = 9000, port = 22 }] }
      }
    }
  }

  assert {
    condition     = one(harness_autostopping_rule_vm.this["b"].tcp).proxy_cloud_connector_id == "proxy-account"
    error_message = "tcp on cross-account proxy must forward connector"
  }
}

run "rds_same_account_proxy" {
  command = plan

  variables {
    rds_rules = {
      orders = {
        cloud_connector_id = "cc"
        database = {
          id     = "arn:aws:rds:us-west-2:123456789012:db:orders"
          region = "us-west-2"
        }
        proxy         = "same"
        forward_rules = [{ connect_on = 5433, port = 5432 }]
      }
    }
  }

  assert {
    condition     = one(harness_autostopping_rule_rds.this["orders"].tcp).proxy_id == "ap-same"
    error_message = "RDS must use the same-account proxy"
  }
  assert {
    condition     = one(one(harness_autostopping_rule_rds.this["orders"].tcp).forward_rule).port == 5432
    error_message = "RDS target port mismatch"
  }
  assert {
    condition     = one(one(harness_autostopping_rule_rds.this["orders"].tcp).forward_rule).connect_on == 5433
    error_message = "RDS proxy port mismatch"
  }
}

run "reject_rds_cross_account_proxy" {
  command = plan

  variables {
    rds_rules = {
      orders = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "cross"
        forward_rules      = [{ port = 5432 }]
      }
    }
  }

  expect_failures = [var.rds_rules]
}

run "reject_rds_through_alb_key" {
  command = plan

  variables {
    alb_api_key = "pat.test"
    albs = {
      web = { cloud_connector_id = "cc", region = "us-west-2", vpc = "vpc-1", alb_arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc" }
    }
    rds_rules = {
      orders = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "web"
        forward_rules      = [{ port = 5432 }]
      }
    }
  }

  expect_failures = [var.rds_rules]
}

run "dependencies_on_vm_and_rds" {
  command = plan

  variables {
    rules = {
      teal = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        ssh                = true
        depends            = { rule_id = 42, delay_in_sec = 60 }
      }
    }
    rds_rules = {
      orders = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "same"
        forward_rules      = [{ port = 5432 }]
        depends            = { rule_id = 43, delay_in_sec = 15 }
      }
    }
  }

  assert {
    condition     = one(harness_autostopping_rule_vm.this["teal"].depends).rule_id == 42 && one(harness_autostopping_rule_vm.this["teal"].depends).delay_in_sec == 60
    error_message = "VM depends not rendered"
  }
  assert {
    condition     = one(harness_autostopping_rule_rds.this["orders"].depends).rule_id == 43 && one(harness_autostopping_rule_rds.this["orders"].depends).delay_in_sec == 15
    error_message = "RDS depends not rendered"
  }
}

run "stable_vm_keys_when_access_mode_changes" {
  command = plan

  variables {
    rules = {
      alpha = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        ssh                = true
      }
      beta = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-2"]
        tcp                = { proxy = "same", rdp = {} }
      }
      gamma = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-3"]
        proxy              = "same"
        routing = [{
          source_protocol = "http"
          source_port     = 80
          target_protocol = "http"
          target_port     = 80
        }]
      }
    }
  }

  assert {
    condition     = toset(keys(harness_autostopping_rule_vm.this)) == toset(["alpha", "beta", "gamma"])
    error_message = "VM resource addresses must be exactly the rules map keys"
  }
}

run "dry_run_defaults_true" {
  command = plan

  variables {
    rules = {
      a = { cloud_connector_id = "cc", vm_ids = ["i-1"], ssh = true }
    }
    rds_rules = {
      r = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "same"
        forward_rules      = [{ port = 5432 }]
      }
    }
  }

  assert {
    condition     = harness_autostopping_rule_vm.this["a"].dry_run == true && harness_autostopping_rule_rds.this["r"].dry_run == true
    error_message = "dry_run must default to true"
  }
  assert {
    condition     = output.rules_pending_enforcement == { vm = ["a"], rds = ["r"] }
    error_message = "both rules should be pending enforcement"
  }
}

run "module_dry_run_false_flips_all" {
  command = plan

  variables {
    dry_run = false
    rules = {
      a = { cloud_connector_id = "cc", vm_ids = ["i-1"], ssh = true }
    }
    rds_rules = {
      r = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "same"
        forward_rules      = [{ port = 5432 }]
      }
    }
  }

  assert {
    condition     = harness_autostopping_rule_vm.this["a"].dry_run == false && harness_autostopping_rule_rds.this["r"].dry_run == false
    error_message = "module dry_run=false must apply to all rules"
  }
  assert {
    condition     = length(output.rules_pending_enforcement.vm) == 0 && length(output.rules_pending_enforcement.rds) == 0
    error_message = "nothing should be pending"
  }
}

run "per_rule_dry_run_wins" {
  command = plan

  variables {
    dry_run = false
    rules = {
      a = { cloud_connector_id = "cc", vm_ids = ["i-1"], ssh = true, dry_run = true }
      b = { cloud_connector_id = "cc", vm_ids = ["i-2"], ssh = true }
    }
    rds_rules = {
      r = {
        cloud_connector_id = "cc"
        database           = { id = "db", region = "us-west-2" }
        proxy              = "same"
        forward_rules      = [{ port = 5432 }]
        dry_run            = true
      }
    }
  }

  assert {
    condition     = harness_autostopping_rule_vm.this["a"].dry_run == true && harness_autostopping_rule_vm.this["b"].dry_run == false
    error_message = "per-rule dry_run must override module default"
  }
  assert {
    condition     = harness_autostopping_rule_rds.this["r"].dry_run == true
    error_message = "per-rule RDS dry_run must override module default"
  }
  assert {
    condition     = output.rules_pending_enforcement == { vm = ["a"], rds = ["r"] }
    error_message = "pending list mismatch"
  }
}

run "reject_bad_keys" {
  command = plan

  variables {
    rules = {
      "bad key" = {
        cloud_connector_id = "cc"
        vm_ids             = ["i-1"]
        ssh                = true
      }
    }
  }

  expect_failures = [var.rules]
}
