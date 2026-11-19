### [Critical] Order Error on `ConsensusRegistry::delegateStake` Makes Delegators Cannot Claim Stake or Rewards, Violating Capital Flow Invariant

**Description:**\
Delegator can't claim the amount of stake or rewards from the prococol breaking the critic invarian that says "...all capital flows to the stake originator, ie the recipient for both stake and rewards is either a validator's delegator if one exists, or the validator itself if not". The root cause lies in the `ConsensusRegistry::delegateStake` function, on this, the order of the `Delegation` struct data (more precisely, `Delegation.validatorAddress` and `Delegation.delegator`) are "inverted" in the asigment of `delegations[validatorAddress]` mapping member, making now that the validator be at the same time the delegator.
<summary>src/ConsensusRegistry.sol</summary>

```solidity
    function delegateStake(
        bytes calldata blsPubkey,
        address validatorAddress,
        bytes calldata validatorSig
    )
        external
        payable
        override
        whenNotPaused
    {
        if (blsPubkey.length != 96) revert InvalidBLSPubkey();
        // require caller is known & whitelisted, having been issued a ConsensusNFT by governance
        uint8 validatorVersion = getCurrentEpochInfo().stakeVersion;
        uint256 stakeAmt = _checkStakeValue(msg.value, validatorVersion);
        _checkConsensusNFTOwner(validatorAddress);

        // require validator status is `Undefined`
        _checkValidatorStatus(validatorAddress, ValidatorStatus.Undefined);
        uint64 nonce = delegations[validatorAddress].nonce;
        bytes32 blsPubkeyHash = keccak256(blsPubkey);

        // governance may utilize white-glove onboarding or offchain agreements
        if (msg.sender != owner()) {
            bytes32 structHash = keccak256(
                abi.encode(DELEGATION_TYPEHASH, blsPubkeyHash, validatorAddress, msg.sender, validatorVersion, nonce)
            );
            bytes32 digest = _hashTypedData(structHash);
            if (!SignatureCheckerLib.isValidSignatureNowCalldata(validatorAddress, digest, validatorSig)) {
                revert NotValidator(validatorAddress);
            }
        }

        delegations[validatorAddress] =
@>      Delegation(blsPubkeyHash, msg.sender, validatorAddress, validatorVersion, nonce + 1);
                                      ^              ^
                                      |__(inverted)__|

        _recordStaked(blsPubkey, validatorAddress, true, validatorVersion, stakeAmt);
    }
```
<summary>src/interfaces/IStakeManager.sol</summary>

```solidity
    struct Delegation {
        bytes32 blsPubkeyHash;
@>      address validatorAddress;
@>      address delegator;
        uint8 validatorVersion;
        uint64 nonce;
    }
```

**Impact:**
- Delegators are unable to access the rewards that rightfully belong to them according to protocol design.
- Violates a core economic security invariant of the protocol.
- Delegation becomes functionally broken, undermining trust and participation incentives for third-party stakers.
- Could lead to legal or reputational risks if delegators are economically excluded from their share.

**Proof of Concept:**\
Add the following test to `test/consensus/ConsensusRegistryTest.t.sol`:
<details><summary>PoC</summary>

```solidity
import { RewardInfo } from "src/interfaces/IStakeManager.sol";

function testClaimFromDelegated() public {
    // 1_000_000e18 this is the minimum stake amount allowed
    uint256 stakeAmount = 1_000_000e18;

    // create a validator
    (address validatorBob, uint256 validatorBobKey) = makeAddrAndKey("bob");
    vm.deal(validatorBob, stakeAmount);

    // Number of headers procesess by Bob
    uint8 bobHeaderCount = type(uint8).max;

    // add TEL to Issuance contract to afront the rewards pay
    vm.deal(consensusRegistry.issuance(), 10_000_000e18);

    // number must be up than 5 (yet taken)
    bytes memory validatorBobBlsPubkey = _createRandomBlsPubkey(6);

    // create a delegator
    address delegatorAlice = makeAddr("alice");
    vm.deal(delegatorAlice, stakeAmount);

    // The consensus registry owner mint a ConsensusNFT for whitelist the validator
    vm.prank(crOwner);
    consensusRegistry.mint(validatorBob);

    // validator signs delegation
    bytes32 structHash = consensusRegistry.delegationDigest(validatorBobBlsPubkey, validatorBob, delegatorAlice);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorBobKey, structHash);
    bytes memory validatorSig = abi.encodePacked(r, s, v);

    // Alice delegate her stake to bob
    vm.prank(delegatorAlice);
    consensusRegistry.delegateStake{ value: stakeAmount }(validatorBobBlsPubkey, validatorBob, validatorSig);

    // Alice try to unstake and fails
    vm.expectPartialRevert(IStakeManager.NotRecipient.selector);
    vm.prank(delegatorAlice);
    consensusRegistry.unstake(validatorBob);

    // Submmit the activation
    vm.prank(validatorBob);
    consensusRegistry.activate();

    RewardInfo[] memory rewards = new RewardInfo[](1);
    rewards[0] = RewardInfo({ validatorAddress: validatorBob, consensusHeaderCount: bobHeaderCount });

    ValidatorInfo[] memory activeValidators = consensusRegistry.getValidators(ValidatorStatus.Active);

    // Conclude the epoch
    vm.startPrank(sysAddress);
    consensusRegistry.concludeEpoch(_createTokenIdCommittee(activeValidators.length));
    vm.stopPrank();

    // Apply incentives for the epoch
    vm.prank(sysAddress);
    consensusRegistry.applyIncentives(rewards);

    // Alice try to claim his accumulated rewards and fails
    vm.expectPartialRevert(IStakeManager.NotRecipient.selector);
    vm.prank(delegatorAlice);
    consensusRegistry.claimStakeRewards(validatorBob);
}
```
</details>

**Recommended Mitigation:**
- On `ConsensusRegistry::delegateStake` put in the right order `Delegation.validatorAddress` and `Delegation.delegator` parameters.

```diff
    function delegateStake(
        bytes calldata blsPubkey,
        address validatorAddress,
        bytes calldata validatorSig
    )
        external
        payable
        override
        whenNotPaused
    {
    .
    .
    .
        delegations[validatorAddress] =
-       Delegation(blsPubkeyHash, msg.sender, validatorAddress, validatorVersion, nonce + 1);
+       Delegation(blsPubkeyHash, validatorAddress, msg.sender, validatorVersion, nonce + 1);
        _recordStaked(blsPubkey, validatorAddress, true, validatorVersion, stakeAmt);
    }
```

- On `ConsensusRegistry::unstake` and `ConsensusRegistry::claimStakeRewards` ensure that only the stake originator be the final recipient. 
