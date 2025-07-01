// import "forge-std/src/Test.sol";
import "../../contracts/game-hub/TaikoGameHub.sol";
import "../../contracts/game-hub/examples/ExampleGame.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
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
    event GameStarted(uint256 indexed sessionId, address indexed game, address[] participants);
    event GameEnded(uint256 indexed sessionId, address indexed game, address indexed winner, address[] participants);

    function setUp() public {
        // Deploy implementation
        gameHubImpl = new TaikoGameHub();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            TaikoGameHub.initialize.selector,
            owner
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(gameHubImpl),
            initData
        );
        
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

    function test_WhitelistGame_RevertIfNotOwner() public {
        vm.startPrank(player1);
        
        vm.expectRevert();
        gameHub.whitelist(gameContract);
        
        vm.stopPrank();
    }

    function test_RemoveFromWhitelist() public {
        vm.startPrank(owner);
        
        // First whitelist
        gameHub.whitelist(gameContract);
        assertTrue(gameHub.isWhitelisted(gameContract));
        
        // Then remove
        vm.expectEmit(true, false, false, false);
        emit GameRemovedFromWhitelist(gameContract);
        
        gameHub.removeFromWhitelist(gameContract);
        
        assertFalse(gameHub.isWhitelisted(gameContract));
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
        assertEq(gameHub.playerCurrentSession(player1), 1);
        assertEq(gameHub.playerCurrentSession(player2), 1);
        
        vm.stopPrank();
    }

    function test_StartGameSession_RevertIfNotWhitelisted() public {
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.GameNotWhitelisted.selector, gameContract));
        gameHub.requestGameSession(players, 1 hours);
        
        vm.stopPrank();
    }

    function test_StartGameSession_RevertIfEmptyPlayers() public {
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](0);
        
        vm.startPrank(gameContract);
        
        vm.expectRevert(TaikoGameHub.EmptyPlayersArray.selector);
        gameHub.requestGameSession(players, 1 hours);
        
        vm.stopPrank();
    }

    function test_StartGameSession_RevertIfPlayerAlreadyInGame() public {
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        
        // Start first game
        gameHub.requestGameSession(players, 1 hours);
        
        // Try to start second game with same player
        address[] memory players2 = new address[](2);
        players2[0] = player1; // Same player
        players2[1] = player3;
        
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.PlayerAlreadyInGame.selector, player1));
        gameHub.requestGameSession(players2, 1 hours);
        
        vm.stopPrank();
    }

    function test_StartGameSession_RevertIfDuplicatePlayer() public {
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player1; // Duplicate
        
        vm.startPrank(gameContract);
        
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.DuplicatePlayer.selector, player1));
        gameHub.requestGameSession(players, 1 hours);
        
        vm.stopPrank();
    }

    function test_StartGameSession_RevertIfInvalidTTL() public {
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        
        // TTL too short
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.InvalidTTL.selector, 1 minutes));
        gameHub.requestGameSession(players, 1 minutes);
        
        // TTL too long
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.InvalidTTL.selector, 25 hours));
        gameHub.requestGameSession(players, 25 hours);
        
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
        
        vm.expectEmit(true, true, true, true);
        emit GameEnded(sessionId, gameContract, player1, players);
        
        gameHub.endGameWithWinner(sessionId, player1);
        
        // Check game state
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        assertTrue(session.ended);
        assertEq(session.winner, player1);
        assertEq(gameHub.sessionWinner(sessionId), player1);
        
        // Check players are unlocked
        assertFalse(gameHub.isInGame(player1));
        assertFalse(gameHub.isInGame(player2));
        assertEq(gameHub.playerCurrentSession(player1), 0);
        assertEq(gameHub.playerCurrentSession(player2), 0);
        
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
        
        vm.expectEmit(true, true, true, true);
        emit GameEnded(sessionId, gameContract, address(0), players);
        
        gameHub.endGameWithDraw(sessionId);
        
        // Check game state
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        assertTrue(session.ended);
        assertEq(session.winner, address(0));
        assertEq(gameHub.sessionWinner(sessionId), address(0));
        
        vm.stopPrank();
    }

    function test_EndGame_RevertIfWrongGame() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        gameHub.whitelist(address(exampleGame));
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        // Try to end from different game
        vm.startPrank(address(exampleGame));
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.UnauthorizedGameAccess.selector, sessionId, address(exampleGame)));
        gameHub.endGameWithWinner(sessionId, player1);
        vm.stopPrank();
    }

    function test_EndGame_RevertIfAlreadyEnded() public {
        // Setup and end game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        gameHub.endGameWithWinner(sessionId, player1);
        
        // Try to end again
        vm.expectRevert(abi.encodeWithSelector(TaikoGameHub.GameSessionAlreadyEnded.selector, sessionId));
        gameHub.endGameWithWinner(sessionId, player2);
        
        vm.stopPrank();
    }

    function test_ForceEndExpiredSession() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        // Fast forward past TTL
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectEmit(true, true, true, true);
        emit GameEnded(sessionId, gameContract, address(0), players);
        
        gameHub.forceEndExpiredSession(sessionId);
        
        // Check game state
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        assertTrue(session.ended);
        assertEq(session.winner, address(0));
    }

    function test_ForceEndExpiredSession_RevertIfNotExpired() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        // Try to force end before expiry
        vm.expectRevert("TaikoGameHub: Session not expired");
        gameHub.forceEndExpiredSession(sessionId);
    }

    function test_GetGameSession() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        TaikoGameHub.GameSession memory session = gameHub.getGameSession(sessionId);
        
        assertEq(session.sessionId, sessionId);
        assertEq(session.players.length, 2);
        assertEq(session.players[0], player1);
        assertEq(session.players[1], player2);
        assertEq(session.game, gameContract);
        assertEq(session.ttl, 1 hours);
        assertEq(session.winner, address(0));
        assertFalse(session.ended);
    }

    function test_GetSessionPlayers() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        address[] memory sessionPlayers = gameHub.getSessionPlayers(sessionId);
        
        assertEq(sessionPlayers.length, 3);
        assertEq(sessionPlayers[0], player1);
        assertEq(sessionPlayers[1], player2);
        assertEq(sessionPlayers[2], player3);
    }

    function test_IsSessionActive() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        
        // Should be active initially
        assertTrue(gameHub.isSessionActive(sessionId));
        
        // Should be inactive after ending
        gameHub.endGameWithWinner(sessionId, player1);
        assertFalse(gameHub.isSessionActive(sessionId));
        
        vm.stopPrank();
    }

    function test_IsSessionActive_ExpiredSession() public {
        // Setup game session
        vm.startPrank(owner);
        gameHub.whitelist(gameContract);
        vm.stopPrank();
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        
        vm.startPrank(gameContract);
        uint256 sessionId = gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        // Should be active initially
        assertTrue(gameHub.isSessionActive(sessionId));
        
        // Fast forward past TTL
        vm.warp(block.timestamp + 2 hours);
        
        // Should be inactive after expiry
        assertFalse(gameHub.isSessionActive(sessionId));
    }

    function test_Pause_Unpause() public {
        vm.startPrank(owner);
        
        // Pause
        gameHub.pause();
        assertTrue(gameHub.paused());
        
        // Should revert when paused
        gameHub.whitelist(gameContract);
        
        address[] memory players = new address[](2);
        players[0] = player1;
        players[1] = player2;
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        vm.expectRevert();
        gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        gameHub.unpause();
        assertFalse(gameHub.paused());
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(gameContract);
        gameHub.requestGameSession(players, 1 hours);
        vm.stopPrank();
    }

    function test_Version() public view {
        assertEq(gameHub.version(), "1.0.0");
    }
}
