output "rule_ids" {
  description = "VM AutoStopping rule IDs keyed by the rules map. Pass tonumber(rule_ids[key]) as depends.rule_id on a later apply."
  value       = { for key, rule in harness_autostopping_rule_vm.this : key => rule.id }
}

output "identifiers" {
  description = "VM rule Harness identifiers keyed by the rules map."
  value       = { for key, rule in harness_autostopping_rule_vm.this : key => rule.identifier }
}

output "connect" {
  description = "Proxy source ports assigned by Harness for proxy-backed TCP (tcp.rdp, tcp.forward), keyed by VM rule. Proxyless ssh rules have no entries."
  value       = { for key, rule in harness_autostopping_rule_vm.this : key => rule.connect }
}

output "alb_identifiers" {
  description = "Harness identifiers of the registered (imported) ALBs keyed by the albs map."
  value       = { for key, alb in harness_autostopping_aws_alb.this : key => alb.identifier }
}

output "rds_rule_ids" {
  description = "RDS AutoStopping rule IDs keyed by the rds_rules map. Pass tonumber(rds_rule_ids[key]) as depends.rule_id on a later apply."
  value       = { for key, rule in harness_autostopping_rule_rds.this : key => rule.id }
}

output "rds_identifiers" {
  description = "RDS rule Harness identifiers keyed by the rds_rules map."
  value       = { for key, rule in harness_autostopping_rule_rds.this : key => rule.identifier }
}

output "dry_run" {
  description = "Module-level default dry_run (var.dry_run)."
  value       = var.dry_run
}

output "vm_rules_dry_run" {
  description = "Resolved dry_run per VM rule key."
  value       = { for key, rule in harness_autostopping_rule_vm.this : key => rule.dry_run }
}

output "rds_rules_dry_run" {
  description = "Resolved dry_run per RDS rule key."
  value       = { for key, rule in harness_autostopping_rule_rds.this : key => rule.dry_run }
}

output "rules_pending_enforcement" {
  description = "Rule keys whose resolved dry_run is true (not yet stopping/starting resources)."
  value = {
    vm  = [for key, rule in harness_autostopping_rule_vm.this : key if rule.dry_run]
    rds = [for key, rule in harness_autostopping_rule_rds.this : key if rule.dry_run]
  }
}
