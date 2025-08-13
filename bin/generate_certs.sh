#!/bin/bash

rm -f tls.crt tls.key ca.crt

# Generate CA private key
openssl genrsa -out ca.key 2048

# Generate CA certificate
openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 \
  -days 3650 \
  -out ca.crt \
  -subj "/CN=Local CA"

# Generate server private key
openssl genrsa -out tls.rsa.key 2048
openssl pkcs8 -topk8 -nocrypt -in tls.rsa.key -out tls.key

# Generate server CSR
openssl req -new \
  -key tls.rsa.key \
  -out server.csr \
  -subj "/CN=localhost"

# Generate server certificate
openssl x509 -req \
  -in server.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 365 \
  -sha256 \
  -extfile <(printf "subjectAltName=DNS:localhost")

# Clean up temporary files
rm ca.key ca.srl server.csr

echo "Generated: ca.crt, tls.crt, and tls.key"

### Create PKCS12 files

rm -f keystore.p12 truststore.p12

openssl pkcs12 -export \
  -in tls.crt \
  -inkey tls.key \
  -out keystore.p12 \
  -name "tls-cert" \
  -passout pass:changeit

keytool -importcert \
  -trustcacerts \
  -alias "ca-cert" \
  -file ca.crt \
  -keystore truststore.p12 \
  -storetype PKCS12 \
  -storepass changeit \
  -noprompt

echo "Generated keystore.p12 and truststore.p12"
