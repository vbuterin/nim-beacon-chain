# beacon_chain
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


# Note: this is also inspired by https://github.com/ethereum/beacon_chain/blob/master/beacon_chain/state/state_transition.py
# The official spec at https://notes.ethereum.org/SCIg8AH5SA-O4C1G1LYZHQ# is not fully
# defining the state transitions.
#
# Note that the ethresearch impl is using "block_vote_cache" field, which is a dictionary mapping hashes
# to the following sub-dictionary:
#     {
#       'voter_indices': set(),
#       'total_voter_deposits': 0
#     }
# It should not be needed anymore with the new AttestationRecord type

{.warning: "The official spec at https://notes.ethereum.org/SCIg8AH5SA-O4C1G1LYZHQ# is not fully defining state transitions.".}

import
  ./spec/[beaconstate, crypto, datatypes, digest, helpers],
  intsets, endians, nimcrypto,
  milagro_crypto # nimble install https://github.com/status-im/nim-milagro-crypto@#master



func process_block*(active_state: BeaconState, crystallized_state: BeaconState, blck: BeaconBlock, slot: uint64) =
  # TODO: non-attestation verification parts of per-block processing

  #let parent_hash = blck.ancestor_hashes[0]
  # TODO actually get parent block, which means fixing up BeaconState refs above;
  # there's no distinction between active/crystallized state anymore, etc.
  let parent_slot = 0'u64

  for attestation in blck.attestations:
    doAssert attestation.data.slot <= blck.slot - MIN_ATTESTATION_INCLUSION_DELAY
    doAssert attestation.data.slot >= max(parent_slot - CYCLE_LENGTH + 1, 0)
    #doAssert attestation.data.justified_slot == justification_source if attestation.data.slot >= state.last_state_recalculation_slot else prev_cycle_justification_source
    # doAssert attestation.data.justified_block_hash == get_block_hash(state, block, attestation.data.justified_slot).
    # doAssert either attestation.data.last_crosslink_hash or attestation.data.shard_block_hash equals state.crosslinks[shard].shard_block_hash.

    # Let attestation_indices be get_shards_and_committees_for_slot(crystallized_state, slot)[x], choosing x so that attestation_indices.shard_id equals the shard_id value provided to find the set of validators that is creating this attestation record.
    let attestation_indices = block:
      let shard_and_committees = get_shards_and_committees_for_slot(crystallized_state, slot)
      var
        x = 1
        record_creator = shard_and_committees[0]
      while record_creator.shard != attestation.data.shard:
        record_creator = shard_and_committees[x]
        inc x
      record_creator

    # Verify that len(attester_bitfield) == ceil_div8(len(attestation_indices)), where ceil_div8 = (x + 7) // 8. Verify that bits len(attestation_indices).... and higher, if present (i.e. len(attestation_indices) is not a multiple of 8), are all zero
    doAssert attestation.attester_bitfield.len == attestation_indices.committee.len

    # Derive a group public key by adding the public keys of all of the attesters in attestation_indices for whom the corresponding bit in attester_bitfield (the ith bit is (attester_bitfield[i // 8] >> (7 - (i %8))) % 2) equals 1
    var agg_pubkey: Eth2PublicKey
    var empty = true
    for attester_idx in attestation_indices.committee:
      # TODO re-enable, but currently this whole function's a nonfunctional stub
      # because state's lacking.
      #if attester_idx in attestation.attester_bitfield:
        let validator = crystallized_state.validators[attester_idx]
        if empty:
          agg_pubkey = validator.pubkey
          empty = false
        else:
          agg_pubkey.combine(validator.pubkey)

    # Verify that aggregate_sig verifies using the group pubkey generated and hash((slot % CYCLE_LENGTH).to_bytes(8, 'big') + parent_hashes + shard_id + shard_block_hash) as the message.
    var msg: array[32, byte]

    block:
      var ctx: blake2_512 # Context for streaming blake2b computation
      ctx.init()

      var be_slot: array[8, byte]
      bigEndian64(be_slot[0].addr, attestation.data.slot.unsafeAddr)
      ctx.update be_slot

      # TODO: re-enable these, but parent_hashes isn't in new spec, so
      # this needs more substantial adjustment.
      # let size_p_hashes = uint parent_hashes.len * sizeof(Eth2Digest)
      # ctx.update(cast[ptr byte](parent_hashes[0].addr), size_p_hashes)

      var be_shard_id: array[2, byte]           # Unsure, spec doesn't mention big-endian representation
      bigEndian16(be_shard_id.addr, attestation.data.shard.unsafeAddr)
      ctx.update be_shard_id

      ctx.update attestation.data.shard_block_hash.data

      var be_justified_slot: array[8, byte]
      bigEndian64(be_justified_slot[0].addr, attestation.data.justified_slot.unsafeAddr)
      ctx.update be_justified_slot

      let h = ctx.finish()                      # Full hash (Blake2b-512)
      msg[0 ..< 32] = h.data.toOpenArray(0, 32) # Keep only the first 32 bytes - https://github.com/ethereum/beacon_chain/issues/60

      ctx.clear()                               # Cleanup context/memory

    # For now only check compilation
    # doAssert attestation.aggregate_sig.verifyMessage(msg, agg_pubkey)
    debugEcho "Aggregate sig verify message: ", attestation.aggregate_sig.verifyMessage(msg, agg_pubkey)

  # Extend the list of AttestationRecord objects in the active_state, ordering the new additions in the same order as they came in the block.
  # TODO

  # Verify that the slot % len(get_indices_for_slot(crystallized_state, slot-1)[0])'th attester in get_indices_for_slot(crystallized_state, slot-1)[0]is part of at least one of the AttestationRecord objects; this attester can be considered to be the proposer of the block.
  # TODO

