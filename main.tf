# main.tf

provider "google" {
  project = var.project_id
  region  = var.region
}


# This module now exclusively handles enabling all necessary APIs.
# It's more robust and maintained by Google.
module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 18.1"

  project_id = var.project_id

  activate_apis = [
    "clouddeploy.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com"
  ]

  disable_services_on_destroy = false
}


# 2. Create an Artifact Registry for Docker images
resource "google_artifact_registry_repository" "hashitalks_app_repo" {
  repository_id = "${var.app_name}-repo"
  format        = "DOCKER"
  description   = "Docker repository for ${var.app_name}"
  location      = var.region
  depends_on    = [module.project-services]
}

# 3. Define Cloud Deploy Targets (Test, Staging, Production)
resource "google_clouddeploy_target" "test" {
  name        = "${var.app_name}-test"
  description = "Test Cloud Run environment"
  run {
    location = var.region
  }

  labels = {
    environment = "test"
    app         = var.app_name
    managed_by  = "terraform"
  }

  depends_on = [module.project-services]
  location   = var.region
  provider   = google-beta
}

resource "google_clouddeploy_target" "staging" {
  name             = "${var.app_name}-staging"
  description      = "Staging Cloud Run environment"
  location         = var.region
  require_approval = true

  labels = {
    environment = "staging"
    app         = var.app_name
    managed_by  = "terraform"
  }

  run {
    location = var.region
  }
  depends_on = [module.project-services]
}

resource "google_clouddeploy_target" "production" {
  name             = "${var.app_name}-production"
  description      = "Production Cloud Run environment"
  require_approval = true # CRITICAL: This enforces a manual approval gate
  location         = var.region

  labels = {
    environment = "production"
    app         = var.app_name
    managed_by  = "terraform"
  }

  run {
    location = var.region
  }
  depends_on = [module.project-services]
}

# 4. Define the Cloud Deploy Delivery Pipeline
resource "google_clouddeploy_delivery_pipeline" "pipeline" {
  name        = "${var.app_name}-delivery-pipeline"
  description = "Delivery pipeline for the ${var.app_name} application"
  location    = var.region
  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.test.name
      profiles  = ["test"] # Matches 'test' profile in skaffold.yaml
    }
    stages {
      target_id = google_clouddeploy_target.staging.name
      profiles  = ["staging"] # Matches 'staging' profile in skaffold.yaml
    }
    stages {
      target_id = google_clouddeploy_target.production.name
      profiles  = ["production"] # Matches 'production' profile in skaffold.yaml
    }
  }
  depends_on = [module.project-services]
}

# 5. Create the Cloud Build Trigger to automate application deployments
resource "google_cloudbuild_trigger" "app_trigger" {
  name        = "trigger-deploy-${var.app_name}"
  description = "Deploys ${var.app_name} on PR merge to main"
  filename    = "cloudbuild.yaml"

  github {
    owner = split("/", var.github_app_repo)[0]
    name  = split("/", var.github_app_repo)[1]
    pull_request {
      branch          = "^main$" # Regex for the main branch
      comment_control = "COMMENTS_DISABLED"
      invert_regex    = false
    }
  }

  # These substitutions will be available in the application's cloudbuild.yaml
  substitutions = {
    _DELIVERY_PIPELINE = google_clouddeploy_delivery_pipeline.pipeline.name
    _REGION            = var.region
    _APP_NAME          = var.app_name
  }
  depends_on = [module.project-services]
}