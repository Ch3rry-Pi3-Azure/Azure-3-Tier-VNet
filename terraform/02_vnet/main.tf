terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for the virtual network."
}

variable "location" {
  type        = string
  description = "Azure region for the virtual network."
  default     = "eastus2"
}

variable "vnet_name" {
  type        = string
  description = "Explicit VNet name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "vnet_name_prefix" {
  type        = string
  description = "Prefix used to build the VNet name when vnet_name is null."
  default     = "vnet-main"
}

variable "address_space" {
  type        = list(string)
  description = "Address space for the VNet."
  default     = ["10.10.0.0/16"]
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the virtual network."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "vnet" {
  length    = 2
  separator = "-"
}

locals {
  vnet_name = var.vnet_name != null ? var.vnet_name : "${var.vnet_name_prefix}-${random_pet.vnet.id}"
}

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}
