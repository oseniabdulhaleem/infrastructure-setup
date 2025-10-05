# iam.tf

data "google_project" "project" {}

# Grant the Cloud Build service account the necessary roles
# to push to Artifact Registry and create Cloud Deploy releases.
resource "google_project_iam_member" "cloudbuild_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/clouddeploy.releaser",
    "roles/run.developer",         # Allows Cloud Deploy to manage Cloud Run
    "roles/iam.serviceAccountUser" # Allows Cloud Deploy to act as the runtime SA
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    module.project-services
  ]
}


resource "google_service_account" "app_build_sa" {
  account_id   = "app-build-sa"
  display_name = "Application Build Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "app_build_sa_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer", # To push Docker images
    "roles/clouddeploy.releaser",    # To create Cloud Deploy releases
    "roles/run.developer",           # For Cloud Deploy to manage Cloud Run
    "roles/iam.serviceAccountUser"   # For Cloud Deploy to act on behalf of the runtime SA
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.app_build_sa.email}"
}

resource "google_service_account_iam_member" "cloudbuild_agent_can_use_build_sa" {
  service_account_id = google_service_account.app_build_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}


resource "google_service_account_iam_member" "terraform_can_impersonate_build_sa" {
  service_account_id = google_service_account.app_build_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:terraform-sa@${var.project_id}.iam.gserviceaccount.com"
}