# AWS Provider configuration with default tags
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

# Additional regional providers for multi-region deployment
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "ca_central_1"
  region = "ca-central-1"

  default_tags {
    tags = local.common_tags
  }
}
