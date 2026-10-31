resource "aws_s3_bucket" "incident_evidence" {
  bucket = local.incident_bucket_name

  # Disposable lab: evidence is short-lived, so destroy must not be blocked by objects.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs entirely; the bucket owner owns every object.
resource "aws_s3_bucket_ownership_controls" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Evidence should not be silently overwritten while an investigation is open.
resource "aws_s3_bucket_versioning" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id

  rule {
    id     = "expire-incident-evidence"
    status = "Enabled"

    filter {}

    expiration {
      days = var.incident_evidence_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Lifecycle rules require versioning state to be settled first.
  depends_on = [aws_s3_bucket_versioning.incident_evidence]
}

data "aws_iam_policy_document" "incident_evidence_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.incident_evidence.arn, "${aws_s3_bucket.incident_evidence.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "incident_evidence" {
  bucket = aws_s3_bucket.incident_evidence.id
  policy = data.aws_iam_policy_document.incident_evidence_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.incident_evidence]
}
