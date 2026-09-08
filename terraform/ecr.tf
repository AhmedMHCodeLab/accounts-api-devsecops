resource "aws_ecr_repository" "accounts_api" {
  name                 = "accounts-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Service = "accounts-api"
    Managed = "terraform"
  }
}