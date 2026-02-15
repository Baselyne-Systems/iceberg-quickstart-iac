# --- DynamoDB version store ---

resource "aws_dynamodb_table" "nessie" {
  name         = "${var.project_name}-${var.environment}-nessie"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nessie"
  }
}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "nessie" {
  name = "${var.project_name}-${var.environment}-nessie"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# --- Task execution role ---

resource "aws_iam_role" "nessie_execution" {
  name = "${var.project_name}-${var.environment}-nessie-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nessie_execution" {
  role       = aws_iam_role.nessie_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Task role (S3 + DynamoDB access) ---

resource "aws_iam_role" "nessie_task" {
  name = "${var.project_name}-${var.environment}-nessie-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "nessie_task" {
  name = "nessie-s3-dynamo"
  role = aws_iam_role.nessie_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
        ]
        Resource = aws_dynamodb_table.nessie.arn
      }
    ]
  })
}

# --- CloudWatch log group ---

resource "aws_cloudwatch_log_group" "nessie" {
  name              = "/ecs/${var.project_name}-${var.environment}-nessie"
  retention_in_days = 30
}

# --- Task definition ---

resource "aws_ecs_task_definition" "nessie" {
  family                   = "${var.project_name}-${var.environment}-nessie"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.nessie_execution.arn
  task_role_arn            = aws_iam_role.nessie_task.arn

  container_definitions = jsonencode([{
    name  = "nessie"
    image = "ghcr.io/projectnessie/nessie:${var.nessie_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 19120
      hostPort      = 19120
      protocol      = "tcp"
    }]

    environment = [
      {
        name  = "NESSIE_VERSION_STORE_TYPE"
        value = "DYNAMODB"
      },
      {
        name  = "QUARKUS_DYNAMODB_AWS_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "NESSIE_VERSION_STORE_DYNAMODB_TABLE_PREFIX"
        value = "${var.project_name}-${var.environment}-nessie"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.nessie.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "nessie"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:19120/api/v2/config || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# --- Security Groups ---

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-nessie-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nessie-alb"
  }
}

resource "aws_security_group" "nessie" {
  name_prefix = "${var.project_name}-${var.environment}-nessie-ecs-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 19120
    to_port         = 19120
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nessie-ecs"
  }
}

# --- ALB ---

resource "aws_lb" "nessie" {
  name               = "${var.project_name}-${var.environment}-nessie"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-nessie"
  }
}

resource "aws_lb_target_group" "nessie" {
  name        = "${var.project_name}-${var.environment}-nessie"
  port        = 19120
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/v2/config"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}

resource "aws_lb_listener" "nessie" {
  load_balancer_arn = aws_lb.nessie.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nessie.arn
  }
}

# --- ECS Service ---

resource "aws_ecs_service" "nessie" {
  name            = "nessie"
  cluster         = aws_ecs_cluster.nessie.id
  task_definition = aws_ecs_task_definition.nessie.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [aws_security_group.nessie.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nessie.arn
    container_name   = "nessie"
    container_port   = 19120
  }

  depends_on = [aws_lb_listener.nessie]
}

data "aws_region" "current" {}
