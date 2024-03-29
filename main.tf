terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.41.0"
    }
  }
  required_version = "~>1.3.9"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "prefix" {
  type = string
}

data "azurerm_client_config" "current" {
}
data "azurerm_subscription" "current" {
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-cmk-etcd-rg"
  location = "westus2"
}

resource "azurerm_key_vault" "repro_cluster_cmk" {
  name                       = "${var.prefix}-cmk-etcd"
  location                   = "westus2"
  resource_group_name        = azurerm_resource_group.rg.name
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  sku_name                   = "standard"
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  enable_rbac_authorization  = true
}

resource "azurerm_key_vault_key" "repro_cluster_etcd" {
  name         = "${var.prefix}-cmk-etcd"
  key_vault_id = azurerm_key_vault.repro_cluster_cmk.id
  key_type     = "EC"
  key_size     = 4096
  key_opts = [
    "sign",
    "verify",
  ]
}

resource "azurerm_user_assigned_identity" "cluster_identity" {
  location            = "westus2"
  resource_group_name = azurerm_resource_group.rg.name
  name                = "${var.prefix}-cmk-etcd-cluster"
}

resource "azurerm_user_assigned_identity" "kubelet_identity" {
  location            = "westus2"
  resource_group_name = azurerm_resource_group.rg.name
  name                = "${var.prefix}-cmk-etcd-kubelet"
}

resource "azurerm_role_assignment" "identity_operator_role" {
  scope                            = azurerm_user_assigned_identity.kubelet_identity.id
  role_definition_name             = "Managed Identity Operator"
  principal_id                     = azurerm_user_assigned_identity.cluster_identity.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "cluster_kv_admin_role" {
  scope                            = data.azurerm_subscription.current.id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = azurerm_user_assigned_identity.cluster_identity.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "kubelet_kv_admin_role" {
  scope                            = data.azurerm_subscription.current.id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = azurerm_user_assigned_identity.kubelet_identity.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "user_kv_admin_role" {
  scope                            = data.azurerm_subscription.current.id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = data.azurerm_client_config.current.client_id
  skip_service_principal_aad_check = true
}

# Gurantee the role assignment is complete before building the cluster
resource "time_sleep" "cmk_role_assignment" {
  depends_on = [
    azurerm_role_assignment.identity_operator_role,
    azurerm_role_assignment.cluster_kv_admin_role,
    azurerm_role_assignment.kubelet_kv_admin_role,
    azurerm_role_assignment.user_kv_admin_role,
  ]
  create_duration = "300s"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  depends_on                = [time_sleep.cmk_role_assignment]
  name                      = "${var.prefix}-cmk-etcd"
  location                  = "westus2"
  dns_prefix                = "${var.prefix}-cmk-etcd"
  resource_group_name       = azurerm_resource_group.rg.name
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster_identity.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet_identity.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet_identity.id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet_identity.id
  }

  azure_active_directory_role_based_access_control {
    managed                = true
    admin_group_object_ids = [data.azurerm_client_config.current.object_id]
  }

  key_management_service {
    key_vault_key_id = azurerm_key_vault_key.repro_cluster_etcd.id
  }
}
