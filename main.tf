terraform {
  /*
  cloud {
    organization = "policy-as-code-training"
    workspaces {
      name = "policy-dev-anm"
    }
  }
  */
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # version = "~> 3.22.0"
    }
  }
  required_version = ">= 0.14.0"
}

provider "aws" {
  region  = "us-west-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.64.0"

  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    project     = "project-alpha",
    environment = "development"
  }
}
# Test comment

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "web-sg-project-alpha-dev"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks

  tags = {
    project     = "project-alpha",
    environment = "development"
  }
}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.17.0"

  name        = "lb-sg-project-alpha-development"
  description = "Security group for load balancer with HTTP ports open within VPC"
  vpc_id      = module.vpc.vpc_id
  
  ingress_cidr_blocks = ["0.0.0.0/0"]

  # Start ANM change
  /*
  ingress_cidr_blocks = ["10.0.0.0/16"]
  
  ingress_rules       = ["ssh-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH open to internal network"
      cidr_blocks = "10.0.0.0/16"
      # description = "SSH open to the world"
      # cidr_blocks = "0.0.0.0/0"
    }
  ]
  */
  # End ANM change
  
  tags = {
    project     = "project-alpha",
    environment = "development"
  }
}

# ANM change start
resource "aws_ebs_volume" "unencrypted" {
  availability_zone = "us-west-1a"
  size              = 8
  encrypted         = true # Intentional violation: unencrypted EBS volume
}
# ANM change end

resource "random_string" "lb_id" {
  length  = 3
  special = false
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "2.4.0"

  # Ensure load balancer name is unique
  name = "lb-${random_string.lb_id.result}-project-alpha-development"

  internal = false

  security_groups = [module.lb_security_group.this_security_group_id]
  subnets         = module.vpc.public_subnets

  number_of_instances = length(module.ec2_instances.instance_ids)
  instances           = module.ec2_instances.instance_ids

  listener = [{
    instance_port     = "80"
    instance_protocol = "HTTP"
    lb_port           = "80"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
  }

  tags = {
    project     = "project-alpha",
    environment = "development"
  }
}

module "ec2_instances" {
  source = "./modules/aws-instance"

  # instance_count     = 3
  instance_count     = var.instance_count
  # instance_type      = "t2.micro"
  instance_type      = var.instance_type
  subnet_ids         = module.vpc.private_subnets[*]
  security_group_ids = [module.app_security_group.this_security_group_id]

  tags = {
    project     = "project-alpha",
    environment = "development"
  }
  
}
