# Databricks notebook source
# MAGIC %md
# MAGIC # Static Egress IP Validation
# MAGIC
# MAGIC This notebook validates that traffic from Databricks Serverless reaches an external
# MAGIC PostgreSQL database through a fixed, static IP address (the NAT Gateway EIP).
# MAGIC
# MAGIC ## Architecture
# MAGIC ```
# MAGIC Databricks Serverless
# MAGIC     -> NLB (your-nlb-host, port 5433)
# MAGIC     -> NGINX proxy (private subnet)
# MAGIC     -> NAT Gateway (static egress IP)
# MAGIC     -> RDS public endpoint (separate VPC, SG allows only the static IP)
# MAGIC ```
# MAGIC
# MAGIC ## Setup
# MAGIC Before running, configure the values in the next cell or store them as Databricks secrets:
# MAGIC ```
# MAGIC databricks secrets create-scope static-ip-test
# MAGIC databricks secrets put-secret static-ip-test rds_host
# MAGIC databricks secrets put-secret static-ip-test rds_password
# MAGIC databricks secrets put-secret static-ip-test nlb_host
# MAGIC databricks secrets put-secret static-ip-test nat_gw_ip
# MAGIC ```

# COMMAND ----------

# DBTITLE 1,Configuration
# Option A — load from Databricks secrets (recommended for shared environments)
# RDS_HOST = dbutils.secrets.get(scope="static-ip-test", key="rds_host")
# RDS_PASSWORD = dbutils.secrets.get(scope="static-ip-test", key="rds_password")
# NLB_HOST = dbutils.secrets.get(scope="static-ip-test", key="nlb_host")
# EXPECTED_NAT_GW_IP = dbutils.secrets.get(scope="static-ip-test", key="nat_gw_ip")

# Option B — fill these in directly for quick testing
RDS_HOST           = "<your-rds-host>.us-west-2.rds.amazonaws.com"
RDS_USER           = "postgres"
RDS_DB             = "testdb"
RDS_PASSWORD       = "<your-rds-password>"
NLB_HOST           = "<your-nlb-host>.elb.us-west-2.amazonaws.com"
NLB_PORT           = 5433
EXPECTED_NAT_GW_IP = "<your-nat-gw-static-ip>"

# COMMAND ----------

# DBTITLE 1,Test 1 — Direct connection (Serverless -> RDS)
# Verifies the RDS security group allows Databricks Serverless egress CIDRs directly.
# The client IP that RDS reports here is one of the Databricks Serverless egress IPs.
import psycopg2

conn_str = f"host={RDS_HOST} port=5432 dbname={RDS_DB} user={RDS_USER} password={RDS_PASSWORD} sslmode=require"

with psycopg2.connect(conn_str) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT version(), inet_server_addr(), inet_client_addr()")
        version, server_ip, client_ip = cur.fetchone()
        print(f"PostgreSQL version : {version}")
        print(f"RDS server IP      : {server_ip}")
        print(f"Client IP seen     : {client_ip}  (a Databricks Serverless egress IP)")

# COMMAND ----------

# DBTITLE 1,Test 2 — Via NLB (Serverless -> NLB -> proxy -> NAT GW -> RDS)
# Verifies traffic exits through the NAT Gateway's static IP.
# The client IP that RDS reports here should equal EXPECTED_NAT_GW_IP.
import psycopg2

conn_str = f"host={NLB_HOST} port={NLB_PORT} dbname={RDS_DB} user={RDS_USER} password={RDS_PASSWORD} sslmode=require"

with psycopg2.connect(conn_str) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT inet_client_addr()")
        client_ip = cur.fetchone()[0]
        print(f"Client IP seen by RDS : {client_ip}")
        print(f"Expected NAT GW IP    : {EXPECTED_NAT_GW_IP}")
        assert str(client_ip) == EXPECTED_NAT_GW_IP, "Static egress IP did not match!"
        print("PASS — traffic exited through the static NAT Gateway IP")

# COMMAND ----------

# DBTITLE 1,Test 3 — End-to-end CRUD via NLB
# Real read/write operations through the static-IP path.
import psycopg2

conn_str = f"host={NLB_HOST} port={NLB_PORT} dbname={RDS_DB} user={RDS_USER} password={RDS_PASSWORD} sslmode=require"

with psycopg2.connect(conn_str) as conn:
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS players (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                score INT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        cur.execute(
            "INSERT INTO players (name, score) VALUES (%s, %s), (%s, %s), (%s, %s)",
            ("alice", 100, "bob", 250, "carol", 175),
        )
        conn.commit()

        cur.execute("SELECT id, name, score, created_at FROM players ORDER BY score DESC")
        rows = cur.fetchall()
        print(f"Inserted and read back {len(rows)} rows:")
        for row in rows:
            print(f"  {row}")
