variable "cluster_name" {
  type = string
}

variable "kafka_version" {
  type    = string
  default = "3.6.0"
}

variable "broker_count" {
  type    = number
  default = 3
}

variable "instance_type" {
  type    = string
  default = "kafka.m5.large"
}

variable "ebs_volume_size" {
  description = "EBS volume size in GiB per broker"
  type        = number
  default     = 100
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "environment" {
  type = string
}
