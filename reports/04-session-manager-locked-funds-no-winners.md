### [Medium]`SessionManager::concludeGame`: Game With No Winners Cannot Be Concluded, Causing Locked Funds

**Description:**

The `concludeGame` function in `SessionManager` requires that a game has at least one winner (`winners.length > 0`) before it can be concluded. If a game reaches the `Ended` state and no winners are determined, the function will revert and the game cannot transition to the `Concluded` state. As a result, all funds associated with the session (entry fees, sponsor deposits, rewards, and fees) remain locked in the contract, with no way to distribute, refund, or recover.

<summary>src/SessionManager.sol</summary>

```solidity
    function concludeGame(uint256 sessionId) external onlyCreator(sessionId) onlyState(sessionId, SessionState.Ended) {
        Game storage game = games[sessionId];
        require(game.numContestants != 0, NoContestantsInGame(sessionId));
        address[] memory winners = ISessionStrategy(game.sessionStrategy).getWinners(sessionId);
@>      require(winners.length > 0, NoWinnersYet(sessionId));
        game.state = SessionState.Concluded;
        emit GameConcluded(sessionId, true, true);
    }
```

Protocol fees, creator fees and referrers rewards can't will be distributed because require the `Concluded` state:
```solidity
    function distributeFees(uint256 sessionId) external
@>      onlyState(sessionId, SessionState.Concluded) {
        _distributeFees(
            sessionId,
            games[sessionId].creatorfeeReceiver != address(0)
                ? games[sessionId].creatorfeeReceiver
                : games[sessionId].creator,
            Registry(registry).protocolTreasury()
        );
    }
```

```solidity
    function claimReferralRewards(uint256[] memory sessionIds) external {
        for (uint256 i; i < sessionIds.length; ++i) {
            require(
@>              games[sessionIds[i]].state == SessionState.Concluded,
                InvalidGameState(SessionState.Concluded, games[sessionIds[i]].state)
            );
            _claimReferralReward(sessionIds[i]);
        }
    }
```

**Impact:**

- **Irrecoverable Funds:** Entry fees, sponsor funds, and rewards for the session are stuck in the contract permanently, as the session cannot be concluded or cancelled.
- **No Reward or Fee Distribution:** Neither the creator, protocol, nor any participant can claim rewards or fees for the session.

**Proof of Concept:**\
Add the following import and test to `test/e2e/FullGameTest.t.sol`
<details><summary>PoC</summary>

```diff
    .
    .
    .
    import {SPBinaryPrompt} from "../../src/prompt/SPBinaryPrompt.sol";
    import {TestUSDC} from "../TestUSDC.sol";
    import {ISessionStrategy} from "../../src/session/ISessionStrategy.sol";
    import {SessionResultAsserter} from "../../src/offchain/uma/SessionResultAsserter.sol";
    import {FixedRanksReward} from "../../src/reward/FixedRanksReward.sol";

+   import {TriviaChoicePrompt} from "../../src/prompt/TriviaChoicePrompt.sol";
```
```solidity
function test_fundsStuckByNoWinners() public {
    uint256 joinFee = 10 ether;

    // create and register the strategy
    TriviaChoicePrompt triviaChoicePromptStrategy = new TriviaChoicePrompt(address(registry));
    registry.registerPromptStrategy(address(triviaChoicePromptStrategy), true);
    uint256[] memory usersSalts = Solarray.uint256s(1, 2, 3);

    // create the trivia question
    uint256 nextSessionId = sessionManager.nextSessionId();
    uint256 question5Id = sessionManager.nextQuestionId();

    uint16 solution = 1; // "Paris"
    uint256 creatorSalt = 1234;
    bytes32 solutionCommitment =
        keccak256(abi.encodePacked(nextSessionId, question5Id, abi.encode(solution), creatorSalt));

    TriviaChoicePrompt.Prompt memory question = TriviaChoicePrompt.Prompt({
        sessionManager: address(sessionManager),
        questionText: "What is the capital of France?",
        media: new string[](0),
        reactionDeadline: 3600,
        solutionCommitment: solutionCommitment,
        solution: solution, // "Paris"
        choices: Solarray.strings("London", "Paris", "Berlin", "Madrid")
    });

    bytes memory q5Encoded = abi.encode(question);
    bytes32 question5Hash = keccak256(abi.encodePacked(q5Encoded, creatorSalt));

    // create the game
    uint32 startTime = uint32(block.timestamp + 1 days);
    uint32 endTime = uint32(startTime + 1 minutes);

    questionHashes = new bytes32[](1);
    questionStrategies = new address[](1);
    questionSalts = new uint256[](1);

    questionHashes[0] = question5Hash;
    questionStrategies[0] = address(triviaChoicePromptStrategy);
    questionSalts[0] = creatorSalt;

    vm.startPrank(creator);
    uint256 triviaGameId =
        createGame(startTime, endTime, joinFee, 10, questionHashes, questionStrategies, rewardStrategy, false);
    FixedRanksReward(rewardStrategy).setRankedRewards(triviaGameId, Solarray.uint256s(10_000));
    vm.stopPrank();

    // Join game with 3 contestants (creator included)
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        TestUSDC(usdc).approve(address(sessionManager), joinFee);
        sessionManager.joinGame(triviaGameId);
        vm.stopPrank();
    }

    // forward to start time and reveal the question
    vm.warp(startTime);
    vm.prank(creator);
    sessionManager.startAndRevealGameQuestion(triviaGameId, question5Id, q5Encoded, creatorSalt);

    // players commit his answers
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        uint16 choice = 0; // everyone give the wrong answer
        bytes32 commit = keccak256(abi.encodePacked(triviaGameId, question5Id, choice, usersSalts[i]));
        sessionManager.commitReaction(triviaGameId, question5Id, commit);
        vm.stopPrank();
    }

    // forward the time and reveal the answers
    vm.warp(block.timestamp + 10);
    for (uint256 i = 0; i < 3; i++) {
        vm.startPrank(contestants[i]);
        sessionManager.revealReactions(
            triviaGameId,
            Solarray.uint256s(question5Id),
            Solarray.bytess(abi.encode(uint16(0))), // everyone give the wrong answer
            usersSalts[i]
        );
        vm.stopPrank();
    }

    vm.warp(endTime + 1 days);

    // the creator reveal the solution
    vm.prank(creator);
    triviaChoicePromptStrategy.revealSolutions(
        triviaGameId,
        Solarray.uint256s(question5Id),
        Solarray.bytess(abi.encode(uint16(1))),
        Solarray.uint256s(creatorSalt)
    );

    // forward to end time and finish the game
    vm.prank(creator);
    sessionManager.endGame(triviaGameId);

    // Mock oracle
    vm.mockCall(
        address(optimisticOracle), abi.encodeCall(OptimisticOracleV3Interface.getMinimumBond, (usdc)), abi.encode(0)
    );
    vm.mockCall(
        address(optimisticOracle),
        abi.encodeWithSelector(OptimisticOracleV3Interface.assertTruth.selector),
        abi.encode(bytes32(0))
    );

    // Simulate no winners adding empty arrays as params
    vm.startPrank(creator);
    bytes32 assertionId = ISessionStrategy(sessionStrategy).assertResults(
        triviaGameId,
        "ipfs address of all results",
        new address[](0),
        new uint256[](0),
        new uint256[](0),
        new bytes[](0)
    );
    vm.stopPrank();

    // Resolve the assertion
    vm.prank(optimisticOracle);
    SessionResultAsserter(sessionStrategy).assertionResolvedCallback(assertionId, true);

    uint256 numOfWinners = ISessionStrategy(sessionStrategy).getWinners(triviaGameId).length;

    (,,,,, SessionState state,,,,,) = sessionManager.games(triviaGameId);

    // The session is in Ended state
    assertEq(uint256(state), uint256(SessionState.Ended));

    // Nobody wins
    assertEq(numOfWinners, 0);

    // When attempt to conclude game, the call reverts with "NoWinnersYet"
    vm.expectPartialRevert(SessionManager.NoWinnersYet.selector);
    vm.prank(creator);
    sessionManager.concludeGame(triviaGameId);

    // When attempt to distribute the creator and protocol fees, the call reverts with "InvalidGameState"
    vm.expectPartialRevert(ISessionStrategy.InvalidGameState.selector);
    vm.prank(creator);
    sessionManager.distributeFees(triviaGameId);

    // When the referrer attempt to claim his reward, the call reverts with "InvalidGameState"
    vm.expectPartialRevert(ISessionStrategy.InvalidGameState.selector);
    vm.prank(referrers[0]);
    sessionManager.claimReferralRewards(Solarray.uint256s(triviaGameId));

    // All the fees will be stuck on the SessionManager contract
    assertEq(TestUSDC(usdc).balanceOf(address(sessionManager)), joinFee * 3);
}
```
</details>

**Recommended Mitigation:**

- Implement an emergency or fallback mechanism to allow the creator or protocol admin to reclaim or refund locked funds for sessions with no winners.
- Consider allowing the session to be concluded even if there are zero winners, triggering a refund or alternative distribution logic.
