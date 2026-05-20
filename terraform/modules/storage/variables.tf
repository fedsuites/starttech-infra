variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for frontend hosting"
  type        = string
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes in the Redis cluster"
  type        = number
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for ElastiCache"
  type        = list(string)
}

variable "redis_security_group_id" {
  description = "Security group ID for ElastiCache Redis"
  type        = string
}