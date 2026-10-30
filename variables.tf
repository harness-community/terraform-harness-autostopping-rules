variable "proxies" {
  description = <<-EOT
    Existing self-managed AutoStopping access points (proxies), keyed by a stable name that rules reference.
    `id` is the access point ID the proxy registered. Set `cloud_connector_id` only when the proxy lives in a
    different cloud account than the target VMs; it is written as `proxy_cloud_connector_id` on VM rules.
    RDS rules cannot use a proxy that sets `cloud_connector_id`.
  EOT
  type = map(object({
    id                 = string
    cloud_connector_id = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.proxies) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", key))])
    error_message = "proxies keys must start with a letter or digit and contain only letters, digits, underscores, and hyphens."
  }

  validation {
    condition     = alltrue([for proxy in values(var.proxies) : length(trimspace(proxy.id)) > 0])
    error_message = "Each proxies entry needs a non-empty id."
  }

  validation {
    condition = alltrue([
      for proxy in values(var.proxies) : proxy.cloud_connector_id == null ? true : length(trimspace(proxy.cloud_connector_id)) > 0
    ])
    error_message = "proxies.*.cloud_connector_id must be null or a non-empty connector ID."
  }
}

variable "albs" {
  description = <<-EOT
    Existing AWS Application Load Balancers to REGISTER with Harness AutoStopping as `harness_autostopping_aws_alb`,
    keyed by a stable name. This module is import-only: it never creates the AWS ALB and never deletes it on destroy
    (`delete_cloud_resources_on_destroy` is hardcoded to false). HTTP(S) rules select one with `rules.*.alb`.
    ALBs never carry TCP traffic.

    - `alb_arn`: required ARN of the existing AWS ALB to register.
    - `cloud_connector_id`, `region`, `vpc`: required by the provider.
    - `certificate_id`, `security_groups`: optional.
  EOT
  type = map(object({
    name               = optional(string)
    cloud_connector_id = string
    region             = string
    vpc                = string
    alb_arn            = string
    certificate_id     = optional(string)
    security_groups    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.albs) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", key))])
    error_message = "albs keys must start with a letter or digit and contain only letters, digits, underscores, and hyphens."
  }

  validation {
    condition = alltrue([
      for alb in values(var.albs) : length(trimspace(alb.alb_arn)) > 0 && can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/.+", alb.alb_arn))
    ])
    error_message = "albs.*.alb_arn is required and must be an Application Load Balancer ARN (arn:aws:elasticloadbalancing:<region>:<account>:loadbalancer/app/...)."
  }

  validation {
    condition = alltrue([
      for alb in values(var.albs) : length(trimspace(alb.cloud_connector_id)) > 0 && length(trimspace(alb.region)) > 0 && length(trimspace(alb.vpc)) > 0
    ])
    error_message = "Each albs entry needs non-empty cloud_connector_id, region, and vpc."
  }

  validation {
    condition     = length(distinct([for key, alb in var.albs : coalesce(alb.name, key)])) == length(var.albs)
    error_message = "ALB names must be unique. The map key is used when name is omitted."
  }

  validation {
    condition = length([for alb in values(var.albs) : alb.alb_arn]) == length(distinct([
      for alb in values(var.albs) : alb.alb_arn
    ]))
    error_message = "Each alb_arn may be registered by only one albs entry."
  }
}

variable "alb_api_key" {
  description = <<-EOT
    Harness NG API key written to every created ALB registration (`api_key`). Harness uses it to authenticate the
    AutoStopping warmup function. Required by provider 0.47.2+ whenever `albs` is non-empty. Sensitive; note it is stored in state.
  EOT
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = length(var.albs) == 0 || (var.alb_api_key != null ? length(var.alb_api_key) > 0 : false)
    error_message = "alb_api_key is required when albs is non-empty (provider harness_autostopping_aws_alb.api_key is required)."
  }
}

variable "dry_run" {
  description = <<-EOT
    Default for all VM and RDS rules. When true (the default), Harness creates the rules but does not stop or start resources.
    Set false to enforce stopping account-wide, or override per rule with rules.*.dry_run / rds_rules.*.dry_run.
  EOT
  type        = bool
  default     = true
}

variable "rules" {
  description = <<-EOT
    AutoStopping VM rules keyed by a stable name. `dry_run` is optional per rule and inherits `var.dry_run` when unset.
    The key is the Terraform address
    (`harness_autostopping_rule_vm.this["<key>"]`); removing a key destroys only that rule.

    Each rule needs at least one access path:
    - `ssh = true`: proxyless SSH intent. The module emits no tcp block, port, or proxy. The provider has no
      explicit proxyless field, so the Harness rule only targets the instances plus any other configured routing.
    - `alb` (an `albs` key) or `proxy` (a `proxies` key; not both) together with `routing` (required) and optional
      `health`: HTTP(S) access.
    - `tcp = { proxy, rdp?, forward? }`: raw TCP through a `proxies` key (ALBs are not allowed).

    `cloud_connector_id` is required unless `alb` is set, in which case it defaults to the ALB's `cloud_connector_id`.
    `regions` defaults to `[albs[alb].region]` when `alb` is set and `regions` is empty.
  EOT
  type = map(object({
    name               = optional(string)
    cloud_connector_id = optional(string)
    idle_time_mins     = optional(number, 10)
    dry_run            = optional(bool)
    use_spot           = optional(bool, false)

    vm_ids  = optional(list(string), [])
    regions = optional(list(string), [])
    zones   = optional(list(string), [])
    tags = optional(list(object({
      key   = string
      value = string
    })), [])

    custom_domains = optional(list(string), [])

    ssh   = optional(bool, false)
    alb   = optional(string)
    proxy = optional(string)

    routing = optional(list(object({
      source_protocol = string
      source_port     = number
      target_protocol = string
      target_port     = number
      path            = optional(string, "/")
      action          = optional(string, "forward")
    })), [])

    health = optional(object({
      protocol         = string
      port             = number
      path             = optional(string, "/")
      timeout          = optional(number, 30)
      status_code_from = optional(number, 200)
      status_code_to   = optional(number, 299)
    }))

    tcp = optional(object({
      proxy = string
      rdp = optional(object({
        connect_on = optional(number)
        port       = optional(number, 3389)
      }))
      forward = optional(list(object({
        connect_on = optional(number)
        port       = number
      })), [])
    }))

    depends = optional(object({
      rule_id      = number
      delay_in_sec = optional(number, 0)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.rules) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", key))])
    error_message = "rules keys must start with a letter or digit and contain only letters, digits, underscores, and hyphens."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : length(rule.vm_ids) > 0 || length(rule.tags) > 0
    ])
    error_message = "Each rule must select instances with vm_ids or tags."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.alb == null || rule.proxy == null
    ])
    error_message = "A rule cannot set both alb and proxy."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : (rule.alb != null || rule.proxy != null) ? length(rule.routing) > 0 : true
    ])
    error_message = "routing must have at least one entry when alb or proxy is set."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.alb == null ? true : contains(keys(var.albs), rule.alb)
    ])
    error_message = "rules.*.alb must be a key of the albs variable."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.proxy == null ? true : contains(keys(var.proxies), rule.proxy)
    ])
    error_message = "rules.*.proxy must be a key of the proxies variable."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : (rule.alb == null && rule.proxy == null) ? (length(rule.routing) == 0 && rule.health == null) : true
    ])
    error_message = "routing and health require alb or proxy to be set."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : (
        rule.ssh ||
        ((rule.alb != null || rule.proxy != null) && length(rule.routing) > 0) ||
        rule.tcp != null
      )
    ])
    error_message = "Each rule needs at least one access type: ssh = true, alb/proxy with routing, or tcp."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.tcp == null ? true : contains(keys(var.proxies), rule.tcp.proxy)
    ])
    error_message = "tcp.proxy must be a key of the proxies variable. ALBs are HTTP(S)-only and cannot carry rdp or forward traffic."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.tcp == null ? true : (rule.tcp.rdp != null || length(rule.tcp.forward) > 0)
    ])
    error_message = "tcp needs rdp or at least one forward entry."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : (
        rule.cloud_connector_id != null ? length(trimspace(rule.cloud_connector_id)) > 0 :
        (rule.alb != null && contains(keys(var.albs), rule.alb))
      )
    ])
    error_message = "cloud_connector_id is required unless alb is set (then it defaults to the ALB's cloud_connector_id)."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.idle_time_mins >= 1
    ])
    error_message = "idle_time_mins must be at least 1."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rules) : rule.depends == null ? true : rule.depends.delay_in_sec >= 0
    ])
    error_message = "depends.delay_in_sec must be zero or greater."
  }

  validation {
    condition = length(distinct([
      for key, rule in var.rules : coalesce(rule.name, key)
    ])) == length(var.rules)
    error_message = "Rule names must be unique. The map key is used when name is omitted."
  }

  validation {
    condition = length(flatten([
      for rule in values(var.rules) : rule.custom_domains
      ])) == length(distinct(flatten([
        for rule in values(var.rules) : rule.custom_domains
    ])))
    error_message = "Each custom domain may belong to only one rule."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : concat(
        [
          for route in rule.routing : (
            contains(["http", "https"], route.source_protocol) &&
            contains(["http", "https"], route.target_protocol) &&
            route.source_port >= 1 && route.source_port <= 65535 &&
            route.target_port >= 1 && route.target_port <= 65535
          )
        ],
        rule.health == null ? [] : [
          contains(["http", "https"], rule.health.protocol) &&
          rule.health.port >= 1 && rule.health.port <= 65535
        ],
      )
    ]))
    error_message = "HTTP routing and health checks must use http or https and a TCP port from 1 to 65535."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rules) : rule.tcp == null ? [] : concat(
        rule.tcp.rdp == null ? [] : [
          (rule.tcp.rdp.connect_on == null ? true : (rule.tcp.rdp.connect_on >= 1 && rule.tcp.rdp.connect_on <= 65535)) &&
          rule.tcp.rdp.port >= 1 && rule.tcp.rdp.port <= 65535
        ],
        [
          for forward in rule.tcp.forward : (
            (forward.connect_on == null ? true : (forward.connect_on >= 1 && forward.connect_on <= 65535)) &&
            forward.port >= 1 && forward.port <= 65535
          )
        ],
      )
    ]))
    error_message = "TCP ports must be from 1 to 65535."
  }

  # connect_on is a listener port on a proxy, so it must be unique per proxy across VM rules and RDS rules.
  validation {
    condition = length(concat(
      flatten([
        for rule in values(var.rules) : rule.tcp == null ? [] : concat(
          rule.tcp.rdp != null && rule.tcp.rdp.connect_on != null ? ["${rule.tcp.proxy}:${rule.tcp.rdp.connect_on}"] : [],
          [for forward in rule.tcp.forward : "${rule.tcp.proxy}:${forward.connect_on}" if forward.connect_on != null],
        )
      ]),
      flatten([
        for rule in values(var.rds_rules) : [
          for forward in rule.forward_rules : "${rule.proxy}:${forward.connect_on}" if forward.connect_on != null
        ]
      ]),
      )) == length(distinct(concat(
        flatten([
          for rule in values(var.rules) : rule.tcp == null ? [] : concat(
            rule.tcp.rdp != null && rule.tcp.rdp.connect_on != null ? ["${rule.tcp.proxy}:${rule.tcp.rdp.connect_on}"] : [],
            [for forward in rule.tcp.forward : "${rule.tcp.proxy}:${forward.connect_on}" if forward.connect_on != null],
          )
        ]),
        flatten([
          for rule in values(var.rds_rules) : [
            for forward in rule.forward_rules : "${rule.proxy}:${forward.connect_on}" if forward.connect_on != null
          ]
        ]),
    )))
    error_message = "Each explicit connect_on port must be unique per proxy across VM rules and RDS rules."
  }
}

