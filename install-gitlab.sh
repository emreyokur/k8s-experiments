#!/usr/bin/bash

set -x

curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.rpm.sh | sudo bash
EXTERNAL_URL="https://gitlab.example.com" yum install -y gitlab-ee