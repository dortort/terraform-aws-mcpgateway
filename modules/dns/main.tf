locals {
  # Extract the parent zone from the custom domain.
  # e.g. "mcpgateway.example.com" -> "example.com"
  domain_parts = split(".", var.custom_domain)
  parent_zone  = join(".", slice(local.domain_parts, 1, length(local.domain_parts)))
}

data "aws_route53_zone" "main" {
  name         = local.parent_zone
  private_zone = false
}

resource "aws_acm_certificate" "mcpgw" {
  domain_name       = var.custom_domain
  validation_method = "DNS"

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.mcpgw.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "mcpgw" {
  certificate_arn         = aws_acm_certificate.mcpgw.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "mcpgw" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.custom_domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
