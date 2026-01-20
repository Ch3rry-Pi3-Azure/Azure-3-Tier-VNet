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
  description = "Resource group name for the NAT gateway."
}

variable "location" {
  type        = string
  description = "Azure region for the NAT gateway."
  default     = "eastus2"
}

variable "nat_gateway_name" {
  type        = string
  description = "Explicit NAT gateway name. When null, a random suffix is added to the prefix."
  default     = null
}

variable "nat_gateway_name_prefix" {
  type        = string
  description = "Prefix used to build the NAT gateway name when nat_gateway_name is null."
  default     = "nat-vnet"
}

variable "public_ip_name" {
  type        = string
  description = "Explicit NAT public IP name. When null, a random suffix is added to the prefix."
  default     = null
}

variable "public_ip_name_prefix" {
  type        = string
  description = "Prefix used to build the NAT public IP name when public_ip_name is null."
  default     = "pip-nat"
}

variable "public_ip_sku" {
  type        = string
  description = "SKU for the NAT public IP."
  default     = "Standard"
}

variable "nat_gateway_sku" {
  type        = string
  description = "SKU name for the NAT gateway."
  default     = "Standard"
}

variable "idle_timeout_in_minutes" {
  type        = number
  description = "TCP idle timeout for the NAT gateway."
  default     = 10
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs that should use the NAT gateway for outbound traffic."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the NAT gateway resources."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "nat" {
  length    = 2
  separator = "-"
}

locals {
  nat_gateway_name = var.nat_gateway_name != null ? var.nat_gateway_name : "${var.nat_gateway_name_prefix}-${random_pet.nat.id}"
  public_ip_name   = var.public_ip_name != null ? var.public_ip_name : "${var.public_ip_name_prefix}-${random_pet.nat.id}"
}

resource "azurerm_public_ip" "nat" {
  name                = local.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = var.public_ip_sku
  tags                = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                    = local.nat_gateway_name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = var.nat_gateway_sku
  idle_timeout_in_minutes = var.idle_timeout_in_minutes
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "main" {
  for_each       = toset(var.subnet_ids)
  subnet_id      = each.value
  nat_gateway_id = azurerm_nat_gateway.main.id
}
