output "cloudfront_domain_name" {
  value = "http://${module.cloud_front.cloudfront_distribution_domain_name}"
}


output "static_website_endpoint" {
  value = module.s3_primary.static_website_endpoint
}
