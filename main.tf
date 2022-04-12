# assumed resources that already exist:
# - vpc (set as default)
# - subnet in the VPC matching CIDR given https://us-west-1.console.aws.amazon.com/vpc/home?region=us-west-1#subnets
# - key pair https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#KeyPairs
# - vpc security group, allowing only 22 & 8080 to your home IP 'curl ipinfo.io/ip' https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#SecurityGroups:
# - ubuntu image from cannonical 
locals {
    instance_type = "t2.medium"
    key_name = "matttrach-initial"
    name = "mt-k3s-default"
    user = "matttrach"
    use = "onboarding"
    security_group = "sg-06bf73fa3affae222"
    vpc = "vpc-3d1f335a"
    subnet = "subnet-0835c74adb9e4a860"
    ami = "ami-01f87c43e618bf8f0"
}

data "aws_vpc" "selected" {
  default = true
}

resource "aws_instance" "k3s" {
  ami                    = local.ami
  instance_type          = local.instance_type
  vpc_security_group_ids = [local.security_group]
  subnet_id              = local.subnet
  key_name               = local.key_name
  instance_initiated_shutdown_behavior = "terminate"
  associate_public_ip_address = true
  user_data = <<-EOT
  #cloud-config
  disable_root: false
  EOT

  tags = {
    Name = "k3s-default"
    User = local.user
    Use  = local.use
  }

  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/local/bin/initial"
    agent       = true
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      max_attempts=15
      attempts=0
      interval=5
      while [ "$(cloud-init status)" != "status: done" ]; do
        echo "cloud init is \"$(cloud-init status)\""
        attempts=$(expr $attempts + 1)
        if [ $attempts = $max_attempts ]; then break; fi
        sleep $interval;
      done
    EOT
    ]
  }
}

resource "null_resource" "update" {
  depends_on = [
    aws_instance.k3s,
  ]
  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/local/bin/update"
    agent       = true
    host        = aws_instance.k3s.public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      apt update
    EOT
    ]
  }
}

resource "null_resource" "install" {
  depends_on = [
    aws_instance.k3s,
    null_resource.update,
  ]
  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/local/bin/install"
    agent       = true
    host        = aws_instance.k3s.public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      curl -sfL https://get.k3s.io | sh -
      sleep 15
      k3s kubectl get node
    EOT
    ]
  }
}
