provider "aws" {
  region = "ap-south-1" # Change to your desired AWS region
}

# Create a VPC for ECS
resource "aws_vpc" "ecs_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create Subnets for ECS tasks (private and public)
resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a" # Choose your AZ
  map_public_ip_on_launch = true
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b" # Choose your AZ
  map_public_ip_on_launch = true
}

# Create an Internet Gateway
resource "aws_internet_gateway" "ecs_igw" {
  vpc_id = aws_vpc.ecs_vpc.id
}

# Create a Security Group for the ECS Service
resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.ecs_vpc.id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }
}

# Create an ECR Repository for Jenkins
resource "aws_ecr_repository" "jenkins_repo" {
  name = "jenkins-repo"
}

# Create ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "jenkins-cluster"
}

# Create Task Definition for Jenkins
resource "aws_ecs_task_definition" "jenkins_task" {
  family                   = "jenkins-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn  # Add execution role ARN

  container_definitions = jsonencode([
    {
      name      = "jenkins"
      image     = "${aws_ecr_repository.jenkins_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# Create ECS Service to Run Jenkins in Fargate
resource "aws_ecs_service" "jenkins_service" {
  name            = "jenkins-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.jenkins_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins_target_group.arn
    container_name   = "jenkins"
    container_port   = 8080
  }
}

# Optional: Create an Application Load Balancer (ALB) for Jenkins
resource "aws_lb" "jenkins_lb" {
  name               = "jenkins-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.ecs_sg.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

# Create a Target Group for the Load Balancer
resource "aws_lb_target_group" "jenkins_target_group" {
  name     = "jenkins-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.ecs_vpc.id
   target_type = "ip"
}

# Create a Listener for the ALB
resource "aws_lb_listener" "jenkins_listener" {
  load_balancer_arn = aws_lb.jenkins_lb.arn
  port              = "80"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_target_group.arn
  }
}

