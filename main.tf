# main.tf

provider "google" {
  project = var.project_id
  region  = var.region
}



# 1. Create a secret in Secret Manager to hold the GitHub PAT
resource "google_secret_manager_secret" "github_token_secret" {
  project   = var.project_id
  secret_id = "github-pat-for-cloudbuild"

  replication {
    auto {}
  }
}

# 2. Add the PAT you created as the first version of the secret
resource "google_secret_manager_secret_version" "github_token_secret_version" {
  secret      = google_secret_manager_secret.github_token_secret.id
  secret_data = var.github_pat
}

# 3. Grant the Cloud Build Service Agent permission to access the secret
#    This uses a data source to construct the IAM policy correctly.
data "google_iam_policy" "serviceagent_secretAccessor" {
  binding {
    role = "roles/secretmanager.secretAccessor"
    members = [
      # This constructs the full name of the Cloud Build Service Agent
      "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
    ]
  }
}

# This resource applies the policy to the secret.
resource "google_secret_manager_secret_iam_policy" "policy" {
  project     = google_secret_manager_secret.github_token_secret.project
  secret_id   = google_secret_manager_secret.github_token_secret.secret_id
  policy_data = data.google_iam_policy.serviceagent_secretAccessor.policy_data
}

# Create the GitHub connection using the secret and installation ID
resource "google_cloudbuildv2_connection" "github" {
  project  = var.project_id
  location = var.region
  name     = "hashitalks-connection-setup"

  github_config {
    app_installation_id = var.github_app_installation_id
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token_secret_version.id
    }
  }
  # This ensures the IAM policy is applied before the connection is created
  depends_on = [google_secret_manager_secret_iam_policy.policy]
}

# 5. Connect the specific GitHub repository to the connection
resource "google_cloudbuildv2_repository" "app_repo" {
  project           = var.project_id
  location          = var.region
  name              = "oseniabdulhaleem-hashitalks-cloud-run"
  parent_connection = google_cloudbuildv2_connection.github.name
  remote_uri        = "https://github.com/${var.github_app_repo}.git"
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
    location = "projects/${var.project_id}/locations/${var.region}"
  }

  labels = {
    environment = "test"
    app         = var.app_name
    managed_by  = "terraform"
  }

  depends_on = [module.project-services]
  location   = var.region
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
    location = "projects/${var.project_id}/locations/${var.region}"
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
    location = "projects/${var.project_id}/locations/${var.region}"
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
  description = "Deploys ${var.app_name} on push to main"
  location    = "global"

  service_account = google_service_account.app_build_sa.id
  repository_event_config {
    # Use the ID from the data source
    repository = google_cloudbuildv2_repository.app_repo.id
    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DELIVERY_PIPELINE = google_clouddeploy_delivery_pipeline.pipeline.name
    _REGION            = var.region
    _APP_NAME          = var.app_name
  }

  depends_on = [
    module.project-services,
    google_cloudbuildv2_repository.app_repo,
    google_service_account_iam_member.cloudbuild_agent_can_use_build_sa
  ]
}