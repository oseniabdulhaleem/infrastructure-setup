# variables.tf

variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "project_name" {
  description = "The GCP project Name to deploy resources into."
  type        = string
  default     = "Cloud Roadshow"
}

variable "region" {
  description = "The primary GCP region for resources."
  type        = string
  default     = "europe-west1"
}

variable "app_name" {
  description = "A short, unique name for the application (e.g webapp). Used for naming resources."
  type        = string
  default     = "hashitalks-cloud-run-app"
}

variable "github_app_repo" {
  description = "The name of the application source code repository in 'owner/repo' format."
  type        = string
  # EXAMPLE: "oseniabdulhaleem/hashitalks-cloud-run"
}