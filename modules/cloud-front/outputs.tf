output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.cf-dist.arn
}
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.cf-dist.domain_name
}
