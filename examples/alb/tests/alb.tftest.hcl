mock_provider "harness" {}

run "plan_alb" {
  command = plan

  variables {
    cloud_connector_id = "cc"
    alb_arn            = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/web/abc"
    vpc_id             = "vpc-1"
    harness_api_key    = "pat.test"
  }
}
