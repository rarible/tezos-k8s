#!/bin/sh

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' job.yaml

while true; do
  # Job exists
  if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}")" ]; then
    printf "%s Snapshot-maker job exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
      printf "%s Snapshot-maker job not complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')" = "True" ]; then
          printf "%s Snapshot-maker job failed. Check Job pod logs for more information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
          exit 1
      fi
      printf "%s Waiting for snapshot-maker job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
      sleep 60
    fi
  else
      printf "%s Snapshot-maker job does not exist.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      # If PVC exists bound with no jobs running delete the PVC
      if [ "$(kubectl get pvc "${NAMESPACE}"-snap-volume -o 'jsonpath={..status.phase}' --namespace "${NAMESPACE}")" = "Bound" ]; then
        printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if [ "$(kubectl get jobs --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ] \
            && [ "$(kubectl get jobs --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
          printf "%s No jobs are running.  Deleting PVC.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
          kubectl delete pvc "${NAMESPACE}"-snap-volume --namespace "${NAMESPACE}"
          sleep 5
        fi
      fi
      printf "%s Ready for new snapshot-maker job.  Triggering job now.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      if ! kubectl apply -f job.yaml; then
        printf "%s Error creating snapshot-maker job.  Check pod logs for more information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
      fi  
      sleep 5
  fi  
done