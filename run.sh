#!/bin/bash
# run en background et attache un bash
docker exec -i -t $(docker run -d -i -p 80:80 -v "$(pwd)/dockersite/www:/var/www/html" -v "$(pwd)/dockersite/database:/var/lib/mysql" -v "$(pwd)/dockersite/vhosts:/etc/apache2/vhosts" -v "$(pwd)/dockersite/log:/var/log/dockersite" dockersite) bash

# Attention sous windows : il faut des chemins sous C:\Users forcement, et specifies sous la forme "/c/Users/...../dockersite/www:/var/www/html"

