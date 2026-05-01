output "bootstrap_brokers" {
  description = "TLS bootstrap broker connection string"
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
  sensitive   = true
}

output "cluster_arn" {
  value = aws_msk_cluster.this.arn
}
