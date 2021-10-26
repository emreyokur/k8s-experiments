#!/usr/bin/bash

set -x

yum -y install java-openjdk-devel java-openjdk

cat > /etc/yum.repos.d/elasticsearch.repo << EOF
[elasticsearch-7.x]
name=Elasticsearch repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
yum clean all
yum makecache

yum -y install elasticsearch
systemctl enable --now elasticsearch.service 
curl http://127.0.0.1:9200