variable "rds_rules" {
  description = <<-EOT
    AutoStopping RDS rules keyed by a stable name, independent of VM rules.
    `dry_run` is optional per rule and inherits `var.dry_run` when unset.
    `proxy` is a `proxies` key. RDS rules require a same-account proxy: the provider has no
    `proxy_cloud_connector_id` for RDS, so a proxy that sets `cloud_connector_id` is rejected.
    `forward_rules[*].connect_on` is the proxy listener port; `port` is the database port.
  EOT
  type = map(object({
    name               = optional(string)
    cloud_connector_id = string
    idle_time_mins     = optional(number, 10)
    dry_run            = optional(bool)

    database = object({
      id     = string # database ARN or identifier as the provider expects
      region = string
    })

    proxy = string
    forward_rules = list(object({
      connect_on = optional(number)
      port       = number
    }))

    depends = optional(object({
      rule_id      = number
      delay_in_sec = optional(number, 0)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.rds_rules) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", key))])
    error_message = "rds_rules keys must start with a letter or digit and contain only letters, digits, underscores, and hyphens."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rds_rules) : length(trimspace(rule.database.id)) > 0 && length(trimspace(rule.database.region)) > 0
    ])
    error_message = "Each rds_rules entry needs a database id and region."
  }

  validation {
    condition     = alltrue([for rule in values(var.rds_rules) : contains(keys(var.proxies), rule.proxy)])
    error_message = "rds_rules.*.proxy must be a key of the proxies variable. ALBs cannot front RDS."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rds_rules) : contains(keys(var.proxies), rule.proxy) ? var.proxies[rule.proxy].cloud_connector_id == null : true
    ])
    error_message = "RDS rules require a same-account proxy. Cross-account proxy connectors (proxies.*.cloud_connector_id) are not supported for RDS."
  }

  validation {
    condition     = alltrue([for rule in values(var.rds_rules) : length(rule.forward_rules) > 0])
    error_message = "Each rds_rules entry needs at least one forward_rules entry."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.rds_rules) : [
        for forward in rule.forward_rules : (
          (forward.connect_on == null ? true : (forward.connect_on >= 1 && forward.connect_on <= 65535)) &&
          forward.port >= 1 && forward.port <= 65535
        )
      ]
    ]))
    error_message = "RDS forward rule ports must be from 1 to 65535."
  }

  validation {
    condition     = alltrue([for rule in values(var.rds_rules) : rule.idle_time_mins >= 1])
    error_message = "rds_rules idle_time_mins must be at least 1."
  }

  validation {
    condition = alltrue([
      for rule in values(var.rds_rules) : rule.depends == null ? true : rule.depends.delay_in_sec >= 0
    ])
    error_message = "rds_rules depends.delay_in_sec must be zero or greater."
  }

  validation {
    condition     = length(distinct([for key, rule in var.rds_rules : coalesce(rule.name, key)])) == length(var.rds_rules)
    error_message = "RDS rule names must be unique. The map key is used when name is omitted."
  }
}
