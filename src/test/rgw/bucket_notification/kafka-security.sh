FQDN=${KAFKA_CERT_HOSTNAME:-localhost}
IP_SAN=${KAFKA_CERT_IP:-}
KEYFILE=server.keystore.jks
TRUSTFILE=server.truststore.jks
CAFILE=y-ca.crt
CAKEYFILE=y-ca.key
REQFILE=$FQDN.req
CERTFILE=$FQDN.crt
CLIENT_KEYFILE=client.key
CLIENT_CSRFILE=client.csr
CLIENT_CERTFILE=client.crt
CLIENT_CN=${KAFKA_CLIENT_CN:-rgw-client}
CLIENT_KEY_PASS=${KAFKA_CLIENT_KEY_PASSWORD:-hunter2}
MYPW=mypassword
VALIDITY=36500

rm -f $KEYFILE
rm -f $TRUSTFILE
rm -f $CAFILE
rm -f $REQFILE
rm -f $CERTFILE
rm -f $CLIENT_KEYFILE
rm -f $CLIENT_CSRFILE
rm -f $CLIENT_CERTFILE

SAN_STRING="DNS:$FQDN"
if [ -n "$IP_SAN" ]; then
  SAN_STRING="$SAN_STRING,IP:$IP_SAN"
fi

echo "########## create the request in key store '$KEYFILE' with SAN=$SAN_STRING"
keytool -keystore $KEYFILE -alias localhost \
  -dname "CN=$FQDN, OU=Michigan Engineering, O=Red Hat Inc, \
  L=Ann Arbor, ST=Michigan, C=US" \
  -storepass $MYPW -keypass $MYPW \
  -validity $VALIDITY -genkey -keyalg RSA \
  -ext SAN=$SAN_STRING

echo "########## create the CA '$CAFILE'"
openssl req -new -nodes -x509 -keyout $CAKEYFILE -out $CAFILE \
  -days $VALIDITY -subj \
  '/C=US/ST=Michigan/L=Ann Arbor/O=Red Hat Inc/OU=Michigan Engineering/CN=yuval-1'

echo "########## store the CA in trust store '$TRUSTFILE'"
keytool -keystore $TRUSTFILE -storepass $MYPW -alias CARoot \
  -noprompt -importcert -file $CAFILE

echo "########## create a request '$REQFILE' for signing in key store '$KEYFILE'"
keytool -storepass $MYPW -keystore $KEYFILE \
  -alias localhost -certreq -file $REQFILE

echo "########## sign and create certificate '$CERTFILE' with SAN=$SAN_STRING"
EXTFILE=$(mktemp)
cat > $EXTFILE << EOF
subjectAltName=$SAN_STRING
EOF

openssl x509 -req -CA $CAFILE -CAkey $CAKEYFILE -CAcreateserial \
  -days $VALIDITY \
  -in $REQFILE -out $CERTFILE -extfile $EXTFILE

rm -f $EXTFILE

echo "########## store CA '$CAFILE' in key store '$KEYFILE'"
keytool -storepass $MYPW -keystore $KEYFILE -alias CARoot \
  -noprompt -importcert -file $CAFILE

echo "########## store certificate '$CERTFILE' in key store '$KEYFILE'"
keytool -storepass $MYPW -keystore $KEYFILE -alias localhost \
  -import -file $CERTFILE

echo "########## generate client key '$CLIENT_KEYFILE' (encrypted) for mTLS"
openssl genrsa -aes256 -passout pass:$CLIENT_KEY_PASS \
  -out $CLIENT_KEYFILE 2048

echo "########## create client CSR '$CLIENT_CSRFILE' with CN=$CLIENT_CN"
openssl req -new -key $CLIENT_KEYFILE -passin pass:$CLIENT_KEY_PASS \
  -subj "/CN=$CLIENT_CN" -out $CLIENT_CSRFILE

echo "########## sign client certificate '$CLIENT_CERTFILE' with CA '$CAFILE'"
openssl x509 -req -CA $CAFILE -CAkey $CAKEYFILE -CAcreateserial \
  -days $VALIDITY -in $CLIENT_CSRFILE -out $CLIENT_CERTFILE

chmod 600 $CLIENT_KEYFILE
rm -f $CLIENT_CSRFILE
