terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# This example uses the default VPC for brevity. In a real stack, pass the
# outputs of a VPC module instead (e.g. this repo's vpc module):
#   vpc_id     = module.vpc.vpc_id
#   subnet_ids = module.vpc.private_subnet_ids

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

module "app_asg" {
  source = "../.."

  name        = "web"
  environment = "dev"
  ami_id      = data.aws_ami.amazon_linux.id

  instance_type = "t3.small"

  network = {
    vpc_id     = data.aws_vpc.default.id
    subnet_ids = data.aws_subnets.default.ids
  }

  capacity = {
    desired = 3
    min     = 2
    max     = 10
  }

  health_check = {
    type         = "ELB"
    grace_period = 600
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nginx
    systemctl start nginx
    systemctl enable nginx
  EOF

  security_group_config = {
    create = true
    ingress_rules = [
      {
        description     = "HTTP from ALB"
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        security_groups = [aws_security_group.alb.id]
      }
    ]
    egress_rules = [
      {
        description = "Allow all outbound"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ]
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  scaling_policies = [
    {
      name        = "cpu-tracking"
      policy_type = "TargetTrackingScaling"
      target_tracking_config = {
        target_value = 70.0
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
      }
    }
  ]

  instance_refresh = {
    enabled = true
    preferences = {
      min_healthy_percentage = 90
      instance_warmup        = 300
    }
  }
}

resource "aws_security_group" "alb" {
  name_prefix = "${module.app_asg.resource_prefix}-alb-"
  vpc_id      = data.aws_vpc.default.id

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

resource "aws_lb" "app" {
  name               = "${module.app_asg.resource_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "${module.app_asg.resource_prefix}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${module.app_asg.resource_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled  = true
    path     = "/"
    interval = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "alb_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "asg_name" {
  value = module.app_asg.asg_name
}
