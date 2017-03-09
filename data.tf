data "aws_availability_zones" "azs" {}

data "template_file" "tf-VPCFlowLogsAccess" {
  template = "${file("${path.module}/templates/tf-VPCFlowLog.json.tpl")}"
}

data "template_file" "flowlog-assumerole" {
  template = "${file("${path.module}/templates/assume-role-policy.json.tpl")}"
  vars {
    aws_service = "vpc-flow-logs.amazonaws.com"
  }
}
