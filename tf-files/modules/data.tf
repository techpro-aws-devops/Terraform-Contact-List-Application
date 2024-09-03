data "aws_vpc" "default" {
    default = true
}

data "aws_subnets" "defaultsubnets" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ami" "amazon-linux-2" {
  owners = ["amazon"]
  most_recent = true
  filter {
    name = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

data "aws_route53_zone" "selected" {
  name         = var.hosted-zone
}

data "template_file" "contactlistdb" {
  template = file("${abspath(path.module)}/userdata.sh")
  vars = {
    user-data-git-name = var.git-user
  }
}

data "aws_ssm_parameter" "ornek_parametre" {
  name = "git-token"
}

