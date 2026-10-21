# ADR-0007: Networking and traffic access

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## What we will use

Use one VPC per environment across two Availability Zones.
Environments do not share a VPC.

Keep EKS nodes and workloads in private subnets without direct public
exposure. Public subnets are for managed components that need public
placement, such as the load balancer and NAT Gateway.

Route public application traffic through one managed load-balancing
boundary. Require HTTPS, redirect HTTP to HTTPS and terminate TLS at
that boundary. Use public DNS and managed certificates for the final
browser-accessible validation. Keep Kubernetes service discovery
separate from public DNS.

Start with one NAT Gateway per environment to limit cost. This accepts
an internet-egress outage if its AZ fails and cross-AZ transfer costs
for resources using it from the other AZ. Do not use NAT instances.

Use gateway endpoints where supported and useful. Add interface
endpoints only when security, reliability, traffic volume or measured
NAT-cost savings justify their recurring cost.

## Access and lifecycle rules

Allow only required traffic. Use Security Groups for infrastructure
access, load-balancer rules for public entry and Kubernetes NetworkPolicy
for workload-to-workload restrictions.

NetworkPolicy requires an enforcing network implementation.
Creating policy manifests alone does not establish protection.

Remove NAT Gateways, their Elastic IPs and load balancers when approved
work windows end. Follow ADR-0013 for VPC retention and full teardown.
It replaces the original assumption that the Dev VPC always persists
during implementation.

Keep detailed CIDRs, routes and access rules in implementation
configuration. Ingress, DNS and certificate implementation are covered
separately. WAF, CDN and service mesh remain deferred.

Track NAT, load-balancer, public IPv4, endpoint, data-processing and
transfer costs.

Revisit the design if traffic needs change, egress costs become excessive
or availability requirements justify one NAT Gateway per AZ.
