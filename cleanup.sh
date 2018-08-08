#!/bin/bash

echo
echo
echo 'Remove the Resource Group'
echo
echo 'resource_group=vmss-us-west2'
echo
echo 'az group delete -n $resource_group'
read -n1 -r -p 'Press any key...' key

resource_group=vmss-us-west2

az group delete -n $resource_group