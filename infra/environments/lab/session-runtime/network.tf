resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Accepted 2026-10-03: disposable lab uses public IPv4 instead of a paid NAT.
# Inbound is limited to the supplied Minecraft /32; no SSH; destroy after testing.
# Review by 2026-12-31 or before long-lived use or sensitive data.
#trivy:ignore:AWS-0164
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.42.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-public"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = {
    Name = "${local.name_prefix}-s3"
  }
}

resource "aws_security_group" "minecraft" {
  name        = "${local.name_prefix}-minecraft"
  description = "Minecraft server traffic"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "${local.name_prefix}-minecraft"
  }
}

# No inbound rule is created until an IPv4 /32 is supplied.
resource "aws_vpc_security_group_ingress_rule" "minecraft" {
  count = var.allowed_client_cidr == "" ? 0 : 1

  security_group_id = aws_security_group.minecraft.id
  cidr_ipv4         = var.allowed_client_cidr
  ip_protocol       = "tcp"
  from_port         = 25565
  to_port           = 25565
  description       = "Minecraft Java from the allowed client"
}

# Accepted 2026-10-03: SSM and fixed JDK/Minecraft downloads need public endpoints.
# Only TCP 443 is allowed; destination trust/TLS is not enforced by this rule.
# Disposable data, limited instance IAM and same-session teardown are required.
# Review by 2026-12-31 or before long-lived use or sensitive data.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.minecraft.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS for SSM and server setup"
}
