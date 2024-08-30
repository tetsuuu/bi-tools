# Secret for Metabase
resource "aws_secretsmanager_secret" "metabase" {
  name = "/metabase/credentials"
}

resource "aws_secretsmanager_secret_version" "metabase" {
  secret_id     = aws_secretsmanager_secret.metabase.id
  secret_string = jsonencode(local.metabase_secrets)
}

# IAM Role for Metabase ECS
resource "aws_iam_role" "metabase_task_execution_role" {
  name               = "MetabaseTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_task.json

  inline_policy {
    name   = "AllowGetDbConnStr"
    policy = data.aws_iam_policy_document.metabase_inline_policy.json
  }
}

data "aws_iam_policy_document" "metabase_inline_policy" {
  version = "2012-10-17"
  statement {
    sid       = "AllowSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.metabase.arn]

  }
}

resource "aws_iam_role_policy_attachment" "metabase" {
  role       = aws_iam_role.metabase_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "metabase_task_role" {
  name               = "MetabaseTaskRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ecs_task.json

  inline_policy {
    name   = "MetabaseTaskRolePolicy"
    policy = data.aws_iam_policy_document.metabase_task_role_policy.json
  }
}

data "aws_iam_policy_document" "metabase_task_role_policy" {
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

# Metabase ECS service
resource "aws_ecs_task_definition" "metabase" {
  family                   = "metabase"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.metabase_task_execution_role.arn
  cpu                      = "512"
  memory                   = "2048"
  container_definitions    = <<EOF
[
  {
    "name": "metabase",
    "image": "metabase/metabase:${local.metabase_version}",
    "cpu": 512,
    "memory": 2048,
    "essential": true,
    "network_mode": "awsvpc",
    "portMappings": [
      {
      "hostPort": 3000,
      "containerPort": 3000,
      "protocol": "tcp"
      }
    ],
    "environment": [
      { "name": "MB_DB_TYPE", "value": "postgres" },
      { "name": "MB_DB_PORT", "value": "5432" },
      { "name": "JAVA_TIMEZONE", "value": "Asia/Tokyo" }
    ],
    "secrets": [
      {
        "name": "MB_DB_PASS",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:MB_DB_PASS::"
      },
      {
        "name": "MB_DB_DBNAME",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:MB_DB_DBNAME::"
      },
      {
        "name": "MB_DB_USER",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:MB_DB_USER::"
      },
      {
        "name": "MB_DB_HOST",
        "valueFrom": "${aws_secretsmanager_secret.redash.arn}:MB_DB_HOST::"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.bi.name}",
        "awslogs-region": "${data.aws_region.current.name}",
        "awslogs-stream-prefix": "metabase"
      }
    }
  }
]
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "metabase" {
  name                              = "metabase"
  cluster                           = aws_ecs_cluster.internal.id
  task_definition                   = aws_ecs_task_definition.metabase.arn
  desired_count                     = 1
  health_check_grace_period_seconds = 300

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.metabase.arn
    container_name   = "metabase"
    container_port   = "3000"
  }

  network_configuration {
    subnets         = local.private_subnets
    security_groups = [aws_security_group.internal.id]
  }
}

# Metabase Networking
resource "aws_lb" "metabase" {
  name               = "metabase"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.sg_alb]
  subnets            = local.public_subnets
}

resource "aws_lb_listener" "metabase_https" {
  load_balancer_arn = aws_lb.metabase.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.metabase.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Hi!"
      status_code  = "200"
    }
  }
}

resource "aws_lb_target_group" "metabase" {
  name        = "tg-metabase"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    interval            = 60
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 30
    unhealthy_threshold = 2
    matcher             = 200
  }
}

resource "aws_lb_listener_rule" "metabase" {
  listener_arn = aws_lb_listener.metabase_https.arn
  priority     = 10
  condition {
    host_header {
      values = [aws_acm_certificate.metabase.domain_name]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.metabase.arn
  }
}

resource "aws_route53_record" "r53_record_metabase_lb_alias" {
  name    = "metabase.${data.aws_route53_zone.example_com.name}"
  type    = "A"
  zone_id = data.aws_route53_zone.example_com.zone_id

  alias {
    zone_id                = aws_lb.metabase.zone_id
    name                   = aws_lb.metabase.dns_name
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "metabase" {
  domain_name       = "metabase.${data.aws_route53_zone.example_com.name}"
  validation_method = "DNS"
  tags = {
    Name = "metabase-lb"
  }
}

resource "aws_acm_certificate_validation" "metabase" {
  certificate_arn         = aws_acm_certificate.metabase.arn
  validation_record_fqdns = [for record in aws_route53_record.metabase_acm_validation : record.fqdn]
}

resource "aws_route53_record" "metabase_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.metabase.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name    = each.value.name
  type    = each.value.type
  zone_id = data.aws_route53_zone.example_com.zone_id
  records = [
    each.value.record
  ]
  ttl = 300
}
