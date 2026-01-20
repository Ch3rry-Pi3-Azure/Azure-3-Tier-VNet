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

variable "location" {
  type        = string
  description = "Azure region for the resource group."
  default     = "eastus2"
}

variable "resource_group_name" {
  type        = string
  description = "Explicit resource group name. When null, a random pet suffix is added to the prefix."
  default     = null
}

variable "resource_group_name_prefix" {
  type        = string
  description = "Prefix used to build the resource group name when resource_group_name is null."
  default     = "rg-vnet"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the resource group."
  default = {
    project = "vnets-subnets"
    env     = "dev"
    owner   = "unknown"
  }
}

resource "random_pet" "rg" {
  length    = 2
  separator = "-"
}

locals {
  rg_name = var.resource_group_name != null ? var.resource_group_name : "${var.resource_group_name_prefix}-${random_pet.rg.id}"
}

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}
