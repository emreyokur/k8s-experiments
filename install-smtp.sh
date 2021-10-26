#!/usr/bin/bash
set -x

yum install libsasl2-modules postfix

cat > main.cf << EOF
# Enable auth
smtp_sasl_auth_enable = yes
# Set username and password
smtp_sasl_password_maps = static:alertmanager:alertmanager
smtp_sasl_security_options = noanonymous
# Turn on tls encryption 
smtp_tls_security_level = encrypt
header_size_limit = 4096000
# Set external SMTP relay host here IP or hostname accepted along with a port number. 
relayhost = [server-emreyuksel-okur-2]:587
# accept email from our web-server only 
inet_interfaces = 127.0.0.1
myhostname = alertmanager.case-emreyukselokur.abc
EOF

mv main.cf /etc/postfix/main.cf
systemctl stop postfix
systemctl start postfix