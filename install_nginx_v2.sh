#!/bin/bash

sudo apt-get update
sudo apt-get install -y nginx
sudo sed -i -e 's/Welcome to nginx/Welcome to nginx on Azure vmss/' /var/www/html/index*.html
