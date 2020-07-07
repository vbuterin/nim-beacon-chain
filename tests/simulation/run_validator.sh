#!/bin/bash

set -e

NODE_ID=${1}
shift

# Read in variables
# shellcheck source=/dev/null
source "$(dirname "$0")/vars.sh"

# set up the environment
# shellcheck source=/dev/null
source "${SIM_ROOT}/../../env.sh"

cd "$GIT_ROOT"

NODE_DATA_DIR="${SIMULATION_DIR}/validator-$NODE_ID"
NODE_VALIDATORS_DIR=$NODE_DATA_DIR/validators/
NODE_SECRETS_DIR=$NODE_DATA_DIR/secrets/

rm -rf "$NODE_VALIDATORS_DIR"
mkdir -p "$NODE_VALIDATORS_DIR"

rm -rf "$NODE_SECRETS_DIR"
mkdir -p "$NODE_SECRETS_DIR"

VALIDATORS_PER_NODE=$((NUM_VALIDATORS / TOTAL_NODES))

if [[ $NODE_ID -lt $TOTAL_NODES ]]; then
  # we will split the keys for this instance in half between the BN and the VC
  ATTACHED_VALIDATORS=$((VALIDATORS_PER_NODE / 2))

  pushd "$VALIDATORS_DIR" >/dev/null
  for VALIDATOR in $(ls | tail -n +$(( ($VALIDATORS_PER_NODE * $NODE_ID) + 1 + $ATTACHED_VALIDATORS )) | head -n $ATTACHED_VALIDATORS); do
      cp -ar "$VALIDATOR" "$NODE_VALIDATORS_DIR"
      cp -a "$SECRETS_DIR/$VALIDATOR" "$NODE_SECRETS_DIR"
    done
  popd >/dev/null
fi

cd "$NODE_DATA_DIR"

$VALIDATOR_CLIENT_BIN \
  --log-level=${LOG_LEVEL:-DEBUG} \
  --data-dir=$NODE_DATA_DIR \
  --secrets-dir=$NODE_SECRETS_DIR \
  --rpc-port="$(( $BASE_RPC_PORT + $NODE_ID ))"