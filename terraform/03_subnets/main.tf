terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the subnets."
}

variable "virtual_network_name" {
  type        = string
  description = "Virtual network name for the subnets."
}

variable "subnet_name_prefix" {
  type        = string
  description = "Prefix used to build subnet names."
  default     = "snet"
}

variable "subnet_name_suffix" {
  type        = string
  description = "Optional suffix appended to subnet names (for example, a random pet ID)."
  default     = null
}

variable "subnet_cidrs" {
  type        = map(string)
  description = "Map of subnet keys to CIDR blocks."
  default = {
    web = "10.10.1.0/24"
    app = "10.10.2.0/24"
    db  = "10.10.3.0/24"
  }
}

locals {
  subnet_suffix = var.subnet_name_suffix != null && length(trimspace(var.subnet_name_suffix)) > 0 ? "-${var.subnet_name_suffix}" : ""
}

resource "azurerm_subnet" "main" {
  for_each             = var.subnet_cidrs
  name                 = "${var.subnet_name_prefix}-${each.key}${local.subnet_suffix}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  private_endpoint_network_policies_enabled = each.key == "db" ? false : true
  address_prefixes     = [each.value]
}
