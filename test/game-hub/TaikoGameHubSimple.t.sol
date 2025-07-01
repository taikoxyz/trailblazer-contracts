// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "../../contracts/game-hub/TaikoGameHub.sol";
import "../../contracts/game-hub/examples/ExampleGame.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TaikoGameHubTest is Test {
    TaikoGameHub public gameHub;
    TaikoGameHub public gameHubImpl;
    ExampleGame public exampleGame;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public player4 = makeAddr("player4");
    address public gameContract = makeAddr("gameContract");

    event GameWhitelisted(address indexed game);
    event GameRemovedFromWhitelist(address indexed game);
    event GameStarted(
        uint256 indexed sessionId,
        address indexed game,
        address[] participants
    );
    event GameEnded(
        uint256 indexed sessionId,
        address indexed game,
        address[] winners,
        address[] participants,
        bool isDrawn
    );

    function setUp() public {
        // Deploy implementation
        gameHubImpl = new TaikoGameHub();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            TaikoGameHub.initialize.selector,
            owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(gameHubImpl), initData);

        gameHub = TaikoGameHub(address(proxy));

        // Deploy example game
        exampleGame = new ExampleGame(address(gameHub), owner);
    }

    function test_Initialize() public view {
        assertEq(gameHub.owner(), owner);
        assertEq(gameHub.latestSessionId(), 0);
        assertEq(gameHub.VERSION(), "1.0.0");
    }

    function test_WhitelistGame() public {
        vm.startPrank(owner);

        vm.expectEmit(true, false, false, false);
        emit GameWhitelisted(gameContract);

        gameHub.whitelist(gameContract);

        assertTrue(gameHub.isWhitelisted(gameContract));
        vm.stopPrank();
    }

    function test_StartGameSession() public {
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();

        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.startPrank(gameContract);

        vm.expectEmit(true, true, false, true);
        emit GameStarted(1, gameContract, players);

        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);

        assertEq(sessionId, 1);
        assertEq(gameHub.latestSessionId(), 1);
        assertTrue(gameHub.isInGame(player1));
        assertTrue(gameHub.isInGame(player2));

        vm.stopPrank();
    }

    function test_EndGameWithWinner() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();

        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);

        address[] memory winners = new address[](1);
        winners[0] = player1;

        vm.expectEmit(true, true, false, true);
        emit GameEnded(sessionId, gameContract, winners, players, false);

        gameHub.endGameWithWinner(sessionId, player1);

        // Check players are unlocked
        assertFalse(gameHub.isInGame(player1));
        assertFalse(gameHub.isInGame(player2));

        // Check winners
        address[] memory sessionWinners = gameHub.getSessionWinners(sessionId);
        assertEq(sessionWinners.length, 1);
        assertEq(sessionWinners[0], player1);

        // Check convenience getter
        assertEq(gameHub.getSessionWinner(sessionId), player1);

        vm.stopPrank();
    }

    function test_EndGameWithRankedWinners() public {
        // Setup game session with 4 players
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();

        address[] memory players = new address[](4);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;
        players[3] = player4;

        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);

        // End with ranked winners: player3 = 1st, player1 = 2nd, player4 = 3rd
        address[] memory winners = new address[](3);
        winners[0] = player3; // 1st place
        winners[1] = player1; // 2nd place
        winners[2] = player4; // 3rd place

        vm.expectEmit(true, true, false, true);
        emit GameEnded(sessionId, gameContract, winners, players, false);

        gameHub.endGameWithWinners(sessionId, winners);

        // Check winners
        address[] memory sessionWinners = gameHub.getSessionWinners(sessionId);
        assertEq(sessionWinners.length, 3);
        assertEq(sessionWinners[0], player3); // 1st place
        assertEq(sessionWinners[1], player1); // 2nd place
        assertEq(sessionWinners[2], player4); // 3rd place

        // Check convenience getter returns 1st place winner
        assertEq(gameHub.getSessionWinner(sessionId), player3);

        // Check session state
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        assertTrue(session.ended);
        assertFalse(session.isDrawn);

        vm.stopPrank();
    }

    function test_EndGameWithDraw() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();

        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;

        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);

        address[] memory emptyWinners = new address[](0);

        vm.expectEmit(true, true, false, true);
        emit GameEnded(sessionId, gameContract, emptyWinners, players, true);

        gameHub.endGameWithDraw(sessionId);

        // Check no winners
        address[] memory sessionWinners = gameHub.getSessionWinners(sessionId);
        assertEq(sessionWinners.length, 0);

        // Check convenience getter returns address(0) for draw
        assertEq(gameHub.getSessionWinner(sessionId), address(0));

        // Check session state
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        assertTrue(session.ended);
        assertTrue(session.isDrawn);

        vm.stopPrank();
    }
}
