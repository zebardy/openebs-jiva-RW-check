#!/bin/bash

READY=1

POD_DETAILS=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/default/pods/$HOSTNAME)

for volume in $(echo $POD_DETAILS | jq -r .spec.volumes[].persistentVolumeClaim.claimName | grep -v null); do
  PVC_DETAILS=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/default/persistentvolumeclaims/$volume)
  VOLUME_NAME=$(echo $PVC_DETAILS | jq -r .spec.volumeName)
  VOLUME_STORAGE_CLASS=$(echo $PVC_DETAILS | jq -r .spec.storageClassName)
  PROVISIONER=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/apis/storage.k8s.io/v1/storageclasses/${VOLUME_STORAGE_CLASS} | jq -r .provisioner)

  if [ $PROVISIONER == "openebs.io/provisioner-iscsi" ]; then
    RW_COUNT=$(curl ${VOLUME_NAME}-ctrl-svc:9501/v1/replicas | jq -r .data[].mode | grep RW | wc -l)
    TOTAL_COUNT=$(curl -sSk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/apis/apps/v1/namespaces/default/deployments/${VOLUME_NAME}-ctrl | jq -r '.spec.template.spec.containers[].env[] | select(.name=="REPLICATION_FACTOR")'.value)
    if [ $(( $RW_COUNT*100/$TOTAL_COUNT )) -lt 52 ]; then
      READY=0
      break
    fi
  fi
done

echo "ready: $READY"

if [ $READY -eq 0 ]; then
 exit 1
fi
