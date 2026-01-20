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
  description = "Resource group name for the load balancer."
}

variable "location" {
  type        = string
  description = "Azure region for the load balancer."
  default     = "eastus2"
}

variable "lb_name" {
  type        = string
  description = "Explicit load balancer name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "lb_name_prefix" {
  type        = string
  description = "Prefix used to build the load balancer name when lb_name is null."
  default     = "lb-public"
}

variable "public_ip_name" {
  type        = string
  description = "Explicit public IP name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "public_ip_name_prefix" {
  type        = string
  description = "Prefix used to build the public IP name when public_ip_name is null."
  default     = "pip-lb"
}

variable "lb_sku" {
  type        = string
  description = "SKU for the load balancer."
  default     = "Standard"
}

variable "public_ip_sku" {
  type        = string
  description = "SKU for the public IP."
  default     = "Standard"
}

variable "frontend_port" {
  type        = number
  description = "Frontend port for the load balancer rule."
  default     = 80
}

variable "backend_port" {
  type        = number
  description = "Backend port for the load balancer rule."
  default     = 80
}

variable "probe_path" {
  type        = string
  description = "HTTP path for the load balancer health probe."
  default     = "/health"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the load balancer resources."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "lb" {
  length    = 2
  separator = "-"
}

locals {
  lb_name           = var.lb_name != null ? var.lb_name : "${var.lb_name_prefix}-${random_pet.lb.id}"
  public_ip_name    = var.public_ip_name != null ? var.public_ip_name : "${var.public_ip_name_prefix}-${random_pet.lb.id}"
  frontend_name     = "fe-${random_pet.lb.id}"
  backend_pool_name = "be-${random_pet.lb.id}"
  probe_name        = "probe-${random_pet.lb.id}"
  rule_name         = "http-${random_pet.lb.id}"
}

resource "azurerm_public_ip" "main" {
  name                = local.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = var.public_ip_sku
  tags                = var.tags
}

resource "azurerm_lb" "main" {
  name                = local.lb_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.lb_sku
  tags                = var.tags

  frontend_ip_configuration {
    name                 = local.frontend_name
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

resource "azurerm_lb_backend_address_pool" "main" {
  name            = local.backend_pool_name
  loadbalancer_id = azurerm_lb.main.id
}

resource "azurerm_lb_probe" "main" {
  name            = local.probe_name
  loadbalancer_id = azurerm_lb.main.id
  protocol        = "Http"
  port            = var.backend_port
  request_path    = var.probe_path
}

resource "azurerm_lb_rule" "main" {
  name                           = local.rule_name
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = var.frontend_port
  backend_port                   = var.backend_port
  frontend_ip_configuration_name = local.frontend_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
}
