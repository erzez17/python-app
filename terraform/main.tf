terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  region  = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.12.0"

  name                 = "erez-reali-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

}

resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id = module.vpc.vpc_id
  cidr_block = "10.64.0.0/16"
}

resource "aws_subnet" "ng_subnet_1a" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary_cidr.vpc_id
  cidr_block = "10.64.0.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "eks-ng"
  }
}

resource "aws_subnet" "ng_subnet_1b" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary_cidr.vpc_id
  cidr_block = "10.64.32.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "eks-ng"
  }
}

resource "aws_subnet" "ng_subnet_1c" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary_cidr.vpc_id
  cidr_block = "10.64.64.0/24"
  availability_zone = "us-east-1c"
  tags = {
    Name = "eks-ng"
  }
}

module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name            = "eks-ng"
  cluster_name    = var.cluster_name
  cluster_version = "1.21"

  vpc_id = module.vpc.vpc_id
  subnet_ids = [aws_subnet.ng_subnet_1a.id , aws_subnet.ng_subnet_1a.id, aws_subnet.ng_subnet_1a.id]

  min_size     = 1
  max_size     = 5
  desired_size = 2

  instance_types = ["t3.small"]

}

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = "1.21"
  subnets         = module.vpc.private_subnets
  version = "17.0.0"
  cluster_create_timeout = "1h"
  cluster_endpoint_private_access = true

  vpc_id = module.vpc.vpc_id

}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

resource "kubernetes_deployment" "reali-app-deployment" {
  metadata {
    name = "reali-app-deployment"
    labels = {
      app = "reali-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "reali-app"
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge = 1
        max_unavailable = 1
        }
    }
    template {
      metadata {
        labels = {
          app = "reali-app"
        }
      }

      spec {
        container {
          image = "erzez/reali-app:latest"
          name  = "reali-app"
        }
      }
    }
  }
}

resource "kubernetes_service" "reali-svc" {
  metadata {
    name = "reali-svc"
  }
  spec {
    selector = {
      app = "reali-app"
    }
    port {
      port        = 5000
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}