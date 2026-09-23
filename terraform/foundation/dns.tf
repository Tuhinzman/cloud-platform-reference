resource "aws_route53_zone" "public" {
  name = var.public_domain

  tags = {
    Component = "dns"
  }

  # Deleting the zone while the registrar still delegates to it leaves a dangling delegation
  # that another account's zone could answer for.
  lifecycle {
    prevent_destroy = true
  }
}

output "public_zone_name_servers" {
  description = "Name servers to set at the registrar for the public domain."
  value       = aws_route53_zone.public.name_servers
}
