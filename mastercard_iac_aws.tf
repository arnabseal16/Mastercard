provider "aws" {
  profile = "default"
  region = "us-east-1"
}
resource "aws_vpc" "vpc_msc1" {
  cidr_block = "10.0.0.0/16"

  tags = {
      Name = "msc1"
      Type = "vpc"
  }
}
resource "aws_eip" "nat" {
  vpc = true
  tags = {
    Name = "Nat_EIP"
    Type = "eip"
  }
}
resource "aws_internet_gateway" "igw_msc1" {
  vpc_id = aws_vpc.vpc_msc1.id

  tags = {
    Name = "IGW"
    Type = "Internet Gateway"
  }
}
resource "aws_route_table" "igw_route_msc1" {
  vpc_id = aws_vpc.vpc_msc1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_msc1.id
  }
  tags = {
      Name = "IGW_RoutingTable"
      Type = "Routing Table"
  }
}
resource "aws_route_table_association" "igw_route_assoc_msc1" {
  subnet_id = aws_subnet.sub_pub_msc1.id
  route_table_id = aws_route_table.igw_route_msc1.id
  
}
resource "aws_route_table" "nat_route_msc1" {
  vpc_id = aws_vpc.vpc_msc1.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw_msc1.id
  }
  tags = {
    Name = "NAT_RoutingTable"
    Type = "Routing Table"
  }
}
resource "aws_route_table_association" "nat_route_assoc_msc1" {
  subnet_id = aws_subnet.sub_priv_msc1.id
  route_table_id = aws_route_table.nat_route_msc1.id
}
resource "aws_nat_gateway" "natgw_msc1" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.sub_pub_msc1.id
  depends_on = [aws_internet_gateway.igw_msc1]
  tags = {
    Name = "NatGW"
    Type = "Nat Gateway"
  }
}
resource "aws_subnet" "sub_priv_msc1" {
  vpc_id     = aws_vpc.vpc_msc1.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "PrivSub"
    Type = "subnet"
    SubnetType = "Private"
  }
}
resource "aws_subnet" "sub_pub_msc1" {
  vpc_id     = aws_vpc.vpc_msc1.id
  cidr_block = "10.0.100.0/27"

  tags = {
    Name = "PubSub"
    Type = "subnet"
    SubnetType = "Public"
  }
}
resource "aws_security_group" "sec_group1_msc1" {
  name = "sec_group_1_msc1"
  description = "Security Group v1"
  vpc_id = aws_vpc.vpc_msc1.id
  ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port = 8080
      to_port = 8080
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port = 8
      to_port = 0
      protocol = "icmp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port = 443
      to_port = 443
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
      Name = "SecGroup"
      Type = "Security Group"
  }

}
resource "aws_launch_configuration" "asg_launch_config_msc1" {
  image_id = "ami-0e70db31f7e942241"
  instance_type = "m5.large"
  security_groups = [aws_security_group.sec_group1_msc1.id]
  root_block_device {
      volume_size = 50
  }
  key_name = "pemtest"
  ebs_block_device {
      volume_size = 200
      device_name = "/dev/sda2"
      delete_on_termination = false

  }
  
  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd
              service httpd start
              chkconfig httpd on
              f1=`lsblk | tail -n1 | awk '{print $1}'`
              sudo mkfs -t ext4 /dev/$f1
              sudo mount /dev/$f1 /var/log
              sed -i s/"#PermitRootLogin yes"/"PermitRootLogin yes"/g /etc/ssh/sshd_config
              sed -i s/"PasswordAuthentication no"/"PasswordAuthentication yes"/g /etc/ssh/sshd_config
              echo "Redhat@123" | passwd ec2-user --stdin
              echo "Redhat@123" | passwd root --stdin
              service sshd restart
              EOF
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "asg_msc1" {
  name = "MSC-ASG-v1"
  launch_configuration = aws_launch_configuration.asg_launch_config_msc1.name
  vpc_zone_identifier = [ aws_subnet.sub_priv_msc1.id ]
  min_size = 2
  max_size = 20
  load_balancers = [aws_elb.elb_msc1.name]
  health_check_type = "ELB"
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_policy" "asg_policy_msc1" {
  name                   = "MSC1_Autoscaling_Policy"
  scaling_adjustment     = 4
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg_msc1.name
}
resource "aws_autoscaling_notification" "asg_notification_msc1" {
  group_names = [ aws_autoscaling_group.asg_msc1.name]
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.sns_msc1.arn
}
resource "aws_sns_topic" "sns_msc1" {
  name = "ASG_Topic_MSC1"
}


resource "aws_elb" "elb_msc1" {
  name = "MSC-ELB-v1"
  security_groups = [ aws_security_group.sec_group1_msc1.id ]
  subnets = [ aws_subnet.sub_pub_msc1.id, aws_subnet.sub_priv_msc1.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

}
resource "aws_instance" "bast1_msc1" {
  instance_type = "t2.micro"
  ami = "ami-0e70db31f7e942241"
  subnet_id = aws_subnet.sub_pub_msc1.id
  security_groups = [aws_security_group.sec_group1_msc1.id]
  key_name = "pemtest"
  disable_api_termination = false
  ebs_optimized = false
  root_block_device {
    volume_size = "10"
  }
  tags = {
    "Name" = "Bastion Host"
  }
  user_data = <<-EOF
              #!/bin/bash
              sed -i s/"#PermitRootLogin yes"/"PermitRootLogin yes"/g /etc/ssh/sshd_config
              sed -i s/"PasswordAuthentication no"/"PasswordAuthentication yes"/g /etc/ssh/sshd_config
              echo "Redhat@123" | passwd ec2-user --stdin
              echo "Redhat@123" | passwd root --stdin
              service sshd restart
              EOF
}
resource "aws_eip" "bast1_eip" {
  instance = aws_instance.bast1_msc1.id
  vpc = true
}
