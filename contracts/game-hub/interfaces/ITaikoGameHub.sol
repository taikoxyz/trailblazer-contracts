// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITaikoGameHubIntegration
 * @author Taiko Labs
 * @notice Interface that third-party game contracts must implement to integrate with TaikoGameHub
 * @dev This interface provides the core functionality for game session management including:
 *      - Creating game sessions with multiple players
 *      - Ending sessions with ranked winners or draws
 *      - Querying session data
 *
 * @custom:example
 * ```solidity
 * contract MyGame is BaseGame {
 *     function startMyGame(address[] calldata players) external {
 *         uint256 sessionId = requestGameSession(players, 1 hours);
 *         // Game logic here...
 *     }
 *
 *     function endMyGame(uint256 sessionId, address winner) external {
 *         endGameWithWinner(sessionId, winner);
 *     }
 * }
 * ```
 */
interface ITaikoGameHubIntegration {
    /**
     * @notice Request creation of a new game session
     * @dev Can only be called by whitelisted game contracts
     * @param players Array of player addresses to include in the session
     * @param ttl Time-to-live for the session in seconds (must be between MIN_TTL and MAX_TTL)
     * @return sessionId The unique identifier for the created session
     *
     * @custom:requirements
     * - Caller must be whitelisted
     * - Players array must not be empty and not exceed MAX_PLAYERS
     * - No player can be in another active session
     * - No duplicate players allowed
     * - TTL must be within allowed bounds (5 minutes to 24 hours)
     *
     * @custom:emits GameStarted
     */
    function requestGameSession(
        address[] calldata players,
        uint256 ttl
    ) external returns (uint256 sessionId);

    /**
     * @notice End a game session with multiple ranked winners
     * @dev Winners array represents ranking order: index 0 = 1st place, index 1 = 2nd place, etc.
     * @param sessionId The ID of the session to end
     * @param winners Array of winners in ranking order
     *
     * @custom:requirements
     * - Only the game that created the session can end it
     * - Session must not be already ended
     * - Session must not be expired
     * - At least one winner must be provided
     * - All winners must be players in the session
     *
     * @custom:emits GameEnded
     */
    function endGameWithWinners(
        uint256 sessionId,
        address[] calldata winners
    ) external;

    /**
     * @notice End a game session with a single winner (convenience function)
     * @dev Equivalent to calling endGameWithWinners with a single-element array
     * @param sessionId The ID of the session to end
     * @param winner The address of the winner
     *
     * @custom:requirements Same as endGameWithWinners
     * @custom:emits GameEnded
     */
    function endGameWithWinner(uint256 sessionId, address winner) external;

    /**
     * @notice End a game session with no winners (draw)
     * @dev Marks the session as ended with isDrawn = true
     * @param sessionId The ID of the session to end
     *
     * @custom:requirements
     * - Only the game that created the session can end it
     * - Session must not be already ended
     * - Session must not be expired
     *
     * @custom:emits GameEnded
     */
    function endGameWithDraw(uint256 sessionId) external;

    /**
     * @notice Get all players for a specific session
     * @param sessionId The ID of the session
     * @return players Array of player addresses in the session
     */
    function getSessionPlayers(
        uint256 sessionId
    ) external view returns (address[] memory players);

    /**
     * @notice Get winners for a specific session in ranking order
     * @param sessionId The ID of the session
     * @return winners Array of winners where index represents rank (0 = 1st place, 1 = 2nd place, etc.)
     * @dev Returns empty array for draw games or sessions that haven't ended
     */
    function getSessionWinners(
        uint256 sessionId
    ) external view returns (address[] memory winners);
}

/**
 * @title IThirdPartyGame
 * @author Taiko Labs
 * @notice Optional interface that third-party games can implement for enhanced integration
 * @dev Provides metadata and validation functions for better GameHub integration
 *
 * @custom:example
 * ```solidity
 * contract RockPaperScissors is BaseGame, IThirdPartyGame {
 *     function gameName() external pure returns (string memory) {
 *         return "Rock Paper Scissors";
 *     }
 *
 *     function minPlayers() external pure returns (uint256) {
 *         return 2;
 *     }
 *
 *     function maxPlayers() external pure returns (uint256) {
 *         return 2;
 *     }
 * }
 * ```
 */
interface IThirdPartyGame {
    /**
     * @notice Get the human-readable name of the game
     * @return name The game's display name (e.g., "Rock Paper Scissors")
     */
    function gameName() external view returns (string memory name);

    /**
     * @notice Get the version of the game contract
     * @return version The version string (e.g., "1.0.0")
     */
    function gameVersion() external view returns (string memory version);

    /**
     * @notice Get the minimum number of players required for this game
     * @return minPlayers The minimum player count (must be >= 1)
     */
    function minPlayers() external view returns (uint256 minPlayers);

    /**
     * @notice Get the maximum number of players supported by this game
     * @return maxPlayers The maximum player count (must be <= TaikoGameHub.MAX_PLAYERS)
     */
    function maxPlayers() external view returns (uint256 maxPlayers);

    /**
     * @notice Check if the game supports a specific number of players
     * @param playerCount The number of players to validate
     * @return supported True if the player count is supported, false otherwise
     * @dev Default implementation should check: playerCount >= minPlayers() && playerCount <= maxPlayers()
     */
    function supportsPlayerCount(
        uint256 playerCount
    ) external view returns (bool supported);
}
