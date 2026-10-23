provider "aws" {
  region = "eu-north-1"
}

variable "db_password" {
  description = "Пароль до бази даних"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email для сповіщень про витрати"
  type        = string
}

variable "github_repo" {
  description = "Репозиторій на GitHub"
  type        = string
}

resource "aws_budgets_budget" "cost_alert" {
  name              = "monthly-budget"
  budget_type       = "COST"
  limit_amount      = "5.0"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

resource "aws_ecr_repository" "api_repo" {
  name                 = "scooter-api-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true
}
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-north-1b"
  map_public_ip_on_launch = true
}
resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-north-1a"
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-north-1b"
}
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "scooter-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_security_group"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.main_vpc.id
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
}
resource "aws_security_group" "api_sg" {
  name        = "api_security_group"
  description = "Allow public access to API"
  vpc_id      = aws_vpc.main_vpc.id
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "db_sg" {
  name        = "db_security_group"
  description = "Allow access to DB from API"
  vpc_id      = aws_vpc.main_vpc.id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "scooter_db" {
  identifier             = "scooter-db"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "postgres"
  username               = "postgres"
  password               = var.db_password
  skip_final_snapshot    = true
  publicly_accessible    = false 
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/ecs/scooter-api"
  retention_in_days = 1
}

resource "aws_lb" "api_alb" {
  name               = "scooter-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}
resource "aws_lb_target_group" "api_tg" {
  name        = "scooter-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "ip"
  health_check {
    path                = "/docs"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
resource "aws_lb_listener" "api_listener" {
  load_balancer_arn = aws_lb.api_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

resource "aws_ecs_cluster" "app_cluster" {
  name = "scooter-cluster"
}
resource "aws_ecs_task_definition" "app_task" {
  family                   = "scooter-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  container_definitions = jsonencode([{
    name      = "scooter-api"
    image     = "${aws_ecr_repository.api_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
    }]
    environment = [
      {
        name  = "DATABASE_URL"
        value = "postgresql://postgres:${var.db_password}@${aws_db_instance.scooter_db.endpoint}/postgres"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/scooter-api"
        "awslogs-region"        = "eu-north-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
resource "aws_ecs_service" "app_service" {
  name            = "scooter-service-alb"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  depends_on      = [aws_lb_listener.api_listener]
  
  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "scooter-api"
    container_port   = 8000
  }
  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.api_sg.id, aws_security_group.db_sg.id]
    assign_public_ip = true
  }
}

output "website_url" {
  description = "Посилання на сайт"
  value       = "http://${aws_lb.api_alb.dns_name}/docs"
}