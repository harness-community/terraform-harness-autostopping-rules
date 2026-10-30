resource "harness_autostopping_aws_alb" "this" {
  for_each = var.albs

  name               = coalesce(each.value.name, each.key)
  cloud_connector_id = each.value.cloud_connector_id
  region             = each.value.region
  vpc                = each.value.vpc
  api_key            = var.alb_api_key
  alb_arn            = each.value.alb_arn
  certificate_id     = each.value.certificate_id
  security_groups    = each.value.security_groups
  # Import-only: never delete the AWS ALB when the registration is destroyed.
  delete_cloud_resources_on_destroy = false
}

locals {
  # Per-rule values resolved from the referenced ALB when the rule does not set them.
  vm_rules = {
    for key, rule in var.rules : key => merge(rule, {
      resolved_cloud_connector_id = (
        rule.cloud_connector_id != null ? rule.cloud_connector_id :
        (rule.alb != null ? var.albs[rule.alb].cloud_connector_id : null)
      )
      resolved_regions = (
        length(rule.regions) > 0 ? rule.regions :
        (rule.alb != null ? [var.albs[rule.alb].region] : [])
      )
    })
  }
}

resource "harness_autostopping_rule_vm" "this" {
  for_each = local.vm_rules

  name               = coalesce(each.value.name, each.key)
  cloud_connector_id = each.value.resolved_cloud_connector_id
  idle_time_mins     = each.value.idle_time_mins
  dry_run            = coalesce(each.value.dry_run, var.dry_run)
  use_spot           = each.value.use_spot
  custom_domains     = each.value.custom_domains

  filter {
    vm_ids  = each.value.vm_ids
    regions = each.value.resolved_regions
    zones   = each.value.zones

    dynamic "tags" {
      for_each = each.value.tags
      content {
        key   = tags.value.key
        value = tags.value.value
      }
    }
  }

  dynamic "http" {
    for_each = (each.value.alb != null || each.value.proxy != null) ? [each.value] : []
    content {
      proxy_id = (
        http.value.alb != null
        ? harness_autostopping_aws_alb.this[http.value.alb].identifier
        : var.proxies[http.value.proxy].id
      )
      # Only self-managed proxies can live in another account; ALB registrations carry their own connector.
      proxy_cloud_connector_id = (
        http.value.alb != null
        ? null
        : var.proxies[http.value.proxy].cloud_connector_id
      )

      dynamic "routing" {
        for_each = http.value.routing
        content {
          source_protocol = routing.value.source_protocol
          source_port     = routing.value.source_port
          target_protocol = routing.value.target_protocol
          target_port     = routing.value.target_port
          path            = routing.value.path
          action          = routing.value.action
        }
      }

      # Provider 0.47.x panics (index out of range on http[0].health[0]) when an http block has no health block,
      # which kills the plugin process and fails every in-flight rule. Always emit one, defaulting to the first
      # routing target when the caller did not set `health`.
      dynamic "health" {
        for_each = (
          http.value.health != null ? [http.value.health] :
          length(http.value.routing) > 0 ? [{
            protocol         = http.value.routing[0].target_protocol
            port             = http.value.routing[0].target_port
            path             = "/"
            timeout          = 30
            status_code_from = 200
            status_code_to   = 299
          }] : []
        )
        content {
          protocol         = health.value.protocol
          port             = health.value.port
          path             = health.value.path
          timeout          = health.value.timeout
          status_code_from = health.value.status_code_from
          status_code_to   = health.value.status_code_to
        }
      }
    }
  }

  # ssh = true is proxyless: it deliberately adds no tcp block. Only tcp.rdp / tcp.forward use a proxy.
  dynamic "tcp" {
    for_each = each.value.tcp == null ? [] : [each.value.tcp]
    content {
      proxy_id                 = var.proxies[tcp.value.proxy].id
      proxy_cloud_connector_id = var.proxies[tcp.value.proxy].cloud_connector_id

      dynamic "rdp" {
        for_each = tcp.value.rdp == null ? [] : [tcp.value.rdp]
        content {
          connect_on = rdp.value.connect_on
          port       = rdp.value.port
        }
      }

      dynamic "forward_rule" {
        for_each = tcp.value.forward
        content {
          connect_on = forward_rule.value.connect_on
          port       = forward_rule.value.port
        }
      }
    }
  }

  dynamic "depends" {
    for_each = each.value.depends == null ? [] : [each.value.depends]
    content {
      rule_id      = depends.value.rule_id
      delay_in_sec = depends.value.delay_in_sec
    }
  }
}

resource "harness_autostopping_rule_rds" "this" {
  for_each = var.rds_rules

  name               = coalesce(each.value.name, each.key)
  cloud_connector_id = each.value.cloud_connector_id
  idle_time_mins     = each.value.idle_time_mins
  dry_run            = coalesce(each.value.dry_run, var.dry_run)

  database {
    id     = each.value.database.id
    region = each.value.database.region
  }

  tcp {
    proxy_id = var.proxies[each.value.proxy].id

    dynamic "forward_rule" {
      for_each = each.value.forward_rules
      content {
        connect_on = forward_rule.value.connect_on
        port       = forward_rule.value.port
      }
    }
  }

  dynamic "depends" {
    for_each = each.value.depends == null ? [] : [each.value.depends]
    content {
      rule_id      = depends.value.rule_id
      delay_in_sec = depends.value.delay_in_sec
    }
  }
}
