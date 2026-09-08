variable "accounts_db_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the accounts database."
}

variable "accounts_db_subnet_group_name" {
  type        = string
  description = "Private DB subnet group used by the accounts database."
}

variable "accounts_app_security_group_id" {
  type        = string
  description = "Security group for the accounts-api workload."
}

variable "trail_bucket_name" {
  type        = string
  description = "Central S3 bucket receiving CloudTrail logs."
}

resource "aws_db_instance" "accounts" {
  identifier = "accounts-prod"

  engine         = "postgres"
  instance_class = "db.r6g.large"

  # Prefer RDS-managed credentials over a plaintext password variable.
  manage_master_user_password = true

  publicly_accessible = false

  db_subnet_group_name = var.accounts_db_subnet_group_name

  storage_encrypted = true
  kms_key_id        = var.accounts_db_kms_key_arn

  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false

  multi_az = true

  apply_immediately = false
}

resource "aws_security_group_rule" "db_ingress" {
  type        = "ingress"
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"

  security_group_id        = aws_security_group.db.id
  source_security_group_id = var.accounts_app_security_group_id
}

resource "aws_cloudtrail" "org" {
  name                          = "org-trail"
  s3_bucket_name                = var.trail_bucket_name
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Production expectation: created from the Organizations
  # management/delegated-administrator account.
  is_organization_trail = true
}