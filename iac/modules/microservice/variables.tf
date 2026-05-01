variable "name" {
  description = "Service name (used as Kubernetes resource name and label)"
  type        = string
}

variable "image" {
  description = "Full Docker image URI including tag"
  type        = string
}

variable "replicas" {
  description = "Number of pod replicas"
  type        = number
  default     = 2
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "env_vars" {
  description = "Environment variables to inject into the container"
  type        = map(string)
  default     = {}
}

variable "cpu_request" {
  type    = string
  default = "250m"
}

variable "memory_request" {
  type    = string
  default = "256Mi"
}

variable "cpu_limit" {
  type    = string
  default = "500m"
}

variable "memory_limit" {
  type    = string
  default = "512Mi"
}
