terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"  // Defines the provider source
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
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

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "DistribtedImageProcessing VPC"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "myigw"
  }
}

# Create a Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "mysubnet"
  }
}

# Create a Route Table
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

# Associate the Route Table with the Public Subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a Security Group for the EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = "EC2 Security Group"
  description = "Allow inbound SSH, HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.my_vpc.id

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
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

# Create an EC2 instance
resource "aws_instance" "my_instance1" {
  ami = "${data.aws_ami.amazon-linux-2.id}"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id, aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.deployer_key.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_access_profile.name

  tags = {
    Name = "image_manipulator1"
  }
}

resource "aws_instance" "my_instance2" {
  ami = "${data.aws_ami.amazon-linux-2.id}"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id, aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  key_name = aws_key_pair.deployer_key.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_access_profile.name

  tags = {
    Name = "image_manipulator2"
  }
}

resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key"
  public_key = file("~/keypair_amazon/deployer_key.pub")
}


# IAM role for the EC2 instance
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

# IAM policy to grant S3 read and write permissions
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
          "${aws_s3_bucket.original_images.arn}/*",
          "${aws_s3_bucket.processed_images.arn}/*"
        ]
      },
    ]
  })
}

# Attach the IAM policy to the role
resource "aws_iam_role_policy_attachment" "ec2_s3_access_policy_attachment" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.s3_read_write_policy.arn
}

# Create an IAM instance profile for the EC2 instance
resource "aws_iam_instance_profile" "ec2_s3_access_profile" {
  name = "ec2_s3_access_profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_s3_bucket" "original_images" {
  bucket = "original-images-${random_pet.name.id}"  // Ensures global uniqueness

  tags = {
    Purpose = "Original Image Uploads"
  }
}


resource "aws_s3_bucket" "processed_images" {
  bucket = "processed-images-${random_pet.name.id}"  // Ensures global uniqueness

  tags = {
    Purpose = "Processed Image Downloads"
  }
}

resource "aws_s3_bucket_public_access_block" "original_images_public_acssess" {
  bucket = aws_s3_bucket.original_images.id

  block_public_acls       = false
  block_public_policy     = false
}
resource "aws_s3_bucket_public_access_block" "processed_images_public_acssess" {
  bucket = aws_s3_bucket.processed_images.id

  block_public_acls       = false
  block_public_policy     = false
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
        Resource  = [
          "${aws_s3_bucket.processed_images.arn}/*"
        ]
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
        Resource  = [
          "${aws_s3_bucket.original_images.arn}/*"
        ]
      },
    ]
  })
}

resource "random_pet" "name" {
  length    = 2
}
