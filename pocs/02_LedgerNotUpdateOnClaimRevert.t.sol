// Add the following test to `test/consensus/ConsensusRegistryTest.t.sol`:

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
