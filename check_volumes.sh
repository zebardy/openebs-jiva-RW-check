#!/bin/bash

set -x

READY=0
PREVIOUS_CHECK=1

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
POD_DETAILS=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/pods/$HOSTNAME)
VOLUME_COUNT=$(echo $POD_DETAILS | jq -r .spec.volumes[].persistentVolumeClaim.claimName | grep -v null | wc -l)

for run in {1..10}
do
  CHECKED_VOLUMES=0
  if [ $VOLUME_COUNT -eq 0 ]; then
    READY=1
  else
    for volume in $(echo $POD_DETAILS | jq -r .spec.volumes[].persistentVolumeClaim.claimName | grep -v null); do
      PVC_DETAILS=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/$NAMESPACE/persistentvolumeclaims/$volume)
      VOLUME_NAME=$(echo $PVC_DETAILS | jq -r .spec.volumeName)
      VOLUME_STORAGE_CLASS=$(echo $PVC_DETAILS | jq -r .spec.storageClassName)
      PROVISIONER=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/apis/storage.k8s.io/v1/storageclasses/${VOLUME_STORAGE_CLASS} | jq -r .provisioner)

      if [ $PROVISIONER == "openebs.io/provisioner-iscsi" ]; then
        RW_COUNT=$(curl ${VOLUME_NAME}-ctrl-svc:9501/v1/replicas | jq -r .data[].mode | grep RW | wc -l)
        TOTAL_COUNT=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/apis/apps/v1/namespaces/$NAMESPACE/deployments/${VOLUME_NAME}-ctrl | jq -r '.spec.template.spec.containers[].env[] | select(.name=="REPLICATION_FACTOR")'.value)
        CONTAINER_ENV $(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/apis/apps/v1/namespaces/$NAMESPACE/deployments/${VOLUME_NAME}-ctrl | jq -r '.spec.template.spec.containers[].env[])
	echo "$CONTAINER_ENV"
	if [ $(( $RW_COUNT*100/$TOTAL_COUNT )) -lt 75 ]; then
          break
        fi
      fi
      ((CHECKED_VOLUMES++))
      if [ $CHECKED_VOLUMES -eq $VOLUME_COUNT ]; then
        READY=1
      fi
    done
  fi
  if [ $READY -eq 1 ]; then
    if [ $PREVIOUS_CHECK -eq 1 ]; then
      break
    else
      PREVIOUS_CHECK=1
	fi
  else
    PREVIOUS_CHECK=0
  fi
  sleep 120
done

echo "ready: $READY"

if [ $READY -eq 0 ]; then
 exit 1
fi
exit 0
