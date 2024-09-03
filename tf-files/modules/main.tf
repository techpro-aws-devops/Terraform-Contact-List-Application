locals {
  tag="contactlist"
}

resource "aws_security_group" "alb-sg" {
  name = "ALBSecurityGroup"
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "${local.tag}-ALBSecurityGroup"
  }
  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "ec2-sg" {
  name = "WebServerSecurityGroup"
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "${local.tag}-WebServerSecurityGroup"
  }

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    security_groups = [aws_security_group.alb-sg.id]
  }

  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

}


resource "aws_security_group" "db-sg" {
  name = "RDSSecurityGroup"
  vpc_id = data.aws_vpc.default.id
  tags = {
    "Name" = "${local.tag}-RDSSecurityGroup"
  }
  ingress {
    security_groups = [aws_security_group.ec2-sg.id]
    from_port = 3306
    protocol = "tcp"
    to_port = 3306
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    protocol = -1
    to_port = 0
  }
}


resource "aws_launch_template" "contactlist-lt" {
  name = "contactlist-lt"
  image_id = data.aws_ami.amazon-linux-2.id
  instance_type = "t2.micro"
  key_name = var.key-name
  vpc_security_group_ids = [aws_security_group.ec2-sg.id]
  user_data = base64encode(data.template_file.contactlistdb.rendered)
  depends_on = [github_repository_file.dbendpoint]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.tag}-LaunchTemplate"
    }
  }
}

resource "github_repository_file" "dbendpoint" {
  content = aws_db_instance.db-server.address
  file = "dbserver.endpoint"
  repository = "Terraform-Contact-List-Application"
  overwrite_on_create = true
  branch = "main"
}


resource "aws_db_subnet_group" "default" {
  name       = "contactlist"
  subnet_ids = data.aws_subnets.defaultsubnets.ids

  tags = {
    Name = "${local.tag}-subnet group"
  }
}


resource "aws_db_instance" "db-server" {
  instance_class = "db.t3.micro"
  allocated_storage = 20
  vpc_security_group_ids = [aws_security_group.db-sg.id]
  allow_major_version_upgrade = false
  auto_minor_version_upgrade = true
  backup_retention_period = 0
  db_subnet_group_name = aws_db_subnet_group.default.name
  identifier = "contactlist-app-db"
  db_name = "contactlist"
  engine = "mysql"
  engine_version = "8.0.35"
  username = "techpro"
  password = "techpro123"
  monitoring_interval = 0
  multi_az = false
  port = 3306
  publicly_accessible = false
  skip_final_snapshot = true

}

resource "aws_autoscaling_group" "app-asg" {
  max_size = 3
  min_size = 1
  desired_capacity = 2
  name = "contactlist-asg"
  health_check_grace_period = 60
  health_check_type = "ELB"
  target_group_arns = [aws_alb_target_group.app-lb-tg.arn]
  vpc_zone_identifier = aws_alb.app-lb.subnets
  launch_template {
    id = aws_launch_template.contactlist-lt.id
    version = aws_launch_template.contactlist-lt.latest_version
  }
}



resource "aws_alb" "app-lb" {
  name = "contactlist-lb-tf"
  ip_address_type = "ipv4"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb-sg.id]
  subnets = data.aws_subnets.defaultsubnets.ids
}

resource "aws_alb_listener" "app-listener" {
  load_balancer_arn = aws_alb.app-lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.app-lb-tg.arn
  }
}

resource "aws_alb_target_group" "app-lb-tg" {
  name = "contactlist-lb-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 3
  }
}



resource "aws_route53_record" "contactlist" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${var.env}.${var.hosted-zone}"
  type    = "A"

  alias {
    name                   = aws_alb.app-lb.dns_name
    zone_id                = aws_alb.app-lb.zone_id
    evaluate_target_health = true
  }
}
