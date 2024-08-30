# Secret for Redash
resource "aws_secretsmanager_secret" "redash" {
  name = "/redash/credentials"
}

resource "aws_secretsmanager_secret_version" "redash" {
  secret_id     = aws_secretsmanager_secret.redash.id
  secret_string = jsonencode(local.redash_secrets)
}

# IAM Role for Redash ECS
resource "aws_iam_role" "redash_task_execution_role" {
  name               = "RedashTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_task.json

  inline_policy {
    name   = "AllowGetDbConnStr"
    policy = data.aws_iam_policy_document.redash_inline_policy.json
  }
}

data "aws_iam_policy_document" "redash_inline_policy" {
  version = "2012-10-17"
  statement {
    sid       = "AllowSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.redash.arn]

  }
}

resource "aws_iam_role_policy_attachment" "redash" {
  role       = aws_iam_role.redash_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "redash_task_role" {
  name               = "RedashTaskRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_task.json

  inline_policy {
    name   = "RedashTaskRolePolicy"
    policy = data.aws_iam_policy_document.redash_task_role_policy.json
  }
}

data "aws_iam_policy_document" "redash_task_role_policy" {
  version = "2012-10-17"

  statement {
    sid    = "AllowWriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.bi.arn}:*"]
  }
}

# Redash ECS service
resource "aws_ecs_task_definition" "redash" {
  family                   = "redash"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.redash_task_execution_role.arn
  cpu                      = "2048"
  memory                   = "4096"
  container_definitions    = <<EOF
[
  {
    "name": "redash-server",
    "image": "redash/redash:${local.redash_version}",
    "cpu": 0,
    "network_mode": "awsvpc",
    "portMappings": [
      {
      "hostPort": 5000,
      "containerPort": 5000,
      "protocol": "tcp"
      }
    ],
    "command": [
      "server"
    ],
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redash"
      }
    }
  },
  {
    "name": "redash-scheduler",
    "image": "redash/redash:${local.redash_version}",
    "cpu": 0,
    "essential": true,
    "portMappings": [],
    "network_mode": "awsvpc",
    "command": [
      "scheduler"
    ],
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redash-scheduler"
      }
    }
  },
  {
    "name": "redash-worker",
    "image": "redash/redash:${local.redash_version}",
    "cpu": 0,
    "essential": true,
    "portMappings": [],
    "network_mode": "awsvpc",
    "command": [
      "scheduled_worker"
    ],
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "QUEUES", "value": "scheduled_queries,schemas,queries,periodic emails default" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redash-worker"
      }
    }
  },
  {
    "name": "redis",
    "image": "redis:3-alpine",
    "cpu": 0,
    "essential": true,
    "portMappings": [
      {
        "hostPort": 6379,
        "containerPort": 6379,
        "protocol": "tcp"
      }
    ],
    "network_mode": "awsvpc",
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redis"
      }
    }
  }
]
EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Redash initial task before starting the server
resource "aws_ecs_task_definition" "redash_init" {
  family                   = "redash-initializer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.redash_task_execution_role.arn
  cpu                      = "2048"
  memory                   = "4096"
  container_definitions    = <<EOF
[
  {
    "name": "redash-server",
    "image": "redash/redash:${local.redash_version}",
    "cpu": 0,
    "network_mode": "awsvpc",
    "portMappings": [
      {
      "hostPort": 5000,
      "containerPort": 5000,
      "protocol": "tcp"
      }
    ],
    "command": [
      "server"
    ],
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redash"
      }
    }
  },
  {
    "name": "redash-init",
    "image": "redash/redash:${local.redash_version}",
    "cpu": 0,
    "essential": true,
    "portMappings": [],
    "network_mode": "awsvpc",
    "command": [
      "create_db"
    ],
    "environment": [
      { "name": "PYTHONUNBUFFERED", "value": "0" },
      { "name": "REDASH_LOG_LEVEL", "value": "INFO" }
    ],
    "secrets": [
      {
        "name": "REDASH_COOKIE_SECRET",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_COOKIE_SECRET::"
      },
      {
        "name": "REDASH_DATABASE_URL",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_DATABASE_URL::"
      },
      {
        "name": "REDASH_SECRET_KEY",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:REDASH_SECRET_KEY::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "redash-init"
      }
    }
  }
]
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "redash" {
  name                              = "redash"
  cluster                           = aws_ecs_cluster.internal.id
  task_definition                   = aws_ecs_task_definition.redash.arn
  desired_count                     = 0 # FIXME
  health_check_grace_period_seconds = 600

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.redash.arn
    container_name   = "redash"
    container_port   = "5000"
  }

  network_configuration {
    subnets         = local.private_subnets
    security_groups = [aws_security_group.internal.id]
  }
}

# Redash Networking
resource "aws_lb" "redash" {
  name               = "redash"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.sg_alb]
  subnets            = local.public_subnets
}

resource "aws_lb_listener" "redash_https" {
  load_balancer_arn = aws_lb.redash.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.redash.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Hi!"
      status_code  = "200"
    }
  }
}

resource "aws_lb_target_group" "redash" {
  name        = "tg-redash"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    path     = "/ping"
    interval = 300
    timeout  = 120
  }
}

resource "aws_route53_record" "r53_record_redash_lb_alias" {
  name    = "redash.${data.aws_route53_zone.example_com.name}"
  type    = "A"
  zone_id = data.aws_route53_zone.example_com.zone_id

  alias {
    zone_id                = aws_lb.redash.zone_id
    name                   = aws_lb.redash.dns_name
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "redash" {
  domain_name       = "redash.${data.aws_route53_zone.example_com.name}"
  validation_method = "DNS"
  tags = {
    Name = "redash-lb"
  }
}

resource "aws_lb_listener_rule" "redash" {
  listener_arn = aws_lb_listener.internal_https.arn
  priority     = 20
  condition {
    host_header {
      values = [aws_acm_certificate.redash.domain_name]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redash.arn
  }
}
