resource "aws_s3_bucket" "backup" {
  bucket        = var.backup_bucket_name == "" ? null : var.backup_bucket_name
  bucket_prefix = var.backup_bucket_name == "" ? "${local.name_prefix}-backup-" : null
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Intentional SSE-S3 choice for the short-lived learning lab.
# Review by 2026-12-31 or before adopting long-lived use.
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  depends_on = [aws_s3_bucket_versioning.backup]

  rule {
    id     = "expire-lab-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}
