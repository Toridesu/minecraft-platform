data "aws_caller_identity" "ci" {}

locals {
  ci_region_arn    = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.ci.account_id}"
  ci_backup_bucket = "arn:aws:s3:::pmp-lab-backup-${data.aws_caller_identity.ci.account_id}-*"
  ci_ec2_create = [
    "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateRouteTable",
    "ec2:CreateInternetGateway", "ec2:CreateSecurityGroup", "ec2:CreateVpcEndpoint",
    "ec2:CreateVolume", "ec2:CreateNetworkInterface",
    "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
  ]
}

# CI passes this one existing role; it cannot create/update IAM roles itself.
resource "aws_iam_role" "ci_minecraft" {
  name = "${var.project_name}-ci-minecraft"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_instance_profile" "ci_minecraft" {
  name = "${var.project_name}-ci-minecraft"
  role = aws_iam_role.ci_minecraft.name
}

resource "aws_iam_role_policy_attachment" "ci_minecraft_ssm" {
  role       = aws_iam_role.ci_minecraft.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ci_minecraft_backup" {
  name = "project-backups"
  role = aws_iam_role.ci_minecraft.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketVersions"]
        Resource  = local.ci_backup_bucket
        Condition = { StringEquals = { "s3:ResourceAccount" = data.aws_caller_identity.ci.account_id } }
      },
      {
        Effect    = "Allow"
        Action    = ["s3:PutObject", "s3:GetObject", "s3:GetObjectVersion", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource  = "${local.ci_backup_bucket}/backups/*"
        Condition = { StringEquals = { "s3:ResourceAccount" = data.aws_caller_identity.ci.account_id } }
      }
    ]
  })
}

data "aws_iam_policy_document" "github_lab_read" {
  # These EC2/KMS list operations cannot be limited to individual resource IDs.
  statement {
    actions   = ["ec2:Describe*", "kms:ListAliases", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
  statement {
    actions = [
      "s3:GetBucketLocation", "s3:GetBucketTagging", "s3:GetBucketPolicy",
      "s3:GetBucketPolicyStatus", "s3:GetBucketPublicAccessBlock", "s3:GetBucketOwnershipControls",
      "s3:GetEncryptionConfiguration", "s3:GetBucketVersioning", "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl", "s3:GetBucketLogging", "s3:GetReplicationConfiguration",
      "s3:GetBucketObjectLockConfiguration", "s3:GetBucketWebsite", "s3:GetAccelerateConfiguration",
      "s3:GetBucketCORS", "s3:GetBucketRequestPayment", "s3:ListBucket",
      "s3:ListBucketVersions", "s3:ListBucketMultipartUploads"
    ]
    resources = [local.ci_backup_bucket]
  }
  statement {
    actions   = ["iam:GetRole", "iam:GetInstanceProfile"]
    resources = [aws_iam_role.ci_minecraft.arn, aws_iam_instance_profile.ci_minecraft.arn]
  }
  statement {
    actions   = ["ssm:DescribeDocument", "ssm:GetDocument", "ssm:ListDocumentVersions", "ssm:ListTagsForResource"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.ci.account_id}:document/pmp-lab-minecraft-*"]
  }
}

resource "aws_iam_role_policy" "github_plan_lab" {
  name   = "lab-read"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_lab_read.json
}

data "aws_iam_policy_document" "github_lab_write" {
  source_policy_documents = [data.aws_iam_policy_document.github_lab_read.json]
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ci_minecraft.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
  statement {
    actions   = local.ci_ec2_create
    resources = ["${local.ci_region_arn}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["lab"]
    }
  }
  statement {
    actions   = ["ec2:RunInstances"]
    resources = ["${local.ci_region_arn}:instance/*", "${local.ci_region_arn}:volume/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
  }
  # RunInstances also authorizes a newly allocated ENI, before it has tags.
  # Its subnet/security-group authorizations below still require our project.
  statement {
    actions   = ["ec2:RunInstances"]
    resources = ["${local.ci_region_arn}:network-interface/*"]
  }
  statement {
    actions   = ["ec2:RunInstances"]
    resources = ["${local.ci_region_arn}:subnet/*", "${local.ci_region_arn}:security-group/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }
  statement {
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}::image/ami-0722c84b91d123e55"]
  }
  statement {
    actions   = ["ec2:CreateTags"]
    resources = ["${local.ci_region_arn}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = [for action in concat(local.ci_ec2_create, ["ec2:RunInstances"]) : split(":", action)[1]]
    }
  }
  statement {
    actions = concat(local.ci_ec2_create, [
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:TerminateInstances",
      "ec2:DeleteVolume", "ec2:AttachVolume", "ec2:DetachVolume", "ec2:ModifyVolume",
      "ec2:ModifyInstanceAttribute", "ec2:ModifyVpcAttribute", "ec2:ModifySubnetAttribute",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:DeleteRouteTable",
      "ec2:DeleteSubnet", "ec2:DeleteVpc", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:DeleteNetworkInterface"
    ])
    resources = ["${local.ci_region_arn}:*/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = ["lab"]
    }
  }
  statement {
    actions = [
      "s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucketTagging", "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutBucketOwnershipControls", "s3:DeleteBucketOwnershipControls",
      "s3:PutEncryptionConfiguration", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration"
    ]
    resources = [local.ci_backup_bucket]
  }
  statement {
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:AbortMultipartUpload"]
    resources = ["${local.ci_backup_bucket}/backups/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:ResourceAccount"
      values   = [data.aws_caller_identity.ci.account_id]
    }
  }
  statement {
    actions   = ["ssm:CreateDocument", "ssm:UpdateDocument", "ssm:UpdateDocumentDefaultVersion", "ssm:DeleteDocument", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource"]
    resources = ["arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.ci.account_id}:document/pmp-lab-minecraft-*"]
  }
}

resource "aws_iam_role_policy" "github_apply_lab" {
  name   = "lab-write"
  role   = aws_iam_role.github_apply.id
  policy = data.aws_iam_policy_document.github_lab_write.json
}

# Only ephemeral CI material expires; the Terraform state prefix is untouched.
resource "aws_s3_bucket_lifecycle_configuration" "ci_plans" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    id     = "temporary-ci-plans"
    status = "Enabled"
    filter { prefix = "ci-plans/" }
    expiration { days = 1 }
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
  rule {
    id     = "remove-expired-ci-markers"
    status = "Enabled"
    filter { prefix = "ci-plans/" }
    expiration { expired_object_delete_marker = true }
  }
}
