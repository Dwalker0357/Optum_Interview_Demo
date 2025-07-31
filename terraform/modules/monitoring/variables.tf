variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "jenkins_instances" {
  description = "List of Jenkins instance IDs to monitor"
  type        = list(string)
  default     = []
}

variable "nessus_instances" {
  description = "List of Nessus instance IDs to monitor"
  type        = list(string)
  default     = []
}

variable "app_instances" {
  description = "List of application instance IDs to monitor"
  type        = list(string)
  default     = []
}

variable "alb_arns" {
  description = "List of ALB ARNs to monitor"
  type        = list(string)
  default     = []
}

variable "notification_topics" {
  description = "SNS topic ARNs for notifications"
  type = object({
    critical = string
    warning  = string
  })
  default = {
    critical = ""
    warning  = ""
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
