#!/bin/bash
openssl s_server -accept 8443 -cert tls.crt -key tls.rsa.key -CAfile ca.crt -Verify 0 -verify_return_error -www
