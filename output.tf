output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

# output "public_instance_public_ips" {
#   value = aws_instance.public_ec2[*].public_ip
# }

# output "public_instance_ids" {
#   value = aws_instance.public_ec2[*].id
# }

output "controller_ip" {
  value = aws_instance.controller.public_ip
}

output "worker_ips" {
  value = aws_instance.worker[*].public_ip
}
