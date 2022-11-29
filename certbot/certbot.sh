#!/bin/bash

set -e

trap exit INT TERM

until nc -z nginx 80; do
  echo "Waiting for nginx to start..."
  sleep 5s & wait ${!}
done

if [ "$CERTBOT_TEST_CERT" != "0" ]; then
  test_cert_arg="--test-cert"
fi

i=1
while true
do
  # Need to set DOMAIN_[...] , CERTBOTEMAIL_[...]
  # loop unit reach end of DOMAIN_[1,2,3,4]
  if [[ -z $(eval "echo \${DOMAIN_$i}") ]]; then
    break
  else
    domain=$(eval "echo \${DOMAIN_$i}")
  fi

  mkdir -p "/var/www/certbot/$domain"

  if [ -d "/etc/letsencrypt/live/$domain" ]; then
    echo "Let's Encrypt certificate for $domain already exists"
    i=$((i+1))
    continue
  fi

  if [[ -z $(eval "echo \${CERTBOTEMAIL_$i}") ]]; then
    email_arg="--register-unsafely-without-email"
    echo "Obtaining the certificate for $domain without email"
  else
    email=$(eval "echo \${CERTBOTEMAIL_$i}")
    email_arg="--email $email"
    echo "Obtaining the certificate for $domain with email $email"
  fi
  certbot certonly \
    --webroot \
    -w "/var/www/certbot/$domain" \
    -d "$domain" \
    $test_cert_arg \
    $email_arg \
    --rsa-key-size "${CERTBOT_RSA_KEY_SIZE:-4096}" \
    --agree-tos \
    --noninteractive \
    --verbose || true

i=$((i+1))
done
