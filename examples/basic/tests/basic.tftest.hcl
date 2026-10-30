mock_provider "harness" {}

run "plan_basic" {
  command = plan

  variables {
    proxy_access_point_id    = "ap-1"
    proxy_cloud_connector_id = "proxy-account"
    cloud_connector_id       = "cc"
  }

  assert {
    condition     = length(module.rules.rule_ids) == 4
    error_message = "expected four VM rules"
  }
}
