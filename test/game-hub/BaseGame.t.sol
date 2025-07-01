// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "../../contracts/game-hub/TaikoGameHub.sol";
import "../../contracts/game-hub/examples/ExampleGame.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BaseGameTest is Test {
    TaikoGameHub public gameHub;
    TaikoGameHub public gameHubImpl;
    ExampleGame public exampleGame;

    address public owner = makeAddr("owner");
    address public gameOwner = makeAddr("gameOwner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");

    function setUp() public {
        // Deploy TaikoGameHub with proxy
        gameHubImpl = new TaikoGameHub();

        bytes memory initData = abi.encodeWithSelector(
            TaikoGameHub.initialize.selector,
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(gameHubImpl), initData);

        gameHub = TaikoGameHub(address(proxy));

        // Deploy example game
        exampleGame = new ExampleGame(address(gameHub), gameOwner);

        // Whitelist the example game
        vm.prank(owner);
        gameHub.whitelist(address(exampleGame));
    }

    function test_ExampleGame_GameInfo() public view {
        assertEq(exampleGame.gameName(), "Example Rock Paper Scissors");
        assertEq(exampleGame.gameVersion(), "1.0.0");
        assertEq(exampleGame.minPlayers(), 2);
        assertEq(exampleGame.maxPlayers(), 8);
        assertEq(exampleGame.gameHub(), address(gameHub));
    }

    function test_ExampleGame_SupportsPlayerCount() public view {
        assertTrue(exampleGame.supportsPlayerCount(2));
        assertTrue(exampleGame.supportsPlayerCount(4));
        assertTrue(exampleGame.supportsPlayerCount(8));
        assertFalse(exampleGame.supportsPlayerCount(1));
        assertFalse(exampleGame.supportsPlayerCount(9));
    }

    function test_ExampleGame_StartGame() public {
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        assertEq(sessionId, 1);
        assertTrue(exampleGame.activeGameSessions(sessionId));
        assertEq(exampleGame.currentSessionId(), sessionId);
        assertTrue(exampleGame.hasActiveSession());
    }

    function test_ExampleGame_StartGame_RevertIfNotOwner() public {
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(player1);
        vm.expectRevert();
        exampleGame.startGame(players);
    }

    function test_ExampleGame_StartGame_RevertIfInvalidPlayerCount() public {
        address[] memory players = new address[](1);
        players[0] = player1;

        vm.prank(gameOwner);
        vm.expectRevert("BaseGame: Invalid player count");
        exampleGame.startGame(players);
    }

    function test_ExampleGame_SubmitMove() public {
        // Start game
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        // Submit moves
        vm.prank(player1);
        exampleGame.submitMove(sessionId, 1); // Rock

        vm.prank(player2);
        exampleGame.submitMove(sessionId, 2); // Paper

        // Game should be completed and ended automatically
        assertFalse(exampleGame.hasActiveSession());
        assertFalse(exampleGame.activeGameSessions(sessionId));
    }

    function test_ExampleGame_SubmitMove_RevertIfDuplicate() public {
        // Start game
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        // Submit first move
        vm.prank(player1);
        exampleGame.submitMove(sessionId, 1); // Rock

        // Try to submit again
        vm.prank(player1);
        vm.expectRevert(ExampleGame.MoveAlreadySubmitted.selector);
        exampleGame.submitMove(sessionId, 1);
    }

    function test_ExampleGame_SubmitMove_RevertIfInvalidMove() public {
        // Start game
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        // Submit invalid move
        vm.prank(player1);
        vm.expectRevert("ExampleGame: Invalid move");
        exampleGame.submitMove(sessionId, 0);

        vm.prank(player1);
        vm.expectRevert("ExampleGame: Invalid move");
        exampleGame.submitMove(sessionId, 4);
    }

    function test_ExampleGame_SubmitMove_RevertIfInvalidSession() public {
        // Submit move without starting game
        vm.prank(player1);
        vm.expectRevert(
            abi.encodeWithSelector(BaseGame.InvalidSession.selector, 999)
        );
        exampleGame.submitMove(999, 1);
    }

    function test_ExampleGame_GetPlayerMove() public {
        // Start game
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        // Submit moves
        vm.prank(player1);
        exampleGame.submitMove(sessionId, 1); // Rock

        vm.prank(player2);
        exampleGame.submitMove(sessionId, 2); // Paper

        // Check moves (should be accessible after game completion)
        assertEq(uint256(exampleGame.getPlayerMove(sessionId, player1)), 1); // Rock
        assertEq(uint256(exampleGame.getPlayerMove(sessionId, player2)), 2); // Paper
    }

    function test_ExampleGame_GetPlayerMove_RevertIfGameNotComplete() public {
        // Start game
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.prank(gameOwner);
        uint256 sessionId = exampleGame.startGame(players);

        // Try to get move before game completion
        vm.expectRevert("ExampleGame: Game not complete");
        exampleGame.getPlayerMove(sessionId, player1);
    }
}
