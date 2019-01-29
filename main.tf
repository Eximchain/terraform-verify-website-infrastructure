# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS
# ---------------------------------------------------------------------------------------------------------------------
provider "aws" {
    version = "~> 1.57"

    region  = "us-east-1"
}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS
# ---------------------------------------------------------------------------------------------------------------------
locals {
    website_bucket_name  = "eximchain-verify-website"
    log_bucket_name = "eximchain-verify-website-logs"
    cloudfront_origin_id = "S3-verify.eximchain.com"
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 BUCKET POLICIES
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "public_access_website" {
    statement {
        sid       = "PublicReadGetObject"
        effect    = "Allow"
        actions   = ["s3:GetObject"]
        resources = ["${aws_s3_bucket.website_content.arn}/*"]

        principals {
            type        = "*"
            identifiers = ["*"]
        }
    }
}

# ---------------------------------------------------------------------------------------------------------------------
# WEBSITE CONTENT S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "website_content" {
    bucket = "${local.website_bucket_name}"
    acl    = "public-read"

    website {
        index_document = "index.html"
        error_document = "index.html"
    }

    logging {
        target_bucket = "${aws_s3_bucket.logs.bucket}"
        target_prefix = "root/"
    }
}

resource "aws_s3_bucket_policy" "website_content" {
    bucket = "${aws_s3_bucket.website_content.bucket}"
    policy = "${data.aws_iam_policy_document.public_access_website.json}"
}

# ---------------------------------------------------------------------------------------------------------------------
# LOG S3 BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
    bucket = "${local.log_bucket_name}"
    acl    = "log-delivery-write"
}

# ---------------------------------------------------------------------------------------------------------------------
# SSL CERTIFICATE
# ---------------------------------------------------------------------------------------------------------------------
data "aws_acm_certificate" "ssl_certificate" {
    # Currently hand-managed
    domain      = "eximchain.com"
    types       = ["AMAZON_ISSUED"]
    most_recent = true
}

# ---------------------------------------------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "website_distribution" {
    enabled = true
    # TODO: Enable aliases after moving DNS
    #aliases = ["verify.eximchain.com"]

    default_root_object = "index.html"
    is_ipv6_enabled     = true

    comment = "CloudFront distribution for the Eximchain Verify website"

    origin {
        domain_name = "${aws_s3_bucket.website_content.bucket_domain_name}"
        origin_id   = "${local.cloudfront_origin_id}"

        s3_origin_config {
            origin_access_identity = "${aws_cloudfront_origin_access_identity.website.cloudfront_access_identity_path}"
        }
    }

    default_cache_behavior {
        allowed_methods  = ["GET", "HEAD"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = "${local.cloudfront_origin_id}"

        forwarded_values {
            query_string = false

            cookies {
                forward = "none"
            }
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl                = 0
        default_ttl            = 86400
        max_ttl                = 31536000

        smooth_streaming = false
        compress         = false
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    logging_config {
        bucket          = "${aws_s3_bucket.logs.bucket_domain_name}"
        include_cookies = false
    }

    viewer_certificate {
        # TODO: swap to eximchain.com certificate
        #acm_certificate_arn = "${data.aws_acm_certificate.ssl_certificate.arn}"
        cloudfront_default_certificate = true
        ssl_support_method  = "sni-only"
    }
}

resource "aws_cloudfront_origin_access_identity" "website" {
    comment = "Origin Access Identity for the Eximchain Verify Website CloudFront Distribution"
}