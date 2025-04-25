terraform {
  backend "local" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.77.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

locals {
  acr_prefix = "halima2" 
  image_name = "nginx"
}

resource "azurerm_resource_group" "rg" {
  name     = "app-service-rg"
  location = "westeurope"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "app-service-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet_appservice" {
  name                 = "appservice-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_service_plan" "asp" {
  name                = "app-service-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_prefix # Use the local prefix
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_app_service" "app_service" {
  name                = "${local.acr_prefix}-webapp" # You can adjust this pattern
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_service_plan.asp.id

  site_config {
    linux_fx_version = "DOCKER|${azurerm_container_registry.acr.login_server}/${local.image_name}:latest"
    always_on        = true
  }

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "DOCKER_REGISTRY_SERVER"   = azurerm_container_registry.acr.login_server
    "DOCKER_REGISTRY_USERNAME" = ""
    "DOCKER_REGISTRY_PASSWORD" = ""
  }

  tags = {
    environment = "dev"
    owner       = "your-team"
  }
}

resource "azurerm_role_assignment" "acr_pull_role" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_app_service.app_service.identity[0].principal_id
}