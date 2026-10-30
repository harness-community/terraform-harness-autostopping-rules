terraform {
  required_version = ">= 1.9.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = ">= 0.47.2"
    }
  }
}

provider "harness" {}
