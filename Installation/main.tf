terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.42.0"
    }
  }
}

# 1. Define the Provider
provider "aws" {
  region = "ap-northeast-3" # Change to your preferred region
}

# Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# 2. Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# 3. Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main-igw"
  }
}

# 4. Create Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-3a"
  tags = {
    Name = "public-subnet"
  }
}

# 5. Create Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# 6. Associate Route Table with Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 7. Create Security Group (Allow SSH,HTTP,All traffic)
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow SSH, HTTP, All traffic"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict in real use
  }

  ingress {
    description = "HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg"
  }
}

# 8.Security Group for Kubernetes Cluster
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-cluster-sg"
  description = "Security group for kubeadm cluster"
  vpc_id = aws_vpc.main_vpc.id

  # Internal: Allow all traffic between nodes in the same SG
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Master: Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Recommendation: Restrict to your IP
  }

  # Master: etcd server client API
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
  }

  # All Nodes: Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
  }

  # Master: kube-scheduler and kube-controller-manager
  ingress {
    from_port = 10257
    to_port   = 10259
    protocol  = "tcp"
    self      = true
  }

  # Worker: NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 8. Launch 3 EC2 Instances
# Master Node
resource "aws_instance" "master" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.medium" # 2 vCPU, 4GB RAM
  subnet_id = aws_subnet.public_subnet.id
  key_name      = "your-key-pair"
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  tags = {
    Name = "k8s-master"
    Role = "master"
  }
}

# Worker Nodes
resource "aws_instance" "worker" {
  count         = 2 # Adjust number of workers here
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.small" # 2 vCPU, 2GB RAM
  subnet_id = aws_subnet.public_subnet.id
  key_name      = "your-key-pair"
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  tags = {
    Name = "k8s-worker-${count.index}"
    Role = "worker"
  }
}

# Jenkins & Monitoring Server
resource "aws_instance" "ec2_instances" {
  for_each = {
    jenkinsServer = "t2.medium"
    monitoringServer = "t2.micro"
  }

  ami           = data.aws_ami.amazon_linux_2023.id #Dynamic AMI value
  instance_type = each.value
  subnet_id     = aws_subnet.public_subnet.id

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  key_name = "your-keypair-name"

  tags = {
    Name = each.key
  }
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker_public_ips" {
  value = aws_instance.worker[*].public_ip
}

output "ec2_instances_public_ips" {
  value = { for k, v in aws_instance.ec2_instances : k => v.public_ip }
}