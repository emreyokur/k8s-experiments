#!/usr/bin/bash

set -x

yum -y install kibana
cat > /etc/kibana/kibana.yml << EOF
server.host: "0.0.0.0"
server.name: "kibana.case-emreyukselokur.abc"
elasticsearch.url: "http://localhost:9200"
EOF

systemctl enable --now kibana