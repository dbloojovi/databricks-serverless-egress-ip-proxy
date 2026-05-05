output "endpoint" {
  description = "RDS hostname. Use as upstream_host in the egress module backend."
  value       = aws_db_instance.main.address
}

output "port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "username" {
  value = aws_db_instance.main.username
}

output "password" {
  description = "Auto-generated master password. Retrieve with: terraform output -raw rds_password"
  value       = random_password.db.result
  sensitive   = true
}
