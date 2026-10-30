mock_provider "harness" {}

run "plan_rds" {
  command = plan

  variables {
    proxy_access_point_id = "ap-1"
    cloud_connector_id    = "cc"
    database_arn          = "arn:aws:rds:us-west-2:123456789012:db:orders"
  }
}
