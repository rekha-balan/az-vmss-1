# Azure Virtual Machine Scale Set (vmss) Demo

Content based on
Tutorial: Canary Deployment for Azure Virtual Machine Scale Sets
by Menghua Xiao
https://open.microsoft.com/2018/06/18/tutorial-canary-deployment-for-azure-virtual-machine-scale-sets/

## Deploy the Virtual Machine Scale Set

Define the deployment variables used by the subsequent Azure CLI commands

```bash
resource_group=vmss-demo-01
location=westus2
vmss_name=vmss-nginx-01
user_name=bot6
storage_account=vmssnginx01storage
```

Define the admin user name and SSH key variables

```bash
admin_user=$user_name
ssh_pubkey="$(readlink -f ~/.ssh/id_rsa.pub)"
```

Create the resource group for the deployment

```bash
az group create --name $resource_group --location $location
```

Create the vmss with three (3) instances using the public Ubuntu LTS image.

>**NOTE**: if you don't have a key pair, either replace --ssh-key-value [value] with --generate-ssh-keys , or run 'ssh-keygen -t rsa -b 2048'

```bash
az vmss create --resource-group $resource_group --name $vmss_name \
    --image UbuntuLTS \
    --admin-username $admin_user \
    --ssh-key-value $ssh_pubkey \
    --vm-sku Standard_D2_v3 \
    --instance-count 3 \
    --vnet-name ${vmss_name}-vnet \
    --public-ip-address ${vmss_name}-pip \
    --backend-pool-name ${vmss_name}-backend \
    --lb ${vmss_name}-elb
```

## Deploy nginx to the Virtual Machine Scale Set

A Storage Account is needed to store the init scripts. Note that '-' is not allowed in a storage account name.  Additional naming rules for storage can be found [here](https://docs.microsoft.com/en-us/azure/architecture/best-practices/naming-conventions#storage)

Create the Azure Storage Account and container that will store the scripts used to deploy the application

```bash
export AZURE_STORAGE_ACCOUNT=$storage_account

az storage account create --name $AZURE_STORAGE_ACCOUNT --location $location --resource-group $resource_group --sku Standard_LRS

export AZURE_STORAGE_KEY="$(az storage account keys list --resource-group "$resource_group" --account-name "$AZURE_STORAGE_ACCOUNT" --query '[0].value' --output tsv)"

az storage container create --name init --public-access container
```

Create the init script that will be used to install nginx

```bash
cat <<EOF >install_nginx.sh
#!/bin/bash

sudo apt-get update
sudo apt-get install -y nginx
EOF
```

Upload the init script to the blob container in the Azure Storage Account

```bash
az storage blob upload --container-name init --file install_nginx.sh --name install_nginx.sh

init_script_url="$(az storage blob url --container-name init --name install_nginx.sh --output tsv)"
```

Create the JSON settings file used by the vmss extension

```bash
cat <<EOF >script-config.json
{
  "fileUris": ["$init_script_url"],
  "commandToExecute": "./install_nginx.sh"
}
EOF
```

Deploy the Custom Script Extension to the Virtual Machine Scale Set

```bash
az vmss extension set \
    --publisher Microsoft.Azure.Extensions \
    --version 2.0 \
    --name CustomScript \
    --resource-group $resource_group \
    --vmss-name $vmss_name \
    --settings @script-config.json
```

The script is staged, and the vmss is now ready to run the script defined in the custom script extension.

Show the current status of the vmss

```bash
az vmss list-instances --name $vmss_name --resource-group $resource_group
```

Trigger the vmss extension to run on each instance

```bash
az vmss update-instances --resource-group $resource_group --name $vmss_name --instance-ids \*
```

Each instance will get run the script and deploy nginx

## Enable Public Access to the vmss Instances

Create a load balancer probe and rule to allow public access to the backend nginx instances

```bash
az network lb probe create \
    --resource-group $resource_group \
    --lb-name ${vmss_name}-elb \
    --name nginx \
    --port 80 \
    --protocol Http \
    --path /

az network lb rule create \
    --resource-group $resource_group \
    --lb-name ${vmss_name}-elb \
    --name nginx \
    --frontend-port 80 \
    --backend-port 80 \
    --protocol Tcp \
    --backend-pool-name ${vmss_name}-backend \
    --probe nginx
```

Verify nginx is running on each instance

```bash
lb_ip=$(az network lb show --resource-group "$resource_group" --name "${vmss_name}-elb" --query "frontendIpConfigurations[].publicIpAddress.id" --output tsv | head -n1 | xargs az network public-ip show --query ipAddress --output tsv --ids)
curl -s "$lb_ip" | grep title
```

## Initiate a Rolling Update to the vmss

Create the new init script that will be used to modify nginx, upload the script to the Storage Account

```bash
cat <<EOF >install_nginx_v2.sh
#!/bin/bash

sudo apt-get update
sudo apt-get install -y nginx
sudo sed -i -e 's/Welcome to nginx/Welcome to nginx on Azure vmss/' /var/www/html/index*.html
EOF

az storage blob upload --container-name init --file install_nginx_v2.sh --name install_nginx_v2.sh
init_script_url="$(az storage blob url --container-name init --name install_nginx_v2.sh --output tsv)"
```

Create the JSON settings file used by the new vmss extension

```bash
cat <<EOF >script-config_v2.json
{
  "fileUris": ["$init_script_url"],
  "commandToExecute": "./install_nginx_v2.sh"
}
EOF
```

Deploy the new Custom Script Extension to the Virtual Machine Scale Set

```bash
az vmss extension set \
    --publisher Microsoft.Azure.Extensions \
    --version 2.0 \
    --name CustomScript \
    --resource-group $resource_group \
    --vmss-name $vmss_name \
    --settings @script-config_v2.json
```

The vmss is now ready to run the new script defined in the custom script extension.

Show the current status of the vmss

```bash
az vmss list-instances --name $vmss_name --resource-group $resource_group
```

Get the vmss first instance ID

```bash
instance_id="$(az vmss list-instances --resource-group $resource_group --name $vmss_name --query '[].instanceId' --output tsv | head -n1)"
```

Upgrade the first instance of the vmss to the latest version

```bash
az vmss update-instances --resource-group "$resource_group" --name "$vmss_name" --instance-ids "$instance_id"
```

Verify the first instance has been upgraded

```bash
az vmss list-instances --resource-group $resource_group --name $vmss_name

for i in `seq 1 6`; do
    curl -s $lb_ip | grep title
done
```

Obtain the NAT SSH port for the updated instance

```bash
ssh_port="$(az network lb inbound-nat-rule show --resource-group $resource_group --lb-name ${vmss_name}-elb --name ${vmss_name}-elbNatPool.${instance_id} --query frontendPort --output tsv)"
```

Map the localhost:8080 endpoint to the remote 80 port through the SSH channel

```bash
ssh -L localhost:8080:localhost:80 -p $ssh_port $lb_ip
```

After creating the SSH channel, you can visit the web page through http://localhost:8080 to see the upgraded instance

Close the SSH channel and upgrade the remaining instances

```bash
az vmss update-instances --resource-group $resource_group --name $vmss_name --instance-ids \*
```