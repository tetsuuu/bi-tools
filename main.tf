terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.65.0"
    }
  }
  required_version = ">= 1.5"
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_region" "current" {}

data "aws_route53_zone" "example_com" {
  name = "example.com"
}

# Common resources
data "aws_iam_policy_document" "assume_role_ecs_task" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_group" "bi" {
  name              = "/aws/ecs/task/bi"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "internal" {
  name = "internal"
}

resource "aws_ecs_cluster_capacity_providers" "internal" {
  cluster_name = aws_ecs_cluster.internal.name

  capacity_providers = [
    "FARGATE",
    "FARGATE_SPOT",
  ]
}

resource "aws_security_group" "internal" {
  name        = "internalEcsTaskSg"
  description = "For internal ECS task"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [local.sg_alb]
    self            = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
