mock_provider "aws" {}

variables {
  allowed_account_id = "000000000000"
  operator_cidr      = "203.0.113.10/32"
}

run "accepts_ipv4_host_32" {
  command = plan
}

run "rejects_31" {
  command = plan

  variables {
    operator_cidr = "203.0.113.10/31"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_24" {
  command = plan

  variables {
    operator_cidr = "203.0.113.0/24"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_1" {
  command = plan

  variables {
    operator_cidr = "128.0.0.0/1"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_0" {
  command = plan

  variables {
    operator_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_ipv6" {
  command = plan

  variables {
    operator_cidr = "2001:db8::1/128"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_garbage" {
  command = plan

  variables {
    operator_cidr = "not-a-cidr"
  }

  expect_failures = [var.operator_cidr]
}

run "rejects_leading_zero_octet" {
  command = plan

  variables {
    operator_cidr = "010.0.0.1/32"
  }

  expect_failures = [var.operator_cidr]
}
