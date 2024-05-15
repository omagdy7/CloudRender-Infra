terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "DistributedImageProcessing VPC"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "myigw"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public_subnet_2"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "myrt"
  }
}

resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "eks_sg" {
  name        = "EKS Security Group"
  description = "Allow all traffic for EKS nodes"
  vpc_id      = aws_vpc.my_vpc.id

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
    Name = "EKS Security Group"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "EC2 Security Group"
  description = "Allow inbound SSH, HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 5672
    to_port     = 5672
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
    Name = "EC2 Security Group"
  }
}

resource "aws_instance" "my_instance1" {
  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deployer_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_access_profile.name

  tags = {
    Name = "image_manipulator1"
  }
}

resource "aws_instance" "my_instance2" {
  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_2.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deployer_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_access_profile.name

  tags = {
    Name = "image_manipulator2"
  }
}

resource "aws_instance" "rabbitmq-instance" {
  ami                         = data.aws_ami.amazon-linux-2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deployer_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_access_profile.name

  user_data = <<-EOF
              #!/bin/bash
              # Install Docker
              sudo yum update -y
              sudo amazon-linux-extras install docker -y
              sudo service docker start
              sudo usermod -a -G docker ec2-user

              # Run RabbitMQ server using Docker
              sudo docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management
              EOF

  tags = {
    Name = "rabbitmq-server"
  }
}

resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key"
  public_key = file("~/keypair_amazon/deployer_key.pub")
}

resource "aws_iam_role" "ec2_s3_access_role" {
  name = "ec2_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "s3_read_write_policy" {
  name        = "s3_read_write_policy"
  description = "Policy that allows S3 read and write access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ],
        Effect = "Allow",
        Resource = [
          format("${aws_s3_bucket.original_images.arn}/*"),
          format("${aws_s3_bucket.processed_images.arn}/*")
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_access_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.s3_read_write_policy.arn
}

resource "aws_iam_instance_profile" "ec2_s3_access_profile" {
  name = "ec2_s3_access_profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_s3_bucket" "original_images" {
  bucket = "original-images-${random_pet.name.id}"

  tags = {
    Purpose = "Original Image Uploads"
  }
}

resource "aws_s3_bucket" "processed_images" {
  bucket = "processed-images-${random_pet.name.id}"

  tags = {
    Purpose = "Processed Image Downloads"
  }
}

resource "aws_s3_bucket_public_access_block" "original_images_public_access" {
  bucket = aws_s3_bucket.original_images.id

  block_public_acls   = false
  block_public_policy = false
  depends_on = [aws_s3_bucket.original_images]
}

resource "aws_s3_bucket_public_access_block" "processed_images_public_access" {
  bucket = aws_s3_bucket.processed_images.id

  block_public_acls   = false
  block_public_policy = false

  depends_on = [aws_s3_bucket.processed_images]
}

resource "aws_s3_bucket_policy" "processed_images_allow_read_policy" {
  bucket = aws_s3_bucket.processed_images.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = format("${aws_s3_bucket.processed_images.arn}/*")
      },
    ]
  })
}

resource "aws_s3_bucket_policy" "original_images_allow_read_policy" {
  bucket = aws_s3_bucket.original_images.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = format("${aws_s3_bucket.original_images.arn}/*")
      },
    ]
  })
}

resource "random_pet" "name" {
  length = 2
}

resource "aws_ecr_repository" "backend_repo" {
  name = "cloudrender-backend"
}

resource "aws_ecr_repository" "worker_repo" {
  name = "cloudrender-worker"
}

resource "aws_eks_cluster" "backend_cluster" {
  name     = "cloudrender-backend-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_policy_attachment]
}

resource "aws_eks_node_group" "backend_cluster_node_group" {
  cluster_name    = aws_eks_cluster.backend_cluster.name
  node_group_name = "cloudrender-backend-node-group"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_eks_cluster.backend_cluster,
    aws_iam_role_policy_attachment.node_group_policy_attachment_eks_worker,
    aws_iam_role_policy_attachment.node_group_policy_attachment_ecr,
    aws_iam_role_policy_attachment.node_group_policy_attachment_cni
  ]
}

resource "aws_iam_role" "eks_role" {
  name = "eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_role.name
}

resource "aws_iam_role" "node_group_role" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_group_policy_attachment_eks_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
  depends_on = [aws_iam_role.node_group_role]
}

resource "aws_iam_role_policy_attachment" "node_group_policy_attachment_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
  depends_on = [aws_iam_role.node_group_role]
}

resource "aws_iam_role_policy_attachment" "node_group_policy_attachment_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
  depends_on = [aws_iam_role.node_group_role]
}
