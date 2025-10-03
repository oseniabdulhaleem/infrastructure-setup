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
}