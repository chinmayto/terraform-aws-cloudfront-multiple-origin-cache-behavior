data "aws_s3_bucket" "s3_primary" {
  bucket = var.s3_primary_bucket_id
}

data "aws_s3_bucket" "s3_secondary" {
  bucket = var.s3_secondary_bucket_id
}

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