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
  description = "Resource group name for the network security groups."
}

variable "location" {
  type        = string
  description = "Azure region for the network security groups."
  default     = "eastus2"
}

variable "subnet_ids_by_key" {
  type        = map(string)
  description = "Map of subnet keys to subnet IDs."
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

variable "nsg_name_prefix" {
  type        = string
  description = "Prefix used to build NSG names."
  default     = "nsg"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the network security groups."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "nsg" {
  length    = 2
  separator = "-"
}

locals {
  nsg_names = {
    web = "${var.nsg_name_prefix}-web-${random_pet.nsg.id}"
    app = "${var.nsg_name_prefix}-app-${random_pet.nsg.id}"
    db  = "${var.nsg_name_prefix}-db-${random_pet.nsg.id}"
  }
}

resource "azurerm_network_security_group" "main" {
  for_each            = local.nsg_names
  name                = each.value
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "main" {
  for_each                  = var.subnet_ids_by_key
  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.main[each.key].id
}

resource "azurerm_network_security_rule" "web_https_in" {
  name                        = "AllowHttpsIn"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.subnet_cidrs["web"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main["web"].name
}

resource "azurerm_network_security_rule" "web_http_in" {
  name                        = "AllowHttpIn"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.subnet_cidrs["web"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main["web"].name
}

resource "azurerm_network_security_rule" "app_8080_in" {
  name                        = "AllowAppFromWeb"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = var.subnet_cidrs["web"]
  destination_address_prefix  = var.subnet_cidrs["app"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main["app"].name
}

resource "azurerm_network_security_rule" "db_1433_in" {
  name                        = "AllowSqlFromApp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = var.subnet_cidrs["app"]
  destination_address_prefix  = var.subnet_cidrs["db"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main["db"].name
}
