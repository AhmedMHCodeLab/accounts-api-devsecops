variable "vpc_id" {
  type        = string
  description = "VPC hosting the private accounts database."
}

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

resource "aws_security_group" "db" {
  name        = "accounts-db"
  description = "Private PostgreSQL access for accounts-api only."
  vpc_id      = var.vpc_id

  egress {
    description = "Required database egress."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "accounts-db"
    Service = "accounts-api"
  }
}

resource "aws_db_instance" "accounts" {
  identifier = "accounts-prod"

  engine         = "postgres"
  instance_class = "db.r6g.large"

  manage_master_user_password = true
  username                    = "rdsadmin"

  publicly_accessible  = false
  db_subnet_group_name = var.accounts_db_subnet_group_name
  storage_encrypted    = true
  kms_key_id           = var.accounts_db_kms_key_arn

  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false

  multi_az                   = true
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  apply_immediately = false

  tags = {
    Service   = "accounts-api"
    DataClass = "customer-financial"
  }
}

resource "aws_security_group_rule" "db_ingress" {
  type                     = "ingress"
  description              = "PostgreSQL from accounts-api only."
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = var.accounts_app_security_group_id
}

resource "aws_cloudtrail" "org" {
  name                          = "org-trail"
  s3_bucket_name                = var.trail_bucket_name
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  is_organization_trail         = true
}