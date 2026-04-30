# Serverless Static Egress IP — Deployment Guide

## Overview

This Terraform module deploys AWS infrastructure that gives Databricks serverless compute a **static egress IP address**. External services (databases, APIs, SaaS platforms) can whitelist this single IP instead of tracking Databricks' rotating serverless IPs.

### Architecture

```
Databricks serverless
    │
    ▼
NLB (public, TCP passthrough)
    │
    ▼
NGINX proxy (private subnet, TCP relay)
    │
    ▼
NAT Gateway + Elastic IP  ◄── this is the static IP
    │
    ▼
Internet → your external service
```

All traffic passes through as encrypted TCP bytes — no TLS termination, no decryption. The proxy is a transparent pipe with a fixed source IP.

### Cost

| Component | Monthly Cost |
|---|---|
| NGINX proxy (t4g.nano) | ~$3 |
| Network Load Balancer | ~$16 |
| NAT Gateway | ~$32 + $0.045/GB processed |
| Elastic IP | Free (while associated) |
| **Total** | **~$51/month + data transfer** |

---

## Prerequisites

- **Terraform** >= 1.5
- **AWS CLI** v2 with a configured profile (SSO or IAM credentials)
- **AWS account** with permissions to create: VPC, subnets, NLB, EC2, NAT GW, EIP, IAM roles, security groups, prefix lists
- **Databricks workspace** with serverless compute enabled
- The **Databricks serverless egress CIDRs** for your workspace region (see Step 2)

---

## Step 1: Configure variables

```bash
cd envs/example
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_profile = "my-aws-profile"       # Your AWS CLI profile name
aws_region  = "us-west-2"            # Must match your Databricks workspace region
name_prefix = "my-company-egress"    # Prefix for all resource names
azs         = ["us-west-2a", "us-west-2b"]  # At least 2 AZs in your region
```

## Step 2: Get Databricks serverless egress CIDRs

Fetch the current egress IPs for your region:

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

Paste the output into `envs/example/main.tf` under `databricks_egress_cidrs`:

```hcl
variable "databricks_egress_cidrs" {
  default = [
    "18.246.106.0/24",
    "44.234.192.32/28",
    "3.42.138.0/25",
    "52.27.216.188/32",
  ]
}
```

> **Note:** These CIDRs rotate roughly once per quarter. New IPs are published at least 60 days before going active. After initial deployment, you can automate updates with a Lambda or cron job that calls the same endpoint and updates the AWS Managed Prefix List.

## Step 3: Configure backends

In `envs/example/main.tf`, set the `backends` list in the module block. Each backend is an external service you want to reach through the static IP:

```hcl
module "egress" {
  source = "../../modules/serverless-egress-static-ip"

  name_prefix             = var.name_prefix
  azs                     = var.azs
  databricks_egress_cidrs = var.databricks_egress_cidrs

  backends = [
    {
      name          = "postgres"
      port          = 5432
      upstream_host = "your-database.example.com"
    },
    # Add more backends as needed:
    # {
    #   name          = "clickhouse"
    #   port          = 8443
    #   upstream_host = "your-clickhouse.example.com"
    # },
  ]
}
```

Each backend creates:
- One NLB listener on `port`
- One NLB target group
- One NGINX `stream` server block that relays TCP to `upstream_host:port`

## Step 4: Deploy

```bash
cd envs/example

# Login to AWS (if using SSO)
aws sso login --profile my-aws-profile

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply
terraform apply
```

Terraform creates ~27 resources. Takes about 3-5 minutes (NAT Gateway is the slowest).

## Step 5: Note the outputs

After `terraform apply`, note these outputs:

```
nat_eip_public_ip = "203.0.113.42"     ← whitelist this IP on your external service
nlb_dns_name      = "my-company-egress-nlb-abc123.elb.us-west-2.amazonaws.com"
```

- **`nat_eip_public_ip`** — the static egress IP. Give this to your external service for their allowlist.
- **`nlb_dns_name`** — the hostname your Databricks workloads connect to (instead of connecting directly to the external service).

## Step 6: Whitelist the static IP

On your external service, add the `nat_eip_public_ip` to the IP allowlist. This is the only IP that traffic will come from, regardless of Databricks' internal IP rotation.

## Step 7: Test the connection

### From a Databricks notebook (serverless compute)

```python
import socket

NLB_HOST = "<nlb_dns_name from Step 5>"

# Verify DNS resolves
nlb_ip = socket.gethostbyname(NLB_HOST)
print(f"NLB resolved to: {nlb_ip}")
```

### PostgreSQL example

```python
import psycopg2

conn = psycopg2.connect(
    host="your-database.example.com",      # real hostname (for TLS SNI)
    hostaddr=socket.gethostbyname(NLB_HOST), # NLB IP (TCP target)
    port=5432,
    user="your_user",
    password="your_password",
    dbname="your_db",
    sslmode="require",
    connect_timeout=10,
)
cur = conn.cursor()
cur.execute("SELECT 1;")
print(cur.fetchone())
conn.close()
print("Connection via static egress IP succeeded.")
```

> **Why `host` + `hostaddr`?** `host` sets the TLS SNI (so the external service knows which certificate to present). `hostaddr` sets the actual TCP destination (the NLB). This lets TLS work correctly even though the traffic routes through the proxy.

### Lakehouse Federation example

```sql
CREATE CONNECTION my_pg_conn
TYPE POSTGRESQL
OPTIONS (
  host '<nlb_dns_name>',
  port '5432',
  user '<pg_user>',
  password '<pg_password>',
  trustServerCertificate 'true'
);

CREATE FOREIGN CATALOG my_pg_catalog
USING CONNECTION my_pg_conn
OPTIONS (database '<database_name>');

SELECT * FROM my_pg_catalog.public.my_table LIMIT 10;
```

---

## How it works

1. **Databricks serverless** connects to the NLB's public DNS name on the backend port (e.g., 5432).
2. The **NLB security group** checks the source IP against the Databricks egress prefix list. Non-Databricks traffic is dropped.
3. The **NLB** forwards the TCP connection to the NGINX proxy in the private subnet.
4. **NGINX** opens a new TCP connection to the external service and relays bytes in both directions. No decryption — pure TCP passthrough.
5. The proxy's outbound traffic routes through the **NAT Gateway**, which rewrites the source IP to the **Elastic IP** (the static egress IP).
6. The external service sees the connection coming from the static IP and allows it.

---

## Adding a new backend

To add a new external service, add an entry to the `backends` list and re-apply:

```hcl
backends = [
  { name = "postgres",   port = 5432, upstream_host = "pg.example.com" },
  { name = "clickhouse", port = 8443, upstream_host = "ch.example.com" },  # new
]
```

```bash
terraform apply
```

This creates a new NLB listener, target group, and NGINX server block. Same static IP, same proxy, no new infrastructure.

---

## Optional configuration

These variables have sensible defaults but can be overridden in `terraform.tfvars`:

| Variable | Default | When to change |
|---|---|---|
| `vpc_cidr` | `10.110.0.0/24` | Conflicts with existing VPC peering |
| `public_subnet_cidrs` | `["10.110.0.0/27", "10.110.0.32/27"]` | Only if you change `vpc_cidr` |
| `private_subnet_cidrs` | `["10.110.0.64/27", "10.110.0.96/27"]` | Only if you change `vpc_cidr` |
| `proxy_instance_type` | `t4g.nano` | Heavy throughput — upgrade to `t3.small` |
| `prefix_list_max_entries` | `10` | If Databricks publishes more than 10 CIDRs for your region |

---

## Operations

### SSH into the proxy (via SSM, no SSH keys needed)

```bash
aws ssm start-session \
  --target <proxy_instance_id> \
  --region <your_region> \
  --profile <your_profile>
```

Requires the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

### View NGINX logs

After SSM into the proxy:

```bash
sudo tail -f /var/log/nginx/stream-access.log
```

### View the current NGINX config

```bash
aws ssm send-command \
  --instance-ids <proxy_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /etc/nginx/nginx.conf"]' \
  --region <your_region> \
  --profile <your_profile>
```

### Reload NGINX without downtime

```bash
aws ssm send-command \
  --instance-ids <proxy_instance_id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["nginx -t && systemctl reload nginx"]' \
  --region <your_region> \
  --profile <your_profile>
```

### Tear down

```bash
cd envs/example
terraform destroy
```

---

## Limitations and future work

- **Single proxy instance** — the proxy is a single point of failure. For production, deploy an Auto Scaling Group with 2 instances across 2 AZs.
- **Single NAT Gateway** — also single-AZ. For production HA, deploy one NAT GW per AZ (each with its own EIP — external services would need to whitelist both IPs).
- **DNS resolved at NGINX startup** — if the external service changes its IP, run `systemctl reload nginx` on the proxy.
- **Prefix list rotation** — Databricks egress CIDRs change roughly quarterly. Automate updates with a Lambda or Databricks job that fetches `ip-ranges.json` and updates the AWS Managed Prefix List.
