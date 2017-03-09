provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_vpc" "vpc" {
  cidr_block = "${var.cidr_block}"
  enable_dns_support = "${var.dns_support}"
  enable_dns_hostnames = "${var.dns_support}"
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-vpc"))))}"
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = "${var.environment}-aws_vpc_log_group"
}

resource "aws_iam_role" "flowlogrole" {
    name = "${var.environment}-flow_logs_role"
    assume_role_policy = "${data.template_file.flowlog-assumerole.rendered}"
}

resource "aws_iam_role_policy" "flowlogs" {
  name = "${var.environment}-tf-VPCFlowLog"
  role =  "${aws_iam_role.flowlogrole.id}"
  policy = "${data.template_file.tf-VPCFlowLogsAccess.rendered}"
}

resource "aws_flow_log" "flow_log" {
  log_group_name = "${aws_cloudwatch_log_group.log_group.name}"
  iam_role_arn = "${aws_iam_role.flowlogrole.arn}"
  vpc_id = "${aws_vpc.vpc.id}"
  traffic_type = "${var.flow_log_traffic_type}"
  depends_on = ["aws_cloudwatch_log_group.log_group"]
}

resource "aws_subnet" "pub_subnet" {
  count = "${var.az_count * length(var.pub_subnet_name)}"
  availability_zone = "${element(data.aws_availability_zones.azs.names, count.index % var.az_count)}"
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "${cidrsubnet(var.cidr_block, 8, count.index)}"
  map_public_ip_on_launch = true
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-", element(var.pub_subnet_name, count.index / var.az_count), "-public-subnet-", element(data.aws_availability_zones.azs.names, count.index % var.az_count)))))}"
}

resource "aws_subnet" "priv_subnet" {
  count = "${var.az_count * length(var.priv_subnet_name)}"
  availability_zone = "${element(data.aws_availability_zones.azs.names, count.index % var.az_count)}"
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "${cidrsubnet(var.cidr_block, 8, count.index + var.az_count * length(var.pub_subnet_name))}"
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-", element(var.priv_subnet_name, count.index / var.az_count), "-private-subnet-", element(data.aws_availability_zones.azs.names, count.index % var.az_count)))))}"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags = "${var.standard_tags}"
}

resource "aws_eip" "nat_gateway" {
  count = "${var.az_count}"
  vpc = true
}

resource "aws_nat_gateway" "gateway" {
  count = "${var.az_count}"
  allocation_id = "${element(aws_eip.nat_gateway.*.id, count.index)}"
  subnet_id = "${element(aws_subnet.pub_subnet.*.id, count.index)}"
}

resource "aws_route_table" "pub" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-public_route_table"))))}"
}

resource "aws_route_table_association" "pub" {
  count = "${var.az_count * length(var.pub_subnet_name)}"
  subnet_id = "${element(aws_subnet.pub_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.pub.id}"
}

resource "aws_route_table" "priv" {
  count = "${var.az_count}"
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${element(aws_nat_gateway.gateway.*.id, count.index)}"
  }
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-private_route_table-", element(data.aws_availability_zones.azs.names, count.index)))))}"
}

resource "aws_route_table_association" "priv" {
  count = "${var.az_count * length(var.priv_subnet_name)}"
  subnet_id = "${element(aws_subnet.priv_subnet.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.priv.*.id, count.index % var.az_count)}"
}

resource "aws_vpc_endpoint" "s3e" {
  vpc_id = "${aws_vpc.vpc.id}"
  route_table_ids = ["${aws_route_table.priv.*.id}", "${aws_route_table.pub.id}"]
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

resource "aws_network_acl" "nacl_common" {
  vpc_id = "${aws_vpc.vpc.id}"
  subnet_ids = [ "${aws_subnet.priv_subnet.*.id}", "${aws_subnet.pub_subnet.*.id}" ]
  tags = "${merge(var.standard_tags, map("Name", join("", list(var.environment,  "-common-nacl"))))}"
}

resource "aws_network_acl_rule" "common-nacl-rule-egress-allow" {
  network_acl_id = "${aws_network_acl.nacl_common.id}"
  rule_number = 32766
  egress = true
  protocol = -1
  rule_action = "allow"
  cidr_block = "0.0.0.0/0"
  from_port = 0
  to_port = 0
}

resource "aws_network_acl_rule" "common-nacl-rule-ingress-allow" {
  network_acl_id = "${aws_network_acl.nacl_common.id}"
  rule_number = 32766
  egress = false
  protocol = -1
  rule_action = "allow"
  cidr_block = "0.0.0.0/0"
  from_port = 0
  to_port = 0
}

resource "aws_network_acl_rule" "common-nacl-rule-egress" {
  count = "${length(var.nacl_egress_deny_rules)}"
  network_acl_id = "${aws_network_acl.nacl_common.id}"
  rule_number = "${count.index * 10 + 100}"
  egress = true
  protocol = "${element(split(",", element(var.nacl_egress_deny_rules, count.index)), 0)}"
  rule_action = "deny"
  cidr_block = "0.0.0.0/0"
  from_port = "${element(split("-", element(split(",", element(var.nacl_egress_deny_rules, count.index)), 1)), 0)}"
  to_port = "${element(split("-", element(split(",", element(var.nacl_egress_deny_rules, count.index)), 1)), 1)}"
}

resource "aws_network_acl_rule" "common-nacl-rule-ingress" {
  count = "${length(var.nacl_egress_deny_rules)}"
  network_acl_id = "${aws_network_acl.nacl_common.id}"
  rule_number = "${count.index * 10 + 100}"
  egress = false
  protocol = "${element(split(",", element(var.nacl_egress_deny_rules, count.index)), 0)}"
  rule_action = "deny"
  cidr_block = "0.0.0.0/0"
  from_port = "${element(split("-", element(split(",", element(var.nacl_ingress_deny_rules, count.index)), 1)), 0)}"
  to_port = "${element(split("-", element(split(",", element(var.nacl_ingress_deny_rules, count.index)), 1)), 1)}"
}
