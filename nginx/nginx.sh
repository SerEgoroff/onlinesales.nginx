#!/bin/bash

set -e

if [ -z "$DOMAINS" ]; then
  echo "DOMAINS environment variable is not set"
  exit 1;
fi

if [ -z "$TARGETS" ]; then
  echo "TARGETS environment variable is not set"
  exit 1;
fi

use_dummy_certificate() {
  if grep -q "/etc/letsencrypt/live/$1" "/etc/nginx/sites/$1.conf"; then
    echo "Switching Nginx to use dummy certificate for $1"
    sed -i "s|/etc/letsencrypt/live/$1|/etc/nginx/sites/ssl/dummy/$1|g" "/etc/nginx/sites/$1.conf"
  fi
}

use_lets_encrypt_certificate() {
  if grep -q "/etc/nginx/sites/ssl/dummy/$1" "/etc/nginx/sites/$1.conf"; then
    echo "Switching Nginx to use Let's Encrypt certificate for $1"
    sed -i "s|/etc/nginx/sites/ssl/dummy/$1|/etc/letsencrypt/live/$1|g" "/etc/nginx/sites/$1.conf"
  fi
}

reload_nginx() {
  echo "Reloading Nginx configuration"
  nginx -s reload
}

wait_for_lets_encrypt() {
  until [ -d "/etc/letsencrypt/live/$1" ]; do
    echo "Waiting for Let's Encrypt certificates for $1"
    sleep 5s & wait ${!}
  done
  use_lets_encrypt_certificate "$1"
  reload_nginx
}

if [ ! -f /etc/nginx/sites/ssl/ssl-dhparams.pem ]; then
  mkdir -p "/etc/nginx/sites/ssl"
  openssl dhparam -out /etc/nginx/sites/ssl/ssl-dhparams.pem 2048
fi


domains_fixed=($(echo "$DOMAINS" | tr -d \"))
domains_count=${#domains_fixed[@]}
targets_fixed=($(echo "$TARGETS" | tr -d \"))
targets_count=${#targets_fixed[@]}

if [ ${domains_count} -ne ${targets_count} ]; then
  echo "Error: DOMAINS environment variable element count does not match TARGET element count\n"
  echo "Domains count ${domains_count}\n"
  echo "Targets count ${targets_count}\n"
  exit 1;
fi


for (( c=0; c<=$domains_count-1; c++ ))
do
  domain=$(echo "${domains_fixed[$c]}")
  target=$(echo "${targets_fixed[$c]}")

  vHostTemplate=""
  if [ "${target:0:1}" = "/" ]; then
    vHostTemplate=$(cat /customization/vhost_static.tpl)  # begins with '/' -> path -> serve static files
  elif [ "${target:0:1}" = ">"]; then
    vHostTemplate=$(cat /customization/vhost_redirect.tpl)  # begins with '>' -> temporary redirect (HTTP 302)
  else
    vHostTemplate=$(cat /customization/vhost_service.tpl) # else - serve service
  fi
  vHostTemplate=$(echo "${vHostTemplate//\$\{target\}/"$target"}")

  if [ ! -f "/etc/nginx/sites/$domain.conf" ]; then
    echo "Creating Nginx configuration file /etc/nginx/sites/$domain.conf"

    templateFile=$(cat /customization/site.conf.tpl)
    templateFile=$(echo "${templateFile//\$\{domain\}/"$domain"}")
    templateFile=$(echo "${templateFile//\$\{vhostinclude\}/"$vHostTemplate"}")
    echo "$templateFile" > "/etc/nginx/sites/$domain.conf"
  fi

  if [ ! -f "/etc/nginx/sites/ssl/dummy/$domain/fullchain.pem" ]; then
    echo "Generating dummy ceritificate for $domain"
    mkdir -p "/etc/nginx/sites/ssl/dummy/$domain"
    printf "[dn]\nCN=${domain}\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:$domain" > openssl.cnf
    openssl req -x509 -out "/etc/nginx/sites/ssl/dummy/$domain/fullchain.pem" -keyout "/etc/nginx/sites/ssl/dummy/$domain/privkey.pem" \
      -newkey rsa:2048 -nodes -sha256 \
      -subj "/CN=${domain}" -extensions EXT -config openssl.cnf
    rm -f openssl.cnf
  fi

  if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
    use_dummy_certificate "$domain"
    wait_for_lets_encrypt "$domain" &
  else
    use_lets_encrypt_certificate "$domain"
  fi
done

exec nginx -g "daemon off;"
