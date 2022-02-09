#!/bin/bash

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0

HISTORY_MODE="${HISTORY_MODE}" yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

while true; do
  #Remove unlabeled snapshots
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' --selector='!history_mode')" -gt 0 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' --selector='!history_mode')
    printf "%s Number of snapshots without label is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --selector='!history_mode')
    SNAPSHOT_TO_DELETE=${SNAPSHOTS%% *}
    if ! kubectl delete volumesnapshots "${SNAPSHOT_TO_DELETE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOT_TO_DELETE}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    while [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; do
      if ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; then
        printf "%s Snapshot %s deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_TO_DELETE}"
      fi
    done

    sleep 10
  done

  # Maintain 5 snapshots of a certain history mode
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")" -gt 4 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")
    printf "%s Number of snapshots for ${HISTORY_MODE}-node is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -l history_mode="${HISTORY_MODE}")
    SNAPSHOT_TO_DELETE=${SNAPSHOTS%% *}
    if ! kubectl delete volumesnapshots "${SNAPSHOT_TO_DELETE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOT_TO_DELETE}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    while [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; do
      if ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; then
        printf "%s Snapshot %s deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_TO_DELETE}"
      fi
    done
  done

  # if no snapshots with readyToUse=false
  if ! [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' -l history_mode="${HISTORY_MODE}")" ]; then

  # EBS Snapshot name based on current time and date
  SNAPSHOT_NAME=$(date "+%Y-%m-%d-%H-%M-%S" "$@")-$HISTORY_MODE-node-snapshot

  # Update volume snapshot name
  SNAPSHOT_NAME="${SNAPSHOT_NAME}" yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

  printf "%s Creating snapshot ${SNAPSHOT_NAME} in ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

  # Create snapshot
  if ! kubectl apply -f createVolumeSnapshot.yaml
  then
      printf "%s ERROR creating volumeSnapshot ${SNAPSHOT_NAME} in ${NAMESPACE} .\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      exit
  fi

  # if snanpshots exist and are readyToUse=false
  else
    EBS_SNAPSHOT_PROGRESS=""
    while [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
      # monitor progress
      SNAPSHOT_NAME=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' -l history_mode="${HISTORY_MODE}")
      SNAPSHOT_CONTENT=$(kubectl get volumesnapshot "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
      EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
      EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)

      printf "%s Snapshot %s is %s done.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}" "${EBS_SNAPSHOT_PROGRESS}"
      NEW_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
      while [ "${EBS_SNAPSHOT_PROGRESS}" == "${NEW_PROGRESS}" ] && [ "${EBS_SNAPSHOT_PROGRESS}" != 100%  ]; do
        NEW_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
      done
    done
  fi
done   