provider "aws" {
  region = var.region
}

# -------------------------------
# Create VPC
# -------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# -------------------------------
# Create Internet Gateway (for Internet access)
# -------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# -------------------------------
# Create Public Subnet
# -------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true  # <-- ensures EC2 gets public IP

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# -------------------------------
# Create Route Table with Route to Internet
# -------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------------
# Security Group - Allow SSH
# -------------------------------
resource "aws_security_group" "public_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Public SSH (use cautiously)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_security_group_rule" "icmp_between_instances" {
  type                     = "ingress"
  from_port                = -1
  to_port                  = -1
  protocol                 = "icmp"
  security_group_id        = aws_security_group.public_sg.id
  source_security_group_id = aws_security_group.public_sg.id
}

resource "aws_security_group_rule" "ssh_between_instances" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.public_sg.id
  source_security_group_id = aws_security_group.public_sg.id
}

# -------------------------------
#  Fetch Free-Tier Eligible Amazon Linux 2 AMI
# -------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ---------------------------------
# Generate SSH key for Ansible
# ---------------------------------
resource "tls_private_key" "ansible_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key locally
resource "local_file" "ansible_private_key" {
  filename        = "${path.module}/ansible_key.pem"
  content         = tls_private_key.ansible_key.private_key_pem
  file_permission = "0600"
}

# resource "aws_instance" "public_ec2" {
#   count         = var.instance_count
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = var.instance_type
#   subnet_id     = aws_subnet.public.id
#   vpc_security_group_ids = [aws_security_group.public_sg.id]
#   associate_public_ip_address = true

#   # Controller instance (index = 0)
#   user_data = (count.index == 0 ?
#   <<-EOF
# #!/bin/bash
# yum update -y
# amazon-linux-extras install ansible2 -y

# mkdir -p /home/ec2-user/.ssh
# chmod 700 /home/ec2-user/.ssh

# # Add public key so controller can SSH to all nodes
# echo "${tls_private_key.ansible_key.public_key_openssh}" >> /home/ec2-user/.ssh/authorized_keys
# chmod 600 /home/ec2-user/.ssh/authorized_keys

# # Add private key ONLY on controller
# cat << 'EOFKEY' > /home/ec2-user/.ssh/ansible_key.pem
# ${tls_private_key.ansible_key.private_key_pem}
# EOFKEY

# chmod 600 /home/ec2-user/.ssh/ansible_key.pem
# chown -R ec2-user:ec2-user /home/ec2-user/.ssh
# EOF
#   :
#   # Managed nodes (index > 0)
#   <<-EOF
# #!/bin/bash
# yum update -y

# mkdir -p /home/ec2-user/.ssh
# chmod 700 /home/ec2-user/.ssh

# # Only public key for SSH from controller
# echo "${tls_private_key.ansible_key.public_key_openssh}" >> /home/ec2-user/.ssh/authorized_keys
# chmod 600 /home/ec2-user/.ssh/authorized_keys
# chown -R ec2-user:ec2-user /home/ec2-user/.ssh
# EOF
#   )

#   tags = {
#     Name = "${var.project_name}-instance-${count.index + 1}"
#   }
# }

resource "aws_instance" "controller" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]

  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
yum update -y
amazon-linux-extras install ansible2 -y

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh

# Add public key
echo "${tls_private_key.ansible_key.public_key_openssh}" >> /home/ec2-user/.ssh/authorized_keys

# Add private key
cat << 'EOFKEY' > /home/ec2-user/.ssh/ansible_key.pem
${tls_private_key.ansible_key.private_key_pem}
EOFKEY

chmod 600 /home/ec2-user/.ssh/ansible_key.pem
chmod 600 /home/ec2-user/.ssh/authorized_keys
chown -R ec2-user:ec2-user /home/ec2-user/.ssh
EOF

  tags = {
    Name = "${var.project_name}-controller"
  }
}

resource "aws_instance" "worker" {
  count         = var.instance_count - 1
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]

  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
yum update -y

mkdir -p /home/ec2-user/.ssh
chmod 700 /home/ec2-user/.ssh

# Worker only gets public key for SSH from controller
echo "${tls_private_key.ansible_key.public_key_openssh}" >> /home/ec2-user/.ssh/authorized_keys

chmod 600 /home/ec2-user/.ssh/authorized_keys
chown -R ec2-user:ec2-user /home/ec2-user/.ssh
EOF

  tags = {
    Name = "${var.project_name}-worker-${count.index + 1}"
  }
}



# # -------------------------------
# #  Create EC2 Instances
# # -------------------------------
# resource "aws_instance" "public_ec2" {
#   count         = var.instance_count
#   ami           = data.aws_ami.amazon_linux.id
#   instance_type = var.instance_type
#   subnet_id     = aws_subnet.public.id
#   key_name      = var.key_name
#   vpc_security_group_ids = [aws_security_group.public_sg.id]

#   associate_public_ip_address = true  # ensure public IP is attached

#   user_data = <<-EOF
#               #!/bin/bash
#               # Update packages
#               yum update -y

#               # Install EPEL repo and Ansible
#               amazon-linux-extras install ansible2 -y

#               # (Optional) Verify installation and log
#               ansible --version > /tmp/ansible_install.log 2>&1
#               EOF

#   tags = {
#     Name = "${var.project_name}-instance-${count.index + 1}"
#     Environment = var.environment
#   }
# }
