variable "cluster_name" {
  type    = string
  default = "eks-study-tf"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "eks-study"
    ManagedBy   = "terraform"
    Environment = "learning"
  }
}
