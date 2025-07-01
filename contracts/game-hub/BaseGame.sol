// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ITaikoGameHub.sol";

/**
 * @title BaseGame
 * @author Taiko Labs
 * @notice Abstract base contract for third-party games to integrate with the GameHub
 * @dev This contract provides the essential integration points for games to interact with the GameHub.
 *      Game developers should inherit from this contract and implement the required abstract functions.
 *
 * Key Features:
 * - Automatic GameHub integration with session management
 * - Protected functions that can only be called by GameHub
 * - Session lifecycle hooks for game state management
 * - Built-in validation and error handling
 * - Metadata management for game information
 *
 * Usage:
 * 1. Inherit from BaseGame in your game contract
 * 2. Implement the abstract functions (onSessionStarted, onSessionEnded, getGameMetadata)
 * 3. Use requestGameSession() to create new game sessions
 * 4. Use endGameSession() to resolve games with winners or draws
 * 5. Handle game logic in your contract while session management is handled automatically
 *
 * @custom:security-contact security@taiko.xyz
 */
abstract contract BaseGame is IThirdPartyGame {
    /// @dev Address of the GameHub contract
    address public immutable gameHub;

    /// @dev Current active session ID
    uint256 public currentSessionId;

    /// @dev Mapping from session ID to game state
    mapping(uint256 => bool) public activeGameSessions;

    /// @dev Events
    event GameSessionRequested(uint256 indexed sessionId, address[] players);
    event GameSessionEnded(uint256 indexed sessionId, address winner);

    /// @dev Custom errors
    error OnlyGameHub();
    error NoActiveSession();
    error InvalidSession(uint256 sessionId);
    error SessionAlreadyActive(uint256 sessionId);

    /// @dev Modifiers
    modifier onlyGameHub() {
        if (msg.sender != gameHub) {
            revert OnlyGameHub();
        }
        _;
    }

    modifier validSession(uint256 sessionId) {
        if (!activeGameSessions[sessionId]) {
            revert InvalidSession(sessionId);
        }
        _;
    }

    /**
     * @dev Constructor
     * @param _gameHub Address of the GameHub contract
     */
    constructor(address _gameHub) {
        require(_gameHub != address(0), "BaseGame: Invalid GameHub address");
        gameHub = _gameHub;
    }

    /**
     * @notice Creates a new game session through the GameHub
     * @dev This function handles the complete session creation process, including validation,
     *      GameHub integration, and session tracking. Game contracts should call this function
     *      when they want to start a new game with specified players.
     *
     * Requirements:
     * - Player count must be within the game's supported range (minPlayers <= count <= maxPlayers)
     * - All players must not be locked in other active sessions
     * - The calling game contract must be whitelisted with the GameHub
     * - TTL must be within the allowed range (MIN_TTL <= ttl <= MAX_TTL)
     *
     * @param players Array of player addresses who will participate in the game session
     * @param ttl Time-to-live for the session in seconds (how long the session remains valid)
     * @return sessionId The unique identifier for the created session
     *
     * @dev Emits GameSessionRequested event
     * @dev Calls internal _onGameSessionStarted hook for custom game initialization
     */
    function requestGameSession(
        address[] calldata players,
        uint256 ttl
    ) external virtual returns (uint256 sessionId) {
        // Validate player count
        require(
            this.supportsPlayerCount(players.length),
            "BaseGame: Invalid player count"
        );

        // Call GameHub to create session
        sessionId = ITaikoGameHubIntegration(gameHub).requestGameSession(
            players,
            ttl
        );

        // Track the session
        activeGameSessions[sessionId] = true;
        currentSessionId = sessionId;

        emit GameSessionRequested(sessionId, players);

        // Allow derived contracts to handle session start
        _onGameSessionStarted(sessionId, players);

        return sessionId;
    }

    /**
     * @notice Ends a game session with multiple winners in ranking order
     * @dev This function should be called when a game has concluded with one or more winners.
     *      Winners are ranked by their position in the array (index 0 = 1st place, index 1 = 2nd place, etc.).
     *      This automatically handles session cleanup and player unlocking through the GameHub.
     *
     * Requirements:
     * - Session must be active and valid
     * - Winners array must contain at least one winner
     * - All winner addresses must be participants in the session
     *
     * @param sessionId The unique identifier of the session to end
     * @param winners Array of winner addresses in ranking order (first element is 1st place winner)
     *
     * @dev Emits GameSessionEnded event with the first place winner
     * @dev Calls internal _onGameSessionEnded hook for custom cleanup logic
     * @dev Automatically unlocks all players and marks session as completed
     */
    function endGameWithWinners(
        uint256 sessionId,
        address[] calldata winners
    ) external virtual validSession(sessionId) {
        require(winners.length > 0, "BaseGame: Must have at least one winner");

        ITaikoGameHubIntegration(gameHub).endGameWithWinners(sessionId, winners);

        // Clean up session state
        activeGameSessions[sessionId] = false;
        if (currentSessionId == sessionId) {
            currentSessionId = 0;
        }

        emit GameSessionEnded(sessionId, winners[0]); // Emit first place winner

        // Allow derived contracts to handle session end
        _onGameSessionEnded(sessionId, winners);
    }

    /**
     * @notice Ends a game session with a single winner
     * @dev Convenience function for games with only one winner. This is equivalent to calling
     *      endGameWithWinners() with a single-element array.
     *
     * Requirements:
     * - Session must be active and valid
     * - Winner address must not be zero address
     * - Winner must be a participant in the session
     *
     * @param sessionId The unique identifier of the session to end
     * @param winner The address of the single winner
     *
     * @dev Emits GameSessionEnded event
     * @dev Calls internal _onGameSessionEnded hook for custom cleanup logic
     */
    function endGameWithWinner(
        uint256 sessionId,
        address winner
    ) external virtual validSession(sessionId) {
        require(winner != address(0), "BaseGame: Invalid winner address");

        address[] memory winners = new address[](1);
        winners[0] = winner;

        ITaikoGameHubIntegration(gameHub).endGameWithWinners(sessionId, winners);

        // Clean up session state
        activeGameSessions[sessionId] = false;
        if (currentSessionId == sessionId) {
            currentSessionId = 0;
        }

        emit GameSessionEnded(sessionId, winner);

        // Allow derived contracts to handle session end
        _onGameSessionEnded(sessionId, winners);
    }

    /**
     * @notice Ends a game session with no winners (draw)
     * @dev This function should be called when a game concludes with no clear winner.
     *      This could be due to a tie, timeout, or other game-specific draw conditions.
     *
     * Requirements:
     * - Session must be active and valid
     *
     * @param sessionId The unique identifier of the session to end
     *
     * @dev Emits GameSessionEnded event with address(0) as winner (indicating draw)
     * @dev Calls internal _onGameSessionEnded hook with empty winners array
     * @dev Automatically unlocks all players and marks session as completed
     */
    function endGameWithDraw(
        uint256 sessionId
    ) external virtual validSession(sessionId) {
        ITaikoGameHubIntegration(gameHub).endGameWithDraw(sessionId);

        // Clean up session state
        activeGameSessions[sessionId] = false;
        if (currentSessionId == sessionId) {
            currentSessionId = 0;
        }

        emit GameSessionEnded(sessionId, address(0));

        // Allow derived contracts to handle session end
        address[] memory emptyWinners = new address[](0);
        _onGameSessionEnded(sessionId, emptyWinners);
    }

    /**
     * @dev Check if there's an active game session
     * @return active True if there's an active session
     */
    function hasActiveSession() external view returns (bool active) {
        return currentSessionId != 0 && activeGameSessions[currentSessionId];
    }

    /**
     * @dev Hook called when a game session is started
     * @param sessionId The ID of the started session
     * @param players Array of player addresses
     */
    function _onGameSessionStarted(
        uint256 sessionId,
        address[] calldata players
    ) internal virtual {
        // Override in derived contracts if needed
    }

    /**
     * @dev Hook called when a game session is ended
     * @param sessionId The ID of the ended session
     * @param winners Array of winners in ranking order (index 0 = 1st place)
     */
    function _onGameSessionEnded(
        uint256 sessionId,
        address[] memory winners
    ) internal virtual {
        // Override in derived contracts if needed
    }

    /**
     * @dev Abstract functions that must be implemented by derived contracts
     */
    function gameName() external view virtual override returns (string memory);

    function gameVersion()
        external
        view
        virtual
        override
        returns (string memory);

    function minPlayers() external view virtual override returns (uint256);

    function maxPlayers() external view virtual override returns (uint256);

    /**
     * @dev Default implementation for player count validation
     * @param playerCount The number of players
     * @return supported True if the player count is supported
     */
    function supportsPlayerCount(
        uint256 playerCount
    ) external view virtual override returns (bool supported) {
        return
            playerCount >= this.minPlayers() &&
            playerCount <= this.maxPlayers();
    }
}
