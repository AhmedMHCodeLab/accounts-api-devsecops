resource "aws_db_instance" "good_accounts" {
  identifier = "accounts-prod"

  engine         = "postgres"
  instance_class = "db.r6g.large"

  manage_master_user_password = true

  publicly_accessible = false
  storage_encrypted   = true

  backup_retention_period = 35
  deletion_protection     = true
  skip_final_snapshot     = false
}

resource "aws_cloudtrail" "good" {
  name                          = "org-trail"
  s3_bucket_name                = "example-trail-bucket"
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  is_organization_trail         = true
}

resource "aws_security_group_rule" "good_db_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = "sg-0123456789abcdef0"
  source_security_group_id = "sg-0fedcba9876543210"
}