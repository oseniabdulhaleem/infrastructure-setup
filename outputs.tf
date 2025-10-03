# outputs.tf

output "delivery_pipeline_name" {
  value       = google_clouddeploy_delivery_pipeline.pipeline.name
  description = "The name of the Cloud Deploy delivery pipeline."
}

output "artifact_registry_repository" {
  value       = google_artifact_registry_repository.app_repo.name
  description = "The name of the Artifact Registry repository for application images."
}

output "cloud_build_trigger_id" {
  value       = google_cloudbuild_trigger.app_trigger.id
  description = "The ID of the Cloud Build trigger for the application."
}