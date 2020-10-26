terraform{
    required_version = ">= 0.13.3"
}

provider "azurerm"{
    version = ">= 2.28.0"
    features {}
}

resource "random_integer" "sa_num"{
    min = 10000
    max = 99999
}

resource "azurerm_resource_group" "backend_rg"{
    name = var.resource_group_name
    location = var.location
}

resource "azurerm_storage_account" "backend_sa"{
    name = "${lower(var.naming_prefix)}sa${random_integer.sa_num.result}"
    resource_group_name = azurerm_resource_group.backend_rg.name
    location = var.location
    account_tier = "Standard"
    account_replication_type = "LRS"
}

resource "azurerm_storage_container" "backend_ct"{
    name = "${lower(var.naming_prefix)}-terraform-state-ct"
    storage_account_name = azurerm_storage_account.backend_sa.name
}

data "azurerm_storage_account_sas" "backend_state_token"{
    connection_string = azurerm_storage_account.backend_sa.primary_connection_string
    https_only = true

    resource_types {
        service = true
        container = true
        object = true
    }

    services {
        blob = true
        queue = false
        table = false
        file = false
    }

    start = timestamp()
    expiry = timeadd(timestamp(),"168h")

    permissions {
        read = true
        write = true
        add = true
        create = true
        delete = true
        list = true
        process = false
        update = false
    }
}
    
    ## PROVISIONERS
    resource "null_resource" "write_backend_config" {
        depends_on = [azurerm_storage_container.backend_ct]

        provisioner "local-exec" {
            command = <<EOT
            Add-Content -Value 'storage_account_name = "${azurerm_storage_account.backend_sa.name}"' -Path backend-config.txt
            Add-Content -Value  'container_name = "${azurerm_storage_container.backend_ct.name}"' -Path backend-config.txt
            Add-Content -Value  'key = "terraform.tfstate"' -Path backend-config.txt
            Add-Content -Value  'sas_token = "${data.azurerm_storage_account_sas.backend_state_token.sas}"' -Path backend-config.txt
            EOT

            interpreter = ["PowerShell", "-Command"]
        } 
    }

    ## OUTPUT

    output "storage_account_name" {
        value = azurerm_storage_account.backend_sa.name
    }

    output "resource_group_name" {
        value = azurerm_resource_group.backend_rg.name
    }
