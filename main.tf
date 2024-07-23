################################################################################
# Create S3 Static Website - primary and secondary
################################################################################
module "s3_primary" {
  source        = "./modules/s3-static-website"
  bucket_name   = var.bucket_name_primary
  source_files  = "webfiles_primary"
  common_tags   = local.common_tags
  naming_prefix = local.naming_prefix
}

module "s3_secondary" {
  source        = "./modules/s3-static-website"
  bucket_name   = var.bucket_name_secondary
  source_files  = "webfiles_secondary"
  common_tags   = local.common_tags
  naming_prefix = local.naming_prefix
}

################################################################################
# Create AWS Cloudfront distribution
################################################################################
module "cloud_front" {
  source                 = "./modules/cloud-front"
  s3_primary_bucket_id   = module.s3_primary.static_website_id
  s3_secondary_bucket_id = module.s3_secondary.static_website_id
  common_tags            = local.common_tags
  naming_prefix          = local.naming_prefix
}

################################################################################
# S3 bucket policy to allow access from cloudfront
################################################################################
module "s3_cf_policy_primary" {
  source                      = "./modules/s3-cf-policy"
  bucket_id                   = module.s3_primary.static_website_id
  bucket_arn                  = module.s3_primary.static_website_arn
  cloudfront_distribution_arn = module.cloud_front.cloudfront_distribution_arn
}

module "s3_cf_policy_secondary" {
  source                      = "./modules/s3-cf-policy"
  bucket_id                   = module.s3_secondary.static_website_id
  bucket_arn                  = module.s3_secondary.static_website_arn
  cloudfront_distribution_arn = module.cloud_front.cloudfront_distribution_arn
}
