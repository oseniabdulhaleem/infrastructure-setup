# backend.tf

terraform {
  backend "gcs" {
    bucket = "hashitalks-bucket"
    prefix = "infra/state"
  }
}