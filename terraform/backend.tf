terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "alfiemellor"

    workspaces {
      name = "infrastructure"
    }
  }
}