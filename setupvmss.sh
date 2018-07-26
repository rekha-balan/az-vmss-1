#!/bin/bash

echo
echo
echo 'Define the deployment variables used by the subsequent Azure CLI commands'
echo
echo 'resource_group=vmss-demo-01'
echo 'location=westus2'
echo 'vmss_name=vmss-nginx-01'
echo 'user_name=bot6'
echo 'storage_account=vmssnginx01storage'
read -n1 -r -p 'Press any key...' key

resource_group=vmss-demo-01
location=westus2
vmss_name=vmss-nginx-01
user_name=bot6
storage_account=vmssnginx01storage

echo
echo
echo 'Define the admin user name and SSH key variables'
echo
echo 'admin_user=$user_name'
echo 'ssh_pubkey="$(readlink -f ~/.ssh/id_rsa.pub)"'
read -n1 -r -p 'Press any key...' key

admin_user=$user_name
ssh_pubkey="$(readlink -f ~/.ssh/id_rsa.pub)"

echo
echo
echo 'Create the resource group for the deployment'
echo
echo 'az group create --name $resource_group --location $location'
read -n1 -r -p 'Press any key...' key

az group create --name $resource_group --location $location

echo
echo
echo "Create the vmss with three (3) instances using the public Ubuntu LTS image."
echo
echo 'az vmss create --resource-group $resource_group --name $vmss_name \'
echo '    --image UbuntuLTS \'
echo '    --admin-username $admin_user \'
echo '    --ssh-key-value $ssh_pubkey \'
echo '    --vm-sku Standard_D2_v3 \'
echo '    --instance-count 3 \'
echo '    --vnet-name ${vmss_name}-vnet \'
echo '    --public-ip-address ${vmss_name}-pip \'
echo '    --backend-pool-name ${vmss_name}-backend \'
echo '    --lb ${vmss_name}-elb'
read -n1 -r -p 'Press any key...' key

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

echo
echo
echo 'Create a storage account for the nginx init container' 
echo
echo 'export AZURE_STORAGE_ACCOUNT=$storage_account'
echo
echo 'az storage account create --name $AZURE_STORAGE_ACCOUNT --location $location --resource-group $resource_group --sku Standard_LRS'
read -n1 -r -p 'Press any key...' key

export AZURE_STORAGE_ACCOUNT=$storage_account

az storage account create --name $AZURE_STORAGE_ACCOUNT --location $location --resource-group $resource_group --sku Standard_LRS

echo
echo
echo 'Create the container for the nginx init script'
echo
echo 'export AZURE_STORAGE_KEY="$(az storage account keys list --resource-group "$resource_group" --account-name "$AZURE_STORAGE_ACCOUNT" --query [0].value --output tsv)"'
echo
echo 'az storage container create --name init --public-access container'
read -n1 -r -p 'Press any key...' key

export AZURE_STORAGE_KEY="$(az storage account keys list --resource-group "$resource_group" --account-name "$AZURE_STORAGE_ACCOUNT" --query '[0].value' --output tsv)"

az storage container create --name init --public-access container

echo
echo
echo 'Create the init script that will be used to install nginx'
echo
echo 'The script will contain "sudo apt-get update" and "sudo apt-get install -y nginx" commands'
echo
read -n1 -r -p 'Press any key...' key

cat <<EOF >install_nginx.sh
#!/bin/bash

sudo apt-get update
sudo apt-get install -y nginx
EOF

echo
echo
echo 'Upload the init script to the blob container in the Azure storage account'
echo
echo 'az storage blob upload --container-name init --file install_nginx.sh --name install_nginx.sh'
echo
echo 'init_script_url="$(az storage blob url --container-name init --name install_nginx.sh --output tsv)"'
read -n1 -r -p 'Press any key...' key

az storage blob upload --container-name init --file install_nginx.sh --name install_nginx.sh

init_script_url="$(az storage blob url --container-name init --name install_nginx.sh --output tsv)"

echo
echo
echo 'Create the JSON settings file used by the vmss extension'
echo
echo 'The script will have the url to the init script, and the command needed for execution'
echo
read -n1 -r -p 'Press any key...' key

cat <<EOF >script-config.json
{
  "fileUris": ["$init_script_url"],
  "commandToExecute": "./install_nginx.sh"
}
EOF

echo
echo
echo 'Deploy the custom script extension to the vmss'
echo
echo 'az vmss extension set \'
echo '    --publisher Microsoft.Azure.Extensions \'
echo '    --version 2.0 \'
echo '    --name CustomScript \'
echo '    --resource-group $resource_group \'
echo '    --vmss-name $vmss_name \'
echo '    --settings @script-config.json'
read -n1 -r -p 'Press any key...' key

az vmss extension set \
    --publisher Microsoft.Azure.Extensions \
    --version 2.0 \
    --name CustomScript \
    --resource-group $resource_group \
    --vmss-name $vmss_name \
    --settings @script-config.json

echo
echo
echo 'Show the current status of the vmss'
echo
echo 'az vmss list-instances --name $vmss_name --resource-group $resource_group'
read -n1 -r -p 'Press any key...' key

az vmss list-instances --name $vmss_name --resource-group $resource_group

echo
echo
echo 'Trigger the vmss extension to run on each vmss instance'
echo
echo 'az vmss update-instances --resource-group $resource_group --name $vmss_name --instance-ids \*'
read -n1 -r -p 'Press any key...' key

az vmss update-instances --resource-group $resource_group --name $vmss_name --instance-ids \*

echo
echo
echo 'Enable public access to the vmss pool'
echo
echo 'Create a load balancer probe'
echo
echo 'az network lb probe create \'
echo '    --resource-group $resource_group \'
echo '    --lb-name ${vmss_name}-elb \'
echo '    --name nginx-probe \'
echo '    --port 80 \'
echo '    --protocol Http \'
echo '    --path /'
read -n1 -r -p 'Press any key...' key

az network lb probe create \
    --resource-group $resource_group \
    --lb-name ${vmss_name}-elb \
    --name nginx-probe \
    --port 80 \
    --protocol Http \
    --path /

echo
echo
echo 'Create a load balancer rule'
echo
echo 'az network lb rule create \'
echo '    --resource-group $resource_group \'
echo '    --lb-name ${vmss_name}-elb \'
echo '    --name nginx-rule \'
echo '    --frontend-port 80 \'
echo '    --backend-port 80 \'
echo '    --protocol Tcp \'
echo '    --backend-pool-name ${vmss_name}-backend \'
echo '    --probe nginx-probe'
read -n1 -r -p 'Press any key...' key

az network lb rule create \
    --resource-group $resource_group \
    --lb-name ${vmss_name}-elb \
    --name nginx-rule \
    --frontend-port 80 \
    --backend-port 80 \
    --protocol Tcp \
    --backend-pool-name ${vmss_name}-backend \
    --probe nginx-probe

echo
echo
echo 'Verify nginx is running on each instance'
read -n1 -r -p 'Press any key...' key

lb_ip=$(az network lb show --resource-group "$resource_group" --name "${vmss_name}-elb" --query "frontendIpConfigurations[].publicIpAddress.id" --output tsv | head -n1 | xargs az network public-ip show --query ipAddress --output tsv --ids)
curl -s "$lb_ip" | grep title


echo
echo
echo 'Initiate a rolling update to the vmss'
echo
echo 'Create the new init script that will be used to modify nginx, upload the script to the Storage Account'
read -n1 -r -p 'Press any key...' key

cat <<EOF >install_nginx_v2.sh
#!/bin/bash

sudo apt-get update
sudo apt-get install -y nginx
sudo sed -i -e 's/Welcome to nginx/Welcome to nginx on Azure vmss/' /var/www/html/index*.html
EOF

az storage blob upload --container-name init --file install_nginx_v2.sh --name install_nginx_v2.sh
init_script_url="$(az storage blob url --container-name init --name install_nginx_v2.sh --output tsv)"

echo
echo
echo 'Create the JSON settings file used by the new vmss extension'
echo
read -n1 -r -p 'Press any key...' key

cat <<EOF >script-config_v2.json
{
  "fileUris": ["$init_script_url"],
  "commandToExecute": "./install_nginx_v2.sh"
}
EOF

echo
echo
echo 'Deploy the new script extension to the vmss'
echo
read -n1 -r -p 'Press any key...' key

az vmss extension set \
    --publisher Microsoft.Azure.Extensions \
    --version 2.0 \
    --name CustomScript \
    --resource-group $resource_group \
    --vmss-name $vmss_name \
    --settings @script-config_v2.json

echo
echo
echo 'Show the current status of the vmss'
echo
read -n1 -r -p 'Press any key...' key

az vmss list-instances --name $vmss_name --resource-group $resource_group

echo
echo
echo 'Get the vmss first instance ID'
echo
echo 'instance_id="$(az vmss list-instances --resource-group $resource_group --name $vmss_name --query [].instanceId --output tsv | head -n1)"'
read -n1 -r -p 'Press any key...' key

instance_id="$(az vmss list-instances --resource-group $resource_group --name $vmss_name --query '[].instanceId' --output tsv | head -n1)"

echo
echo
echo 'Upgrade the first instance of the vmss to the latest version'
echo
read -n1 -r -p 'Press any key...' key

az vmss update-instances --resource-group "$resource_group" --name "$vmss_name" --instance-ids "$instance_id"

echo
echo
echo 'Verify the first instance has been upgraded'
echo
read -n1 -r -p 'Press any key...' key

az vmss list-instances --resource-group $resource_group --name $vmss_name

echo
echo
echo 'curl each the elb to validate'
echo
read -n1 -r -p 'Press any key...' key

for i in `seq 1 6`; do
    curl -s $lb_ip | grep title
done

echo
echo
echo 'Obtain the NAT SSH port for the updated instance'
echo
read -n1 -r -p 'Press any key...' key

ssh_port="$(az network lb inbound-nat-rule show --resource-group $resource_group --lb-name ${vmss_name}-elb --name ${vmss_name}-elbNatPool.${instance_id} --query frontendPort --output tsv)"

echo
echo
echo 'Map the localhost:8080 endpoint to the remote 80 port through the SSH channel'
echo
echo 'After creating the SSH channel, you can visit the web page through http://localhost:8080 to see the upgraded instance'
echo
read -n1 -r -p 'Press any key...' key

ssh -L localhost:8080:localhost:80 -p $ssh_port $user_name@$lb_ip

echo
echo 'Close the SSH channel and upgrade the remaining instances'
echo
read -n1 -r -p 'Press any key...' key

az vmss update-instances --resource-group $resource_group --name $vmss_name --instance-ids \*

echo
echo
echo 'curl each the elb to validate'
echo
read -n1 -r -p 'Press any key...' key

for i in `seq 1 6`; do
    curl -s $lb_ip | grep title
done