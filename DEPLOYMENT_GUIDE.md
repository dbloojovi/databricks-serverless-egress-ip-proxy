# Serverless Static Egress IP — Deployment Guide

## Overview

This Terraform project deploys AWS infrastructure that gives Databricks serverless compute a **static egress IP**. External services can whitelist this single IP instead of tracking Databricks' rotating serverless CIDRs.

```
Databricks Serverless
    → NLB (public, TCP passthrough)
    → NGINX proxy (private subnet)
    → NAT Gateway + Elastic IP   ◄── this is the static IP
    → External service
```

All traffic passes through as encrypted TCP bytes — no TLS termination.

### Cost

| Component | ~Monthly |
|---|---|
| NGINX proxy (`t4g.nano`) | $3 |
| Network Load Balancer | $16 |
| NAT Gateway | $32 + $0.045/GB |
| Elastic IP | Free (while attached) |
| **Total** | **~$51/mo + data transfer** |

---

## Prerequisites

- Terraform ≥ 1.5
- AWS CLI v2 with a configured profile (SSO works)
- AWS perms to create: VPC, subnets, NLB, EC2, NAT GW, EIP, IAM roles, security groups, prefix lists
- Databricks workspace with serverless compute enabled

---

## Quick Start

The example environment deploys the egress infrastructure **plus** a self-contained RDS PostgreSQL instance you can use to validate the static IP works before swapping in your real backend.

### 1. Configure

```bash
cd envs/example
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_profile = "my-aws-profile"
aws_region  = "us-west-2"            # must match your Databricks workspace region
name_prefix = "my-egress"
azs         = ["us-west-2a", "us-west-2b"]
```

### 2. Refresh Databricks egress CIDRs (optional)

The defaults in `envs/example/main.tf` were fetched on `2026-04-28` for `us-west-2`. To refresh or use a different region:

```bash
curl -s https://www.databricks.com/networking/v1/ip-ranges.json | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
region = 'us-west-2'  # <-- change to your region
cidrs = [r['cidr'] for r in data['ranges']
         if r.get('platform') == 'aws'
         and r.get('type') == 'outbound'
         and r.get('region') == region]
for c in cidrs:
    print(f'  \"{c}\",')
"
```

Paste the output into the `databricks_egress_cidrs` default list in `envs/example/main.tf`.

> CIDRs rotate at most monthly with 60 days notice. Automate updates against the AWS Managed Prefix List with a Lambda or scheduled job.

### 3. Deploy

```bash
aws sso login --profile my-aws-profile
terraform init
terraform apply
```

~5–7 minutes (RDS is the slowest).

### 4. Note the outputs

```
nat_eip_public_ip = "203.0.113.42"             ← static egress IP
nlb_dns_name      = "my-egress-nlb-…elb.amazonaws.com"
rds_endpoint      = "my-egress-rds-test.…rds.amazonaws.com"
rds_username      = "postgres"
rds_password      = <sensitive>                 ← retrieve with the command below
```

```bash
terraform output -raw rds_password
```

---

## Validate the Static Egress IP

The example includes a self-contained RDS test instance. Its security group allows inbound 5432 from:
- The static NAT GW IP (`nat_eip_public_ip`) — proves traffic via NLB exits through the static IP.
- The Databricks Serverless egress CIDRs — provides a direct-connection baseline.

Import [`examples/notebooks/static_ip_validate.py`](examples/notebooks/static_ip_validate.py) into your Databricks workspace and fill in the values from `terraform output`. The notebook runs three tests:

| # | Path | What it proves |
|---|---|---|
| 1 | Direct: Serverless → RDS | RDS reachable from a Databricks egress IP |
| 2 | Via NLB: Serverless → NLB → proxy → NAT GW → RDS | `inet_client_addr()` equals the static NAT GW IP |
| 3 | End-to-end CRUD via NLB | Real read/write through the static-IP path |

Run all three cells. Test 2 asserts the static IP is what RDS sees — that's the proof the proxy works.

---

## Use Your Real Backend

Once validated, add your real backends to `terraform.tfvars` (no main.tf edits needed):

```hcl
enable_rds_test = false   # disable the test RDS

backends = [
  {
    name          = "postgres"
    port          = 5432
    upstream_host = "your-database.example.com"
  },
  {
    name          = "clickhouse"
    port          = 8443
    upstream_host = "your-clickhouse.example.com"
  },
]
```

Run `terraform apply`. Each backend entry creates one NLB listener, one target group, and one NGINX `stream` server block. Same static IP, same proxy.

Then on your external service, **whitelist the `nat_eip_public_ip`**, and connect from Databricks to the **NLB DNS name** instead of the real database hostname:

```python
import psycopg2

conn = psycopg2.connect(
    host="<nlb_dns_name>",
    port=5432,
    user="...",
    password="...",
    dbname="...",
    sslmode="require",
)
```

---

## Tear down

```bash
terraform destroy
```

---

## Optional Variables

| Variable | Default | When to override |
|---|---|---|
| `vpc_cidr` | `10.110.0.0/24` | Conflicts with existing VPC peering |
| `proxy_instance_type` | `t4g.nano` | Heavy throughput → `t4g.small` |
| `prefix_list_max_entries` | `10` | If Databricks publishes more CIDRs for your region |

---

## Known Limitations

- **Single proxy** — single AZ, single point of failure. For production, run an ASG of ≥2 across AZs.
- **Single NAT Gateway** — also single-AZ. For HA, deploy one NAT GW per AZ (each with its own EIP — external services must whitelist both).
- **DNS resolved at NGINX startup** — if the upstream host's IP changes, `systemctl reload nginx` on the proxy.
- **Prefix list rotation** — automate updates against Databricks' published CIDRs.
