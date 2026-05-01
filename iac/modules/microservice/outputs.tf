output "service_name" {
  description = "Kubernetes service name"
  value       = kubernetes_service.this.metadata[0].name
}

output "deployment_name" {
  description = "Kubernetes deployment name"
  value       = kubernetes_deployment.this.metadata[0].name
}
