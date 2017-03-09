variable "aws_region" {type = "string"}

variable "standard_tags" {type = "map"}

variable "environment" {type = "string"}

variable "cidr_block" {type = "string"}

variable "az_count" {type = "string"}

variable "dns_support" {type = "string"}

variable "pub_subnet_name" {type = "list"}
variable "priv_subnet_name" {type = "list"}

variable "nacl_egress_deny_rules" {
  type = "list"
  default = [
    "tcp,20-21",
    "tcp,23-23",
    "tcp,110-110",
    "tcp,143-143",
    "udp,161-162"
  ]
}
variable "nacl_ingress_deny_rules" {
  type = "list"
  default = [
    "tcp,20-21",
    "tcp,23-23",
    "tcp,110-110",
    "tcp,143-143",
    "udp,161-162"
  ]
}

variable "flow_log_traffic_type" {
  type = "string"
  default = "ALL"
}

output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}
