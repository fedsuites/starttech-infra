output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.alb_dns_name
}

/*output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = module.storage.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = module.storage.cloudfront_distribution_id
}*/

output "s3_bucket_name" {
  description = "Name of the frontend S3 bucket"
  value       = module.storage.s3_bucket_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.compute.ecr_repository_url
}

output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = module.storage.redis_endpoint
  sensitive   = true
}

output "backend_log_group_name" {
  description = "CloudWatch log group for backend"
  value       = aws_cloudwatch_log_group.backend.name
}


output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.asg_name
}