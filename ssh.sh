. global.sh
ssh-keygen -t rsa -N '' -f $ROOT_DIR/.ssh/id_rsa <<< y
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_1
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_2
ssh-copy-id -i $ROOT_DIR/.ssh/id_rsa.pub $SERVER_3