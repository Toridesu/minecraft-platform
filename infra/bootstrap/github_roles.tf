locals {
  # session-runtimeのStateとロックファイルだけを権限対象にする
  session_runtime_state_key = "pmp/lab/session-runtime/terraform.tfstate"

  session_runtime_state_arn = "${aws_s3_bucket.terraform_state.arn}/${local.session_runtime_state_key}"

  session_runtime_lock_arn = "${local.session_runtime_state_arn}.tflock"
}

data "aws_iam_policy_document" "github_plan_state" {
  # Plan用：Stateの場所を確認する
  statement {
    sid       = "ListSessionRuntimeState"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"

      values = [
        local.session_runtime_state_key,
        "${local.session_runtime_state_key}.tflock",
      ]
    }
  }

  statement {
    # Plan用：Stateとロックを読む
    sid     = "ReadSessionRuntimeState"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      local.session_runtime_state_arn,
      local.session_runtime_lock_arn,
    ]
  }

  statement {
    # Terraformの同時実行を防ぐため、ロックだけ書き換える
    sid       = "ManageSessionRuntimeLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = [local.session_runtime_lock_arn]
  }
}

data "aws_iam_policy_document" "github_apply_state" {
  # Apply用：Stateの場所を確認する
  statement {
    sid       = "ListSessionRuntimeState"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"

      values = [
        local.session_runtime_state_key,
        "${local.session_runtime_state_key}.tflock",
      ]
    }
  }

  statement {
    # Apply用：State本体を読み書きする
    sid       = "ManageSessionRuntimeState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [local.session_runtime_state_arn]
  }

  statement {
    # Apply用：ロックを読み書き・削除する
    sid       = "ManageSessionRuntimeLock"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.session_runtime_lock_arn]
  }
}

resource "aws_iam_role" "github_plan" {
  # mainブランチからのPlan専用Role
  name                 = "${var.project_name}-github-plan"
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role" "github_apply" {
  # lab-apply EnvironmentからのApply専用Role
  name                 = "${var.project_name}-github-apply"
  assume_role_policy   = data.aws_iam_policy_document.github_apply_assume_role.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_plan_state" {
  # Plan用RoleへState権限を付与する
  name   = "${var.project_name}-github-plan-state"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_state.json
}

resource "aws_iam_role_policy" "github_apply_state" {
  # Apply用RoleへState権限を付与する
  name   = "${var.project_name}-github-apply-state"
  role   = aws_iam_role.github_apply.id
  policy = data.aws_iam_policy_document.github_apply_state.json
}
