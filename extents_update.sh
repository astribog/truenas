#!/bin/bash

# Define systenm vars 
POOL_NAME="hdd-pool"
ZVOL_NAME="gold-zvol"
DATASET_PATH="${POOL_NAME}/${ZVOL_NAME}"
DT=$(date '+%d%m%y-%H%M%S')
# Define your pool of DNS names
# Initialize an empty array
DNS_POOL=()
# Generate elements from ba-1 to ba-46
for i in {1..46}; do
   DNS_POOL+=("ba-$i")
done
# Loop through each DNS name in the pool
for DNS in "${DNS_POOL[@]}"; do
# Ping the DNS name
   if ! ping -c 1 -W 1 "$DNS" > /dev/null 2>&1; then
      echo "DNS $DNS is not pinging. Applying the script..."
      # Get a list of all iSCSI extents
      EXTENTS=$(midclt call iscsi.extent.query)
      # Loop through each extent
      for row in $(echo "${EXTENTS}" | jq -r '.[] | @base64'); do
         _jq() {
            echo ${row} | base64 --decode | jq -r ${1}
         }
         EXTENT_NAME=$(_jq '.name')
         EXTENT_ID=$(_jq '.id')
         # Check if the extent name contains the DNS name
         if [[ $EXTENT_NAME == *"$DNS" ]]; then
            echo "Deleting extent: $EXTENT_NAME (ID: $EXTENT_ID)"
            # Delete the extent
            DELETE_OUTPUT=$(midclt call iscsi.extent.delete "$EXTENT_ID")
            echo "Delete output: $DELETE_OUTPUT"
            echo "---------------------------------"
         fi
      done
      # Define ZFS clones & snapshots names
      CLONE_NAME="${POOL_NAME}/clone:${DNS}"
      SNAPSHOT_NAME="${DATASET_PATH}@snapshot:${DNS}"
      SNAPSHOT_SHORT_NAME="snapshot:${DNS}"
      # Delete corresponding ZFS clones & snapshots
      midclt call zfs.dataset.delete "$CLONE_NAME"
      midclt call zfs.snapshot.delete "$SNAPSHOT_NAME"
      # Recreate snapshot
      midclt call zfs.snapshot.create '{"dataset": "'"$DATASET_PATH"'", "name":  "'"$SNAPSHOT_SHORT_NAME"'"}' 
      #> /dev/null 2>&1 
      # Recreate clone
      midclt call zfs.snapshot.clone '{"dataset_dst": "'"$CLONE_NAME"'", "snapshot": "'"$SNAPSHOT_NAME"'"}' 
      # Generate a random serial number for extent
      SERIAL=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')
      # Recreate iSCSI Extent
      EXTENT_NAME="extent-${DT}:${DNS}"
      EXTENT_ID=$(midclt call iscsi.extent.create '{
         "name": "'"$EXTENT_NAME"'",
         "type": "DISK",
         "disk": "'"zvol/$CLONE_NAME"'",
         "serial": "'"$SERIAL"'",
         "blocksize": 512,
         "pblocksize": false,
         "avail_threshold": 80
      }' | jq -r '.id')
      # Get a list of all iSCSI extents
      TARGETS=$(midclt call iscsi.target.query)
      # Loop through each target
      for row in $(echo "${TARGETS}" | jq -r '.[] | @base64'); do
         _jq() {
         echo ${row} | base64 --decode | jq -r ${1}
         }
         TARGET_NAME=$(_jq '.name')
         TARGET_ID=$(_jq '.id')
         # Check if the extent name contains the DNS name
         if [[ $TARGET_NAME == *"$DNS" ]]; then
            # Associate Target and Extent
            midclt call iscsi.targetextent.create '{
               "target": '$TARGET_ID',
               "extent": '$EXTENT_ID'
            }'
         fi
      done
   fi
done
