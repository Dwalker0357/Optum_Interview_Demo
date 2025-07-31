variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_attachments" {
  description = "VPC attachments for the transit gateway"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    cidr_block = string
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
