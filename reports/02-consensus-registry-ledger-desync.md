### [High] Failed Reward Transfers Revert Ledger Updates, Violating Capital Accounting Invariant

**Description:**\
When `ConsensusRegistry::claimStakeRewards` is called and the internal call to `Issuance.distributeStakeReward` fails due to insufficient funds, the entire transaction reverts — including the ledger update that decrements the validator’s reward balance. This behavior violates the invariant stating: “claims can revert if Issuance contract runs dry (e.g., TAO governance problem), but rewards ledger must continue being updated by applyIncentives or applySlashes.”

Although this invariant focuses on reward *addition* via `applyIncentives` or `applySlashes`, its intent is to guarantee **ledger integrity regardless of Issuance liquidity**. The ledger should always reflect the correct, current reward state — even if rewards cannot be transferred.

**Impact:**
- The validator’s reward balance remains unchanged after a failed claim, creating an incorrect accounting state.
- The reward appears as if it was never claimed, allowing for indefinite reattempts and potentially inflating perceived system liabilities.
- Breaks the separation between token transfer failure and state mutation, weakening protocol robustness under partial failure conditions.
- Violates a documented critical invariant, undermining auditability and economic correctness.

**Proof of Concept:**\
Add the following test to `test/consensus/ConsensusRegistryTest.t.sol`:
<details><summary>PoC</summary>

```solidity
import { RewardInfo } from "src/interfaces/IStakeManager.sol";
import { Issuance } from "src/consensus/Issuance.sol";

function testLedgerNotUpdateOnClaimRevert() public {
    // configuring validator
    address validatorBob = makeAddr("bob");

    // Number of headers procesess by Bob
    uint8 bobHeaderCount = 20;

    // number must be up than 5 (yet taken)
    bytes memory validatorBobBlsPubkey = _createRandomBlsPubkey(6);

    // 1_000_000e18 this is the minimum stake amount allowed
    uint256 stakeAmount = 1_000_000e18;
    vm.deal(validatorBob, stakeAmount);

    // The consensus registry owner mint a ConsensusNFT for whitelist the validator
    vm.prank(crOwner);
    consensusRegistry.mint(validatorBob);

    // Stake the minimum TEL amount for get the activation
    vm.prank(validatorBob);
    consensusRegistry.stake{ value: stakeAmount }(validatorBobBlsPubkey);

    RewardInfo[] memory rewards = new RewardInfo[](1);
    rewards[0] = RewardInfo({ validatorAddress: validatorBob, consensusHeaderCount: bobHeaderCount });

    // Apply incentives for the epoch
    vm.prank(sysAddress);
    consensusRegistry.applyIncentives(rewards);

    uint256 prevBobRewards = consensusRegistry.getRewards(validatorBob);

    // Dry the Issuance contract, now will can't to afront the rewards pay
    vm.deal(consensusRegistry.issuance(), 0);

    // Bob fails to claims his accumulated rewards
    vm.expectPartialRevert(Issuance.InsufficientBalance.selector);
    vm.prank(validatorBob);
    consensusRegistry.claimStakeRewards(validatorBob);

    uint256 actualBobRewards = consensusRegistry.getRewards(validatorBob);

    // check for unchanged Bob rewards in the ledge
    assertEq(prevBobRewards, actualBobRewards);
}
```
</details>

**Recommended Mitigation:**\
Refactor `claimStakeRewards` to decouple reward ledger updates from the token transfer. Ensure the internal reward balance is always cleared regardless of whether the `Issuance` transfer succeeds. In the event of a failed transfer, emit a failure event (e.g., `RewardTransferFailed`) and optionally track unpaid rewards for future governance resolution.
