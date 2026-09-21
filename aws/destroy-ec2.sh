#!/usr/bin/env bash
# Elimina la instancia y el security group de la kata
set -euo pipefail
export AWS_DEFAULT_REGION="${REGION:-us-east-1}"

IDS="$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=kata Name=instance-state-name,Values=pending,running,stopped,stopping \
  --query 'Reservations[].Instances[].InstanceId' --output text)"

if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  aws ec2 wait instance-terminated --instance-ids $IDS
fi

SG_ID="$(aws ec2 describe-security-groups --filters Name=group-name,Values=kata-sg --query 'SecurityGroups[0].GroupId' --output text)"
[ "$SG_ID" != "None" ] && aws ec2 delete-security-group --group-id "$SG_ID"
echo "Recursos eliminados"