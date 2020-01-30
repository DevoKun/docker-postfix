#!/bin/bash

##
## supervisor
##
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true
EOF

cat > /etc/supervisor/conf.d/postfix.conf <<EOF
[program:postfix]
process_name    = master
autostart       = true
autorestart     = false
## because the command is postfix start
## autorestart must be false
directory       = /etc/postfix
command         = /usr/sbin/postfix -c /etc/postfix start
startsecs       = 0
stdout_logfile  = /dev/stdout
stderr_logfile  = /dev/stderr
stdout_logfile_maxbytes = 0
stderr_logfile_maxbytes = 0
EOF

cat > /etc/supervisor/conf.d/rsyslogd.conf <<EOF
[program:rsyslog]
command         = /usr/sbin/rsyslogd -n
autostart       = true
autorestart     = true
startsecs       = 2
stopwaitsecs    = 2
stdout_logfile  = /dev/stdout
stderr_logfile  = /dev/stderr
stdout_logfile_maxbytes = 0
stderr_logfile_maxbytes = 0
EOF




##
## rsyslogd
##
cat << EOF > /etc/rsyslog.conf
\$ModLoad immark.so   # provides --MARK-- message capability
\$ModLoad imuxsock.so # provides support for local system logging (e.g. via logger command)

# default permissions for all log files.
\$FileOwner root
\$FileGroup adm
\$FileCreateMode 0640
\$DirCreateMode 0755
\$Umask 0022

#*.info             /dev/stdout
#mail.*             /dev/stdout
mail.info           /dev/stdout
EOF





##
## postfix
##

postconf -e myhostname="${MYHOSTNAME}"
# $MAILDOMAIN
postconf -F '*/*/chroot = n'

##
## SASL SUPPORT FOR CLIENTS
## The following options set parameters needed by Postfix to enable
## Cyrus-SASL support for authentication of mail clients.
##

## /etc/postfix/main.cf
postconf -e smtpd_sasl_auth_enable=yes
postconf -e broken_sasl_auth_clients=yes
postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination

## smtpd.conf
cat >> /etc/postfix/sasl/smtpd.conf <<EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF

## sasldb2
echo $SMTP_USER | tr , \\n > /tmp/passwd
while IFS=':' read -r _user _pwd; do
  echo $_pwd | saslpasswd2 -p -c -u $MAILDOMAIN $_user
done < /tmp/passwd
chown postfix.sasl /etc/sasldb2

##
## Enable TLS
## If certs aren't provided, generate our own using mkcert.
##
if [[ -n "$(find /etc/postfix/certs -iname *.crt)" && -n "$(find /etc/postfix/certs -iname *.key)" ]]; then
  mkdir -p /etc/postfix/certs
  cd /etc/postfix/certs
  export CAROOT="/etc/postfix/certs"
  /usr/local/bin/mkcert -install -ecdsa
  /usr/local/bin/mkcert -ecdsa ${MYHOSTNAME} localhost 127.0.0.1 ::1 0.0.0.0
  KEYFILE=(ls *-key.pem | grep -v "rootCA")
  CRTFILE=(ls *.pem | grep -v "rootCA")
  mv $KEYFILE $KEYFILE.key
  mv $CRTFILE $CRTFILE.crt
fi

## /etc/postfix/main.cf
postconf -e smtpd_tls_cert_file=$(find /etc/postfix/certs -iname *.crt)
postconf -e smtpd_tls_key_file=$(find  /etc/postfix/certs -iname *.key)
chmod 0400 /etc/postfix/certs/*.*

## /etc/postfix/master.cf
postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission"
postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination"


##
## opendkim
## Only activate if Domain Keys found.
##
if [[ ! -z "$(find /etc/opendkim/domainkeys -iname *.private)" ]]; then

cat > /etc/supervisor/conf.d/opendkim.conf <<EOF
[program:opendkim]
command         = /usr/sbin/opendkim -f
user            = opendkim
autostart       = true
autorestart     = true
startsecs       = 5
stopwaitsecs    = 5
stdout_logfile  = /dev/stdout
stderr_logfile  = /dev/stderr
stdout_logfile_maxbytes = 0
stderr_logfile_maxbytes = 0
EOF

# /etc/postfix/main.cf
postconf -e milter_protocol=2
postconf -e milter_default_action=accept
postconf -e smtpd_milters=inet:localhost:12301
postconf -e non_smtpd_milters=inet:localhost:12301

cat >> /etc/opendkim.conf <<EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                   002
Syslog                  yes
SyslogSuccess           Yes
LogWhy                  Yes

Canonicalization        relaxed/simple

ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable

Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256

UserID                  opendkim:opendkim

Socket                  inet:12301@localhost
EOF

cat >> /etc/default/opendkim <<EOF
SOCKET="inet:12301@localhost"
EOF

cat >> /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
192.168.0.1/24

*.$MAILDOMAIN
EOF
cat >> /etc/opendkim/KeyTable <<EOF
mail._domainkey.$MAILDOMAIN $MAILDOMAIN:mail:$(find /etc/opendkim/domainkeys -iname *.private)
EOF
cat >> /etc/opendkim/SigningTable <<EOF
*@$MAILDOMAIN mail._domainkey.$MAILDOMAIN
EOF
chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
chmod 0400 $(find /etc/opendkim/domainkeys -iname *.private)

fi ## if opendkim keys found



##
## Amazon SES
##
if [ "x${AWS_RELAYHOST}" != "x" ]; then

  if [ "x${AWS_ACCESS_KEY_ID}" == "x" ]; then
    echo "${AWS_RELAYHOST} ${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" > /etc/postfix/sasl_passwd
  fi

  postmap hash:/etc/postfix/sasl_passwd
  postconf -e relayhost="${AWS_RELAYHOST}"
  postconf -e smtp_sasl_auth_enable=yes
  postconf -e smtp_sasl_security_options=noanonymous
  postconf -e smtp_sasl_password_maps=hash:/etc/postfix/sasl_passwd
  postconf -e smtp_use_tls=yes
  postconf -e smtp_tls_security_level=encrypt
  postconf -e smtp_tls_note_starttls_offer=yes
  postconf -e smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt
fi



