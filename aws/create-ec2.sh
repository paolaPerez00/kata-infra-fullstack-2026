#!/usr/bin/env bash
# Uso (desde la carpeta donde está docker-compose.yml):
#   REPO_BACK=https://github.com/usuario/kata-back-fullstack-2026.git \
#   REPO_FRONT=https://github.com/usuario/kata-front-fullstack-2026.git \
#   ./create-ec2.sh
set -euo pipefail

export AWS_DEFAULT_REGION="${REGION:-us-east-1}"
REPO_BACK="${REPO_BACK:?Falta REPO_BACK}"
REPO_FRONT="${REPO_FRONT:?Falta REPO_FRONT}"
ROLE=kata-ec2-ssm
SG_NAME=kata-sg

DB_PASSWORD="$(openssl rand -hex 16)"
COMPOSE_B64="$(base64 < docker-compose.yml | tr -d '\n')"

# Script que corre la instancia al arrancar
cat > /tmp/kata-userdata.sh <<EOF
#!/bin/bash
set -ex
apt-get update
apt-get install -y docker.io docker-compose-v2 git
systemctl enable --now docker
mkdir -p /opt/kata /tmp/kata-exec
cd /opt/kata
git clone $REPO_BACK kata-back-fullstack-2026
git clone $REPO_FRONT kata-front-fullstack-2026
echo '$COMPOSE_B64' | base64 -d > docker-compose.yml
cat > .env <<ENV
DB_USER=kata
DB_PASSWORD=$DB_PASSWORD
DB_NAME=kata_db
ENV
docker pull node:24-alpine
docker pull python:3.12-alpine
docker pull eclipse-temurin:21-jdk-alpine
docker compose up -d --build
docker compose --profile seed run --rm seed
EOF

# Rol para entrar por Session Manager (sin SSH ni claves)
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name "$ROLE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$ROLE" --role-name "$ROLE"
  sleep 15
fi

# Security group: solo puerto 80
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
if [ "$VPC_ID" = "None" ]; then
  VPC_ID="$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)"
fi
SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=map-public-ip-on-launch,Values=true --query 'Subnets[0].SubnetId' --output text)"
SG_ID="$(aws ec2 describe-security-groups --filters Name=group-name,Values=$SG_NAME Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)"
if [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws ec2 create-security-group --group-name "$SG_NAME" --description "Kata web" --vpc-id "$VPC_ID" --query GroupId --output text)"
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
fi

AMI="$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)"

IID="$(aws ec2 run-instances \
  --image-id "$AMI" --instance-type t3.small \
  --iam-instance-profile Name="$ROLE" \
  --security-group-ids "$SG_ID" --subnet-id "$SUBNET_ID" \
  --user-data file:///tmp/kata-userdata.sh \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
  --metadata-options HttpTokens=required \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kata}]' \
  --query 'Instances[0].InstanceId' --output text)"

aws ec2 wait instance-running --instance-ids "$IID"
IP="$(aws ec2 describe-instances --instance-ids "$IID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
rm -f /tmp/kata-userdata.sh

echo "Instancia: $IID"
echo "URL: http://$IP  (disponible en 5-10 min, cuando termine el build)"