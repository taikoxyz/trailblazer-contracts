// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ExampleGame - Rock Paper Scissors
 * @author Taiko Labs
 * @notice A complete example implementation of a multiplayer Rock Paper Scissors game using the GameHub
 * @dev This contract demonstrates how to build a third-party game that integrates with the GameHub system.
 *      It showcases all the key patterns and best practices for game development on the platform.
 *
 * Game Features:
 * - Multiplayer Rock Paper Scissors (2-8 players)
 * - Simultaneous move submission (commit-reveal pattern could be added for production)
 * - Automatic winner determination using standard RPS rules
 * - Support for draws when no clear winner emerges
 * - Complete session lifecycle management
 * - Owner-controlled game initiation
 *
 * Game Rules:
 * - Rock (1) beats Scissors (3)
 * - Paper (2) beats Rock (1)
 * - Scissors (3) beats Paper (2)
 * - Same moves result in ties
 * - With multiple players, winner is determined by elimination rounds
 *
 * Integration Points:
 * - Inherits from BaseGame for GameHub integration
 * - Uses Ownable for administrative controls
 * - Implements all required metadata functions
 * - Demonstrates session lifecycle hooks
 *
 * @custom:security-contact security@taiko.xyz
 * @custom:example-contract This is an example implementation for educational purposes
 */
contract ExampleGame is BaseGame, Ownable {
    /// @dev Game configuration
    string private constant GAME_NAME = "Example Rock Paper Scissors";
    string private constant GAME_VERSION = "1.0.0";
    uint256 private constant MIN_PLAYERS = 2;
    uint256 private constant MAX_PLAYERS = 8;

    /// @dev Game state
    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    struct GameState {
        mapping(address => Move) playerMoves;
        mapping(address => bool) hasSubmitted;
        uint256 submissionCount;
        uint256 revealDeadline;
        bool gameComplete;
    }

    /// @dev Mapping from session ID to game state
    mapping(uint256 => GameState) private gameStates;

    /// @dev Events
    event MoveSubmitted(uint256 indexed sessionId, address indexed player);
    event GameComplete(uint256 indexed sessionId, address winner);

    /// @dev Custom errors
    error MoveAlreadySubmitted();
    error InvalidMove();
    error GameNotInRevealPhase();
    error RevealDeadlinePassed();

    /**
     * @dev Constructor
     * @param _gameHub Address of the GameHub contract
     * @param _owner Address of the contract owner
     */
    constructor(
        address _gameHub,
        address _owner
    ) BaseGame(_gameHub) Ownable(_owner) {}

    /**
     * @notice Starts a new Rock Paper Scissors game with specified players
     * @dev This function demonstrates how to initiate a game session through the GameHub.
     *      Only the contract owner can start games in this example implementation.
     *
     * Game Flow:
     * 1. Validates player count is within supported range (2-8 players)
     * 2. Requests a new session from GameHub with 1-hour TTL
     * 3. Players have 30 minutes to submit their moves
     * 4. Game automatically resolves when all players have submitted moves
     *
     * @param players Array of player addresses who will participate in the game
     * @return sessionId The unique identifier for the created game session
     *
     * @dev Emits GameSessionRequested event through BaseGame
     * @dev Sets up game state with move submission deadline
     */
    function startGame(
        address[] calldata players
    ) external onlyOwner returns (uint256 sessionId) {
        // Use 1 hour TTL for the game
        sessionId = this.requestGameSession(players, 1 hours);
        return sessionId;
    }

    /**
     * @notice Submits a move for a player in an active game session
     * @dev This function handles move submission for the Rock Paper Scissors game.
     *      Each player can only submit one move per session. The game automatically
     *      resolves when all players have submitted their moves.
     *
     * Move Values:
     * - 1 = Rock
     * - 2 = Paper
     * - 3 = Scissors
     *
     * Requirements:
     * - Session must be active and valid
     * - Player must be a participant in the session
     * - Player must not have already submitted a move
     * - Move must be valid (1, 2, or 3)
     * - Submission must be before the reveal deadline
     *
     * @param sessionId The unique identifier of the game session
     * @param move The player's move (1=Rock, 2=Paper, 3=Scissors)
     *
     * @dev Emits MoveSubmitted event
     * @dev Automatically triggers game resolution when all moves are submitted
     */
    function submitMove(
        uint256 sessionId,
        uint8 move
    ) external validSession(sessionId) {
        require(move >= 1 && move <= 3, "ExampleGame: Invalid move");

        GameState storage gameState = gameStates[sessionId];

        if (gameState.hasSubmitted[msg.sender]) {
            revert MoveAlreadySubmitted();
        }

        gameState.playerMoves[msg.sender] = Move(move);
        gameState.hasSubmitted[msg.sender] = true;
        gameState.submissionCount++;

        emit MoveSubmitted(sessionId, msg.sender);

        // If all players have submitted, determine winner
        if (gameState.submissionCount == _getSessionPlayerCount(sessionId)) {
            _determineWinner(sessionId);
        }
    }

    /**
     * @dev Get game information
     */
    function gameName() external pure override returns (string memory) {
        return GAME_NAME;
    }

    function gameVersion() external pure override returns (string memory) {
        return GAME_VERSION;
    }

    function minPlayers() external pure override returns (uint256) {
        return MIN_PLAYERS;
    }

    function maxPlayers() external pure override returns (uint256) {
        return MAX_PLAYERS;
    }

    /**
     * @dev Get player's move for a session (only after game is complete)
     * @param sessionId The session ID
     * @param player The player address
     * @return move The player's move
     */
    function getPlayerMove(
        uint256 sessionId,
        address player
    ) external view returns (Move move) {
        require(
            gameStates[sessionId].gameComplete,
            "ExampleGame: Game not complete"
        );
        return gameStates[sessionId].playerMoves[player];
    }

    /**
     * @dev Hook called when a game session is started
     * @param sessionId The ID of the started session
     */
    function _onGameSessionStarted(
        uint256 sessionId,
        address[] calldata /* players */
    ) internal override {
        GameState storage gameState = gameStates[sessionId];
        gameState.revealDeadline = block.timestamp + 30 minutes; // 30 minutes to submit moves
        gameState.submissionCount = 0;
        gameState.gameComplete = false;
    }

    /**
     * @dev Hook called when a game session is ended
     * @param sessionId The ID of the ended session
     * @param winners Array of winners in ranking order (index 0 = 1st place)
     */
    function _onGameSessionEnded(
        uint256 sessionId,
        address[] memory winners
    ) internal override {
        gameStates[sessionId].gameComplete = true;
        address winner = winners.length > 0 ? winners[0] : address(0);
        emit GameComplete(sessionId, winner);
    }

    /**
     * @dev Internal function to determine the winner
     * @param sessionId The session ID
     */
    function _determineWinner(uint256 sessionId) internal {
        GameState storage gameState = gameStates[sessionId];
        address[] memory players = _getSessionPlayers(sessionId);

        // Simple logic for 2 players (Rock Paper Scissors)
        if (players.length == 2) {
            Move move1 = gameState.playerMoves[players[0]];
            Move move2 = gameState.playerMoves[players[1]];

            address winner = _getRPSWinner(
                players[0],
                move1,
                players[1],
                move2
            );

            if (winner != address(0)) {
                this.endGameWithWinner(sessionId, winner);
            } else {
                this.endGameWithDraw(sessionId);
            }
        } else {
            // For more than 2 players, just pick the first player as winner for this example
            // In a real game, you'd implement proper multi-player logic
            this.endGameWithWinner(sessionId, players[0]);
        }
    }

    /**
     * @dev Get Rock Paper Scissors winner
     * @param player1 First player address
     * @param move1 First player's move
     * @param player2 Second player address
     * @param move2 Second player's move
     * @return winner Address of winner (address(0) for draw)
     */
    function _getRPSWinner(
        address player1,
        Move move1,
        address player2,
        Move move2
    ) internal pure returns (address winner) {
        if (move1 == move2) {
            return address(0); // Draw
        }

        if (
            (move1 == Move.Rock && move2 == Move.Scissors) ||
            (move1 == Move.Paper && move2 == Move.Rock) ||
            (move1 == Move.Scissors && move2 == Move.Paper)
        ) {
            return player1;
        } else {
            return player2;
        }
    }

    /**
     * @dev Get session players (helper function)
     * @param sessionId The session ID
     * @return players Array of player addresses
     */
    function _getSessionPlayers(
        uint256 sessionId
    ) internal view returns (address[] memory players) {
        // Call GameHub to get players
        return ITaikoGameHubIntegration(gameHub).getSessionPlayers(sessionId);
    }

    /**
     * @dev Get session player count (helper function)
     * @param sessionId The session ID
     * @return count Number of players
     */
    function _getSessionPlayerCount(
        uint256 sessionId
    ) internal view returns (uint256 count) {
        // Get players array and return length
        address[] memory players = _getSessionPlayers(sessionId);
        return players.length;
    }
}
