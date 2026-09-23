# Validated through the zone in dns.tf, so apply only after the registrar delegates to it.
resource "aws_acm_certificate" "public" {
  domain_name               = var.public_domain
  subject_alternative_names = ["*.${var.public_domain}"]
  validation_method         = "DNS"

  # Exportable public certificates are charged; ADR-0013 requires the non-exportable form.
  options {
    export = "DISABLED"
  }

  tags = {
    Component = "dns"
  }

  # A replacement has a new ARN: it is created first, and the old certificate deletes only once
  # the ingress annotation no longer references it.
  lifecycle {
    create_before_destroy = true
  }
}

# ACM gives the apex and its wildcard the same validation record, so one record validates both.
locals {
  certificate_validation = one([
    for option in aws_acm_certificate.public.domain_validation_options : option
    if option.domain_name == var.public_domain
  ])
}

resource "aws_route53_record" "certificate_validation" {
  zone_id = aws_route53_zone.public.zone_id
  name    = local.certificate_validation.resource_record_name
  type    = local.certificate_validation.resource_record_type
  records = [local.certificate_validation.resource_record_value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "public" {
  certificate_arn         = aws_acm_certificate.public.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}

output "public_certificate_arn" {
  description = "ARN of the validated certificate, for the ingress annotation."
  value       = aws_acm_certificate_validation.public.certificate_arn
}
