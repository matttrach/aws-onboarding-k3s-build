# assumed resources that already exist:
# - vpc (set as default)
# - subnet in the VPC matching CIDR given https://us-west-1.console.aws.amazon.com/vpc/home?region=us-west-1#subnets
# - key pair https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#KeyPairs
# - vpc security group, allowing only 22 & 8080 to your home IP 'curl ipinfo.io/ip' https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#SecurityGroups:
# - ubuntu image from cannonical 
locals {
    instance_type   = "t2.medium"
    key_name        = "matttrach-initial"
    user            = "matttrach"
    use             = "onboarding"
    security_group  = "sg-06bf73fa3affae222"
    vpc             = "vpc-3d1f335a"
    subnet          = "subnet-0835c74adb9e4a860"
    ami             = "ami-01f87c43e618bf8f0"
    servers         = toset(["k3s0","k3s1","k3s2"])
    agents          = toset(["k3s1","k3s2"])
}

resource "random_uuid" "cluster_token" {
}

resource "aws_instance" "k3s" {
  for_each                    = local.servers
  ami                         = local.ami
  instance_type               = local.instance_type
  vpc_security_group_ids      = [local.security_group]
  subnet_id                   = local.subnet
  key_name                    = local.key_name
  associate_public_ip_address = true
  instance_initiated_shutdown_behavior = "terminate"
  user_data = <<-EOT
  #cloud-config
  disable_root: false
  EOT

  tags = {
    Name = each.key
    User = local.user
    Use  = local.use
  }

  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/bin/initial"
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

resource "null_resource" "server" {
  depends_on = [
    aws_instance.k3s,
  ]
  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/bin/server"
    agent       = true
    host        = aws_instance.k3s["k3s0"].public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      curl -sfL https://get.k3s.io | K3S_TOKEN=${random_uuid.cluster_token.result} sh -
      sleep 15
      k3s kubectl get node
    EOT
    ]
  }
}

resource "null_resource" "agents" {
  depends_on = [
    aws_instance.k3s,
    null_resource.server,
  ]
  for_each = local.agents
  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/bin/agents"
    agent       = true
    host        = aws_instance.k3s[each.key].public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      curl -sfL https://get.k3s.io | K3S_TOKEN=${random_uuid.cluster_token.result} K3S_URL="https://${aws_instance.k3s["k3s0"].public_dns}:6443" sh -
      sleep 15
    EOT
    ]
  }
}

resource "null_resource" "validate" {
  depends_on = [
    aws_instance.k3s,
    null_resource.server,
    null_resource.agents,
  ]
  connection {
    type        = "ssh"
    user        = "root"
    script_path = "/usr/bin/validate"
    agent       = true
    host        = aws_instance.k3s["k3s0"].public_ip
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      k3s kubectl get node
    EOT
    ]
  }
}
