resource "aws_db_instance" "bad_accounts" {
  identifier = "accounts-prod-bad"

  engine         = "postgres"
  instance_class = "db.r6g.large"

  username = "postgres"
  password = "plaintext-example"

  publicly_accessible = true
  storage_encrypted   = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
}

resource "aws_cloudtrail" "bad" {
  name                          = "bad-trail"
  s3_bucket_name                = "example-trail-bucket"
  is_multi_region_trail         = false
  include_global_service_events = false
  enable_log_file_validation    = false
}

resource "aws_security_group_rule" "bad_db_ingress" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "sg-0123456789abcdef0"
}