locals {
  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_oidc_audience = "sts.amazonaws.com"

  # Requires .github/oidc-subject.json; repository settings are not changed here.
  github_subject_prefix = "repository_owner_id:160250540:repository_id:1376681181:ref:refs/heads/main"

  github_plan_subject = "${local.github_subject_prefix}:environment:lab-plan"

  github_apply_subject = "${local.github_subject_prefix}:environment:lab-apply"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = local.github_oidc_url

  client_id_list = [
    local.github_oidc_audience,
  ]
}

data "aws_iam_policy_document" "github_plan_assume_role" {
  statement {
    sid     = "GitHubActionsPlan"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = [local.github_oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_plan_subject]
    }
  }
}

data "aws_iam_policy_document" "github_apply_assume_role" {
  statement {
    sid     = "GitHubActionsApply"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = [local.github_oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_apply_subject]
    }

  }
}
