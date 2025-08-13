#!/bin/bash

rm -f *.crt *.key *.csr *.srl

# Generate shared CA private key
echo "=== Generating shared CA private key ==="
openssl genrsa -out ca-shared.key 2048

# Generate first CA certificate (simulating original CA)
echo
echo "=== Generating CA1 (Original CA) ==="
openssl req -x509 -new -nodes \
  -key ca-shared.key \
  -sha256 \
  -days 3650 \
  -out ca1.crt \
  -subj "/CN=Local CA v1/O=Test Org/C=US"

# Generate second CA certificate (simulating rotated CA with same key)
echo
echo "=== Generating CA2 (Rotated CA with same key) ==="
openssl req -x509 -new -nodes \
  -key ca-shared.key \
  -sha256 \
  -days 3650 \
  -out ca2.crt \
  -subj "/CN=Local CA v1/O=Test Org/C=US"

# Generate third CA certificate with DIFFERENT private key but SAME subject
echo
echo "=== Generating CA3 (Different key, same subject) ==="
openssl genrsa -out ca3.key 2048
openssl req -x509 -new -nodes \
  -key ca3.key \
  -sha256 \
  -days 3650 \
  -out ca3.crt \
  -subj "/CN=Local CA v1/O=Test Org/C=US"

# Generate server1 private key and certificate signed by CA1
echo
echo "=== Generating Server1 certificate (signed by CA1) ==="
openssl genrsa -out server1.rsa.key 2048
openssl pkcs8 -topk8 -nocrypt -in server1.rsa.key -out server1.key

openssl req -new \
  -key server1.rsa.key \
  -out server1.csr \
  -subj "/CN=server1.localhost"

openssl x509 -req \
  -in server1.csr \
  -CA ca1.crt \
  -CAkey ca-shared.key \
  -CAcreateserial \
  -out server1.crt \
  -days 365 \
  -sha256 \
  -extfile <(printf "subjectAltName=DNS:server1.localhost,DNS:localhost")

# Generate server2 private key and certificate signed by CA2
echo
echo "=== Generating Server2 certificate (signed by CA2) ==="
openssl genrsa -out server2.rsa.key 2048
openssl pkcs8 -topk8 -nocrypt -in server2.rsa.key -out server2.key

openssl req -new \
  -key server2.rsa.key \
  -out server2.csr \
  -subj "/CN=server2.localhost"

openssl x509 -req \
  -in server2.csr \
  -CA ca2.crt \
  -CAkey ca-shared.key \
  -CAcreateserial \
  -out server2.crt \
  -days 365 \
  -sha256 \
  -extfile <(printf "subjectAltName=DNS:server2.localhost,DNS:localhost")

# Generate server3 private key and certificate signed by CA3
echo
echo "=== Generating Server3 certificate (signed by CA3) ==="
openssl genrsa -out server3.rsa.key 2048
openssl pkcs8 -topk8 -nocrypt -in server3.rsa.key -out server3.key

openssl req -new \
  -key server3.rsa.key \
  -out server3.csr \
  -subj "/CN=server3.localhost"

openssl x509 -req \
  -in server3.csr \
  -CA ca3.crt \
  -CAkey ca3.key \
  -CAcreateserial \
  -out server3.crt \
  -days 365 \
  -sha256 \
  -extfile <(printf "subjectAltName=DNS:server3.localhost,DNS:localhost")

echo
echo "Generated files:"
echo "- ca-shared.key: Shared CA private key"
echo "- ca1.crt: First CA certificate"
echo "- ca2.crt: Second CA certificate (rotated, same key)"
echo "- ca3.crt: Third CA certificate (same subject, DIFFERENT key)"
echo "- server1.crt, server1.key: Certificate signed by CA1"
echo "- server2.crt, server2.key: Certificate signed by CA2"
echo "- server3.crt, server3.key: Certificate signed by CA3"

# Display certificate details
echo
echo "=== Certificate Details ==="
echo
echo "--- CA1 Certificate ---"
openssl x509 -in ca1.crt -noout -text | grep -E "(Subject:|Serial Number:|Not Before:|Not After:)" | sed 's/^[[:space:]]*//'

echo
echo "--- CA2 Certificate ---"
openssl x509 -in ca2.crt -noout -text | grep -E "(Subject:|Serial Number:|Not Before:|Not After:)" | sed 's/^[[:space:]]*//'

echo
echo "--- CA3 Certificate ---"
openssl x509 -in ca3.crt -noout -text | grep -E "(Subject:|Serial Number:|Not Before:|Not After:)" | sed 's/^[[:space:]]*//'

echo
echo "--- Server1 Certificate ---"
openssl x509 -in server1.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before:|Not After:|Subject Alternative Name:)" | sed 's/^[[:space:]]*//'

echo
echo "--- Server2 Certificate ---"
openssl x509 -in server2.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before:|Not After:|Subject Alternative Name:)" | sed 's/^[[:space:]]*//'

echo
echo "--- Server3 Certificate ---"
openssl x509 -in server3.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before:|Not After:|Subject Alternative Name:)" | sed 's/^[[:space:]]*//'

# Show why cross-validation will succeed or fail
echo
echo "=== Understanding Certificate Verification ==="
echo "For verification to succeed:"
echo "1. Certificate's Issuer must match CA's Subject"
echo "2. Certificate must be signed by CA's private key"
echo
echo "Server1 Issuer: $(openssl x509 -in server1.crt -noout -issuer | cut -d' ' -f2-)"
echo "CA1 Subject: $(openssl x509 -in ca1.crt -noout -subject | cut -d' ' -f2-)"
echo "CA1 Public Key SHA256: $(openssl x509 -in ca1.crt -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 | cut -d' ' -f2)"
echo
echo "Server2 Issuer: $(openssl x509 -in server2.crt -noout -issuer | cut -d' ' -f2-)"
echo "CA2 Subject: $(openssl x509 -in ca2.crt -noout -subject | cut -d' ' -f2-)"
echo "CA2 Public Key SHA256: $(openssl x509 -in ca2.crt -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 | cut -d' ' -f2)"
echo ""
echo "Server3 Issuer: $(openssl x509 -in server3.crt -noout -issuer | cut -d' ' -f2-)"
echo "CA3 Subject: $(openssl x509 -in ca3.crt -noout -subject | cut -d' ' -f2-)"
echo "CA3 Public Key SHA256: $(openssl x509 -in ca3.crt -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 | cut -d' ' -f2)"
echo

# Verify certificates
echo
echo "=== Certificate Verification Tests ==="
echo
echo "--- Test 1: Verify server1.crt (signed by CA1) against CA1 ---"
if openssl verify -CAfile ca1.crt server1.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed"
fi

echo
echo "--- Test 2: Verify server1.crt (signed by CA1) against CA2 ---"
echo "Checking if Server1 Issuer matches CA2 Subject..."
if openssl verify -CAfile ca2.crt server1.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed - Issuer/Subject mismatch"
fi

echo
echo "--- Test 3: Verify server2.crt (signed by CA2) against CA2 ---"
if openssl verify -CAfile ca2.crt server2.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed"
fi

echo
echo "--- Test 4: Verify server2.crt (signed by CA2) against CA1 ---"
echo "Checking if Server2 Issuer matches CA1 Subject..."
if openssl verify -CAfile ca1.crt server2.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed - Issuer/Subject mismatch"
fi

echo
echo "=== CA3 Cross-Validation Test (Different Private Key) ==="
echo
echo "--- Test 5: Verify server3.crt (signed by CA3) against CA3 ---"
if openssl verify -CAfile ca3.crt server3.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed"
fi

echo
echo "--- Test 6: Verify server3.crt (signed by CA3) against CA1 ---"
echo "CA1 and CA3 have the same subject but DIFFERENT private keys"
if openssl verify -CAfile ca1.crt server3.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed - Different private key"
fi

echo
echo "--- Test 7: Verify server1.crt (signed by CA1) against CA3 ---"
echo "Testing the reverse: CA1-signed cert against CA3"
if openssl verify -CAfile ca3.crt server1.crt 2>&1; then
    echo "✓ Verification successful"
else
    echo "✗ Verification failed - Different private key"
fi

