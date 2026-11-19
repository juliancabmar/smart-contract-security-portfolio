// Add the following test to `test/consensus/ConsensusRegistryTest.t.sol`
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
