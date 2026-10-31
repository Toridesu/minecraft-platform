locals {
  lab_state_keys = [
    "pmp/lab/session-data/terraform.tfstate",
    "pmp/lab/session-runtime/terraform.tfstate",
  ]
  lab_state_arns = [for key in local.lab_state_keys : "${aws_s3_bucket.terraform_state.arn}/${key}"]
  lab_lock_arns  = [for arn in local.lab_state_arns : "${arn}.tflock"]
}

data "aws_iam_policy_document" "github_plan_state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = concat(local.lab_state_keys, [for key in local.lab_state_keys : "${key}.tflock"], ["env:/", "ci-plans/*"])
    }
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = local.lab_state_arns
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.lab_lock_arns
  }
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/ci-plans/*"]
  }
}

data "aws_iam_policy_document" "github_apply_state" {
  source_policy_documents = [data.aws_iam_policy_document.github_plan_state.json]
  statement {
    actions   = ["s3:ListBucketVersions"]
    resources = [aws_s3_bucket.terraform_state.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["ci-plans/*"]
    }
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = local.lab_state_arns
  }
  statement {
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/ci-plans/*"]
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "${var.project_name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role" "github_apply" {
  name                 = "${var.project_name}-github-apply"
  assume_role_policy   = data.aws_iam_policy_document.github_apply_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_plan_state" {
  name   = "${var.project_name}-github-plan-state"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_state.json
}

resource "aws_iam_role_policy" "github_apply_state" {
  name   = "${var.project_name}-github-apply-state"
  role   = aws_iam_role.github_apply.id
  policy = data.aws_iam_policy_document.github_apply_state.json
}
