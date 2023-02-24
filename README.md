# aks-cmk-repro

## Description

This repo contains Terraform to reproduce the bug described here: <https://github.com/MicrosoftDocs/azure-docs/issues/98954>.

When creating an AKS cluster with KMS etcd encryption as per [this documentation](https://learn.microsoft.com/en-us/azure/aks/use-kms-etcd-encryption),
the following error is encountered:

```shell
(AzureKeyVaultKmsValidateIdentityPermissionCustomerError) The identity does not have keys encrypt/decrypt permission on key vault <My Key Vault URL>
Code: AzureKeyVaultKmsValidateIdentityPermissionCustomerError
Message: The identity does not have keys encrypt/decrypt permission on key vault <My Key Vault URL>
```

This repository acts as a reproduction of the bug in the form of a Terraform Azure resources definition.

## To Reproduce

### Requirements

1. Install Terraform `~>.1.3.9`
1. Install Azure CLI

### Steps

1. Create a `vars.tfvars.json` file in project root with following content:

    ```json
    # Fill in fields with your details
    {
      "prefix": "",
      "cluster_admins": "",
      "tenant_id": ""
    {
    ```

1. Login to your Azure tenant.

    ```shell
    az login --tenant <same tenant_id as tfvars>
    ```

1. Initialize Terraform.

    ```shell
    terraform init
    ```

1. Apply Terraform.

    ```shell
    terraform apply -var-file vars.tfvars.json
    ```

1. Cleanup resources when done.

    ```shell
    terraform destroy -var-file vars.tfvars.json
    ```

### Expected Behavior

```shell
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
```

### Actual Behavior

```shell
╷
│ Error: waiting for creation of Managed Cluster (Subscription: "6603a406-455b-439b-a974-d52ec58a4d44"
│ Resource Group Name: "meddin-test-cmk-etcd-rg"
│ Managed Cluster Name: "meddin-test-cmk-etcd"): Code="AzureKeyVaultKmsValidateIdentityPermissionCustomerError" Message="The identity does not have keys encrypt/decrypt permission on key vault \"https://meddin-test-cmk-etcd.vault.azure.net\""
│ 
│   with azurerm_kubernetes_cluster.k8s,
│   on main.tf line 80, in resource "azurerm_kubernetes_cluster" "k8s":
│   80: resource "azurerm_kubernetes_cluster" "k8s" {
│ 
╵
```
