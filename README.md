# Implementing AWS Cloudfront with Multiple Origin Cache Behavior using Terraform

In this technical blog post, we will explore how to implement AWS CloudFront with multiple origin cache behavior using Terraform. CloudFront's multiple origin cache behavior allows you to configure a single CloudFront distribution to fetch content from different origins based on specified conditions. This capability is particularly useful when you need to serve content from multiple sources (such as different S3 buckets or custom origins) through a single CloudFront distribution efficiently.

Multiple origin cache behavior in AWS CloudFront enables a single CloudFront distribution to fetch content from multiple origins based on rules you define. This allows you to consolidate content delivery from various sources, optimizing network latency and improving content availability. By configuring cache behaviors, you can specify which requests CloudFront forwards to which origin, based on request path patterns, headers, query strings, or any combination thereof.

## Architecture Overview
Before diving into the implementation details, let's outline the architecture we'll be working with:

![alt text](/images/diagram.png)

## Step 1: Create primary and secondary S3 static websites
We'll set up two S3 buckets to act as our primary and secondary origins. These buckets will host static websites that CloudFront will fetch content from. Also upload the files. Make sure you upload files to `secondary/` in second S3 static website as we will create second cache behaviour with `/secondary/*` path pattern.

```terraform
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
```

```terraform
################################################################################
# S3 static website bucket
################################################################################
resource "aws_s3_bucket" "s3-static-website" {
  bucket = var.bucket_name
  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-s3-bucket"
  })
}

################################################################################
# S3 public access settings
################################################################################
resource "aws_s3_bucket_public_access_block" "static_site_bucket_public_access" {
  bucket = aws_s3_bucket.s3-static-website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# S3 bucket static website configuration
################################################################################
resource "aws_s3_bucket_website_configuration" "static_site_bucket_website_config" {
  bucket = aws_s3_bucket.s3-static-website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

################################################################################
# Upload files to S3 Bucket 
################################################################################
resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.s3-static-website.id

  # webfiles/ is the Directory contains files to be uploaded to S3
  for_each = fileset("${var.source_files}/", "**/*.*")

  key          = each.value
  source       = "${var.source_files}/${each.value}"
  content_type = lookup(var.mime_map, reverse(split(".", each.value))[0], "text/plain")

}
```

## Step 2: Create CloudFront distribution with default and path-pattern based cache behavior
Using Terraform, we'll define a CloudFront distribution that includes multiple cache behaviors. One cache behavior will handle requests to a default origin (typically the primary S3 bucket), while another cache behavior will route requests based on path patterns to the secondary origin (secondary S3 bucket).
```terraform
################################################################################
# Create AWS Cloudfront distribution
################################################################################
resource "aws_cloudfront_origin_access_control" "cf-s3-oac" {
  name                              = "CloudFront S3 OAC"
  description                       = "CloudFront S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cf-dist" {
  enabled             = true
  default_root_object = "index.html"

  # Primary origin with default cache behavior
  origin {
    domain_name              = data.aws_s3_bucket.s3_primary.bucket_regional_domain_name
    origin_id                = "s3_primary"
    origin_access_control_id = aws_cloudfront_origin_access_control.cf-s3-oac.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3_primary"
    viewer_protocol_policy = "allow-all"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  # Secondary origin with path-pattern based cache behavior
  origin {
    domain_name              = data.aws_s3_bucket.s3_secondary.bucket_regional_domain_name
    origin_id                = "s3_secondary"
    origin_access_control_id = aws_cloudfront_origin_access_control.cf-s3-oac.id
  }

  ordered_cache_behavior {
    path_pattern           = "/secondary/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3_secondary"
    viewer_protocol_policy = "allow-all"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN", "US", "CA"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-cloudfront"
  })
}
```

## Step 3: Create S3 bucket policy to allow access from CloudFront
To ensure that CloudFront can access the content stored in the S3 buckets securely, we'll set up a bucket policy on both S3 buckets. This policy will allow CloudFront to fetch objects from the buckets for distribution.
```terraform
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

```

```terraform
################################################################################
# S3 bucket policy to allow access from cloudfront
################################################################################
data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [var.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site_bucket_policy" {
  bucket = var.bucket_id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}
```

## Steps to Run Terraform
Follow these steps to execute the Terraform configuration:
```terraform
terraform init
terraform plan 
terraform apply -auto-approve
```

Upon successful completion, Terraform will provide relevant outputs.
```terraform
Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

Outputs:

cloudfront_domain_name = "http://dgs42ejsdgx6n.cloudfront.net"
```

## Testing
Static Website Buckets:
![alt text](/images/buckets.png)

S3 Bucket Policies:
![alt text](/images/policy_a.png)
![alt text](/images/policy_b.png)

CloudFront Distribution:
![alt text](/images/cloudfront.png)

CloudFront Origins:
![alt text](/images/origins.png)

CloudFront Cache Behaviours:
![alt text](/images/cachebehaviours.png)

Website Default Origin:
![alt text](/images/default_origin.png)

Website Secondary Origin:
![alt text](/images/secondary_origin.png)


## Cleanup
Remember to stop AWS components to avoid large bills.
```terraform
terraform destroy -auto-approve
```

## Conclusion
Implementing AWS CloudFront with multiple origin cache behavior using Terraform provides a scalable and efficient way to manage content delivery from diverse sources. By following the steps outlined and leveraging Terraform's infrastructure-as-code capabilities, you can achieve robust and flexible content delivery configurations tailored to your application's needs.

## Resources
CoudFront Multiple Origins: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistS3AndCustomOrigins.html

CloudFront Cache Behaviour: https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_CacheBehavior.html

Github Link: https://github.com/chinmayto/terraform-aws-cloudfront-multiple-origin-cache-behavior
