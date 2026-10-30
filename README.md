# Harness AutoStopping rules

> **Dry-run by default.** Rules are created with `dry_run = true`, so Harness will not stop or start resources. Enforce with `dry_run = false` on the module, or override per rule with `rules.*.dry_run` / `rds_rules.*.dry_run`. See the `rules_pending_enforcement` output.

Creates AutoStopping resources from keyed maps:

- [`harness_autostopping_rule_vm`](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/autostopping_rule_vm) from `rules`
- [`harness_autostopping_rule_rds`](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/autostopping_rule_rds) from `rds_rules`
- [`harness_autostopping_aws_alb`](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/autostopping_aws_alb) registrations of **existing** AWS ALBs from `albs` (import-only; the AWS load balancer is never created or deleted)

The module does not create self-managed proxies (access points) or the target instances. Requires OpenTofu/Terraform `>= 1.9` (cross-variable validations) and Harness provider `>= 0.47.2`.

VM rules are one `for_each` resource, addressed as `harness_autostopping_rule_vm.this["<key>"]`. Changing how a rule is accessed, adding or removing other map entries, or adding a dependency never moves a rule to a different address. New rules inherit the module-level `dry_run` (default `true`).

## Ingress inputs

```hcl
proxies = {
  shared = {
    id                 = "ap-..."            # access point the proxy registered
    cloud_connector_id = "proxy-account"     # optional; only for a cross-account proxy
  }
}

albs = {
  web = {
    cloud_connector_id = "alb-account"
    region             = "us-west-2"
    vpc                = "vpc-..."
    alb_arn            = "arn:aws:elasticloadbalancing:..."
    certificate_id     = "arn:aws:acm:..."   # optional
    security_groups    = ["sg-..."]          # optional
  }
}
alb_api_key = var.harness_api_key            # required when albs is non-empty
```

Map keys must match `^[A-Za-z0-9][A-Za-z0-9_-]*$`; they are what rules reference.

## VM rule inputs

```hcl
rules = {
  app = {
    vm_ids = ["i-..."]                 # or tags
    ssh    = true                      # optional, proxyless intent
    alb    = "web"                     # key of albs   (xor proxy)
    proxy  = "shared"                  # key of proxies (xor alb)
    routing = [{ source_protocol = "https", source_port = 443,
                 target_protocol = "http",  target_port = 8080 }]   # required with alb/proxy
    health = { protocol = "http", port = 8080, path = "/healthz" } # optional
    tcp = {                            # optional; proxy only
      proxy   = "shared"
      rdp     = { connect_on = 3390 }
      forward = [{ connect_on = 8443, port = 443 }]
    }
  }
}
```

`cloud_connector_id` is required unless `alb` is set; with `alb` it defaults to `albs[alb].cloud_connector_id`, and an empty `regions` defaults to `[albs[alb].region]`.

| Field | Behavior |
| --- | --- |
| `ssh = true` | Target instance only. No `tcp.ssh`, no port, no proxy is emitted. |
| `alb` / `proxy` + `routing` | Emits provider `http`. Set one of `alb` (an `albs` key) or `proxy` (a `proxies` key), never both. `routing` is required. |
| `tcp` | `tcp.proxy` must be a `proxies` key and `rdp` or `forward` must be set. Emits one provider `tcp` block. ALBs are rejected. |

Every rule needs at least one of `ssh`, `alb`/`proxy` with `routing`, or `tcp`.

### Proxyless SSH caveat

The provider has no explicit proxyless-SSH field. `ssh = true` therefore only records intent in the module: the resulting Harness VM rule has the instance filter plus whatever other routing you configured (for example `http`). An SSH-only rule is a filter-only rule. Verify in Harness that this matches the behavior you expect before relying on it.

### Data flow

- HTTP via proxy: `proxy_id = proxies[key].id` and `proxy_cloud_connector_id = proxies[key].cloud_connector_id`.
- HTTP via ALB: `proxy_id = harness_autostopping_aws_alb.this[key].identifier`; `proxy_cloud_connector_id` is never set.
- TCP: `proxy_id` and `proxy_cloud_connector_id` come from `proxies[tcp.proxy]`.

`connect_on` is a proxy listener port and must be unique per proxy across VM and RDS rules.

## Cross-account limits

- `rules.*.cloud_connector_id` is the connector that owns the target instances (defaulted from the ALB when `alb` is set).
- `proxies.*.cloud_connector_id` is for a proxy in a different account than the VMs; it applies to VM `http` and `tcp` only.
- RDS rules cannot use cross-account proxies: the provider has no `proxy_cloud_connector_id` on RDS, so the module rejects a proxy that sets it.
- ALB registrations carry their own connector; they are never given `proxy_cloud_connector_id`.

## ALBs are import-only

This module only registers an already-existing AWS Application Load Balancer with Harness (`harness_autostopping_aws_alb`). It never creates the AWS ALB, and `delete_cloud_resources_on_destroy` is hardcoded to `false`, so destroying only removes the Harness registration. `alb_arn` is required for every `albs` entry. `alb_api_key` (sensitive) is written to state. ALBs carry HTTP(S) only; use a proxy for TCP.

## RDS rules

```hcl
rds_rules = {
  orders = {
    cloud_connector_id = "db-account"
    database           = { id = "arn:aws:rds:...", region = "us-west-2" }
    proxy              = "shared"                       # same-account proxy key
    forward_rules      = [{ connect_on = 5433, port = 5432 }]
    depends            = { rule_id = 123, delay_in_sec = 30 }
  }
}
```

RDS rules are independent of VM rules, addressed as `harness_autostopping_rule_rds.this["<key>"]`, and need at least one forward rule.

## Dependencies

`depends` takes the numeric ID of a rule that already exists (`tonumber(module.rules.rule_ids["blue"])` or `rds_rule_ids`). Create the independent rule first, then reference it. The second apply updates the dependent rule in place.

## Outputs

`rule_ids`, `identifiers`, `connect` (VM, keyed by rule; proxyless SSH has none), `alb_identifiers`, `rds_rule_ids`, `rds_identifiers`.

## Migration to the flat rule interface

| Before | After |
| --- | --- |
| `access.ssh = true` | `ssh = true` |
| `access.http.ingress.proxy = "<key>"` | `proxy = "<key>"` |
| `access.http.ingress.alb = "<key>"` | `alb = "<key>"` |
| `access.http.routing` / `access.http.health` | `routing` / `health` |
| `access.tcp_proxy` | `tcp.proxy` |
| `access.rdp` | `tcp.rdp` |
| `access.tcp_forward` | `tcp.forward` |
| `albs.*.delete_cloud_resources_on_destroy` | removed (always `false`) |
| `albs.*.alb_arn` optional | required |
| `rules.*.cloud_connector_id` / `regions` always required | optional when `alb` is set (defaulted from the ALB) |

VM rule addresses are unchanged, so no state moves are required. Note that rules that previously emitted a `tcp.ssh` block will drop it on the next apply.

Envoy matches `path` literally. `/` forwards every request. `/*` matches only the path `/*`.

The Harness provider reads `HARNESS_PLATFORM_API_KEY` and `HARNESS_ACCOUNT_ID` from the environment.

## Examples

- [`examples/basic`](examples/basic): SSH-only, proxy HTTP, proxy TCP, and a dependency wired on a second apply.
- [`examples/alb`](examples/alb): import of an existing ALB used by an HTTP rule (connector and region defaulted from the ALB).
- [`examples/rds`](examples/rds): same-account RDS forwarding.

## Tests

`tofu test` runs mock-provider tests in [`tests/`](tests).
