location / {
    return 302 https://${target}$request_uri;
}