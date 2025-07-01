// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ITaikoGameHub.sol";

/**
 * @title TaikoGameHub
 * @author Taiko Labs
 * @notice Central game contract that serves as an interface for third-party games to integrate into the Taiko gaming ecosystem
 * @dev This contract implements a session-based game management system with the following features:
 *      - Whitelisted game contracts can create game sessions
 *      - Players are locked during active sessions to prevent double-participation
 *      - Sessions have configurable time-to-live (TTL) limits
 *      - Support for ranked winners (1st place, 2nd place, etc.) and draws
 *      - Proxy pattern implementation for upgradeability
 *      - Comprehensive access controls and security measures
 *
 * @custom:security-contact security@taiko.xyz
 * @custom:upgradeable This contract is designed to be deployed behind a proxy for upgradeability
 */
contract TaikoGameHub is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ITaikoGameHubIntegration
{
    /// @notice Version of the contract for tracking deployments
    string public constant VERSION = "1.0.0";

    /// @notice Maximum number of players allowed in a single game session
    uint256 public constant MAX_PLAYERS = 100;

    /// @notice Maximum time-to-live for a game session (24 hours)
    uint256 public constant MAX_TTL = 24 hours;

    /// @notice Minimum time-to-live for a game session (5 minutes)
    uint256 public constant MIN_TTL = 5 minutes;

    /**
     * @notice Structure representing a game session
     * @dev This struct contains all the essential information for managing a game session
     * @param sessionId Unique identifier for the session
     * @param players Array of all players participating in the session
     * @param winners Array of winners in ranking order (index 0 = 1st place, index 1 = 2nd place, etc.)
     * @param game Address of the game contract that created this session
     * @param ttl Time-to-live duration in seconds from session start
     * @param startTime Timestamp when the session was created
     * @param ended Whether the session has been completed
     * @param isDrawn Whether the session ended in a draw (no winners)
     */
    struct GameSession {
        uint256 sessionId;
        address[] players;
        address[] winners;
        address game;
        uint256 ttl;
        uint256 startTime;
        bool ended;
        bool isDrawn;
    }

    /// @notice Latest session ID counter, incremented for each new session
    uint256 public latestSessionId;

    /// @notice Mapping from game contract address to whitelist status
    /// @dev Only whitelisted games can create sessions
    mapping(address => bool) public isWhitelisted;

    /// @notice Mapping from session ID to complete game session data
    /// @dev Contains all session information including players, winners, and metadata
    mapping(uint256 => GameSession) public gameSessions;

    /// @notice Mapping from session ID to winners array for easy access
    /// @dev Redundant storage for gas-efficient winner lookups
    mapping(uint256 => address[]) public sessionWinners;

    /// @notice Mapping to track if a player is currently in an active game
    /// @dev Prevents players from joining multiple games simultaneously
    mapping(address => bool) public isInGame;

    /// @notice Mapping from player address to their current session ID
    /// @dev Zero means player is not in any session
    mapping(address => uint256) public playerCurrentSession;

    /**
     * @notice Emitted when a game contract is added to the whitelist
     * @param game Address of the game contract that was whitelisted
     */
    event GameWhitelisted(address indexed game);

    /**
     * @notice Emitted when a game contract is removed from the whitelist
     * @param game Address of the game contract that was removed
     */
    event GameRemovedFromWhitelist(address indexed game);

    /**
     * @notice Emitted when a new game session is started
     * @param sessionId Unique identifier for the session
     * @param game Address of the game contract that created the session
     * @param participants Array of all players in the session
     */
    event GameStarted(
        uint256 indexed sessionId,
        address indexed game,
        address[] participants
    );

    /**
     * @notice Emitted when a game session ends
     * @param sessionId Unique identifier for the session
     * @param game Address of the game contract
     * @param winners Array of winners in ranking order (index 0 = 1st place)
     * @param participants Array of all players who participated
     * @param isDrawn Whether the game ended in a draw
     */
    event GameEnded(
        uint256 indexed sessionId,
        address indexed game,
        address[] winners,
        address[] participants,
        bool isDrawn
    );

    /**
     * @notice Thrown when a non-whitelisted game tries to create a session
     * @param game Address of the unauthorized game contract
     */
    error GameNotWhitelisted(address game);

    /**
     * @notice Thrown when trying to add a player who is already in an active game
     * @param player Address of the player already in a game
     */
    error PlayerAlreadyInGame(address player);

    /**
     * @notice Thrown when referencing a player not in any game
     * @param player Address of the player not in a game
     */
    error PlayerNotInGame(address player);

    /**
     * @notice Thrown when the number of players is invalid
     * @param count The invalid player count provided
     */
    error InvalidPlayerCount(uint256 count);

    /**
     * @notice Thrown when the TTL is outside allowed bounds
     * @param ttl The invalid TTL value provided
     */
    error InvalidTTL(uint256 ttl);

    /**
     * @notice Thrown when referencing a non-existent session
     * @param sessionId The invalid session ID
     */
    error GameSessionNotFound(uint256 sessionId);

    /**
     * @notice Thrown when trying to operate on an already ended session
     * @param sessionId The ID of the already ended session
     */
    error GameSessionAlreadyEnded(uint256 sessionId);

    /**
     * @notice Thrown when trying to operate on an expired session
     * @param sessionId The ID of the expired session
     */
    error GameSessionExpired(uint256 sessionId);

    /**
     * @notice Thrown when a game tries to end a session it didn't create
     * @param sessionId The session ID
     * @param game The unauthorized game contract address
     */
    error UnauthorizedGameAccess(uint256 sessionId, address game);

    /**
     * @notice Thrown when trying to create a session with no players
     */
    error EmptyPlayersArray();

    /**
     * @notice Thrown when the same player appears multiple times in a session
     * @param player Address of the duplicate player
     */
    error DuplicatePlayer(address player);

    /**
     * @notice Modifier to restrict access to whitelisted games only
     * @dev Reverts with GameNotWhitelisted if caller is not whitelisted
     */
    modifier onlyWhitelisted() {
        if (!isWhitelisted[msg.sender]) {
            revert GameNotWhitelisted(msg.sender);
        }
        _;
    }

    modifier validSessionId(uint256 sessionId) {
        if (sessionId == 0 || sessionId > latestSessionId) {
            revert GameSessionNotFound(sessionId);
        }
        _;
    }

    modifier sessionNotEnded(uint256 sessionId) {
        if (gameSessions[sessionId].ended) {
            revert GameSessionAlreadyEnded(sessionId);
        }
        _;
    }

    modifier sessionNotExpired(uint256 sessionId) {
        GameSession storage session = gameSessions[sessionId];
        if (block.timestamp > session.startTime + session.ttl) {
            revert GameSessionExpired(sessionId);
        }
        _;
    }

    modifier onlyGameForSession(uint256 sessionId) {
        if (gameSessions[sessionId].game != msg.sender) {
            revert UnauthorizedGameAccess(sessionId, msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param owner The owner of the contract
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Pausable_init();
        __ReentrancyGuard_init();

        latestSessionId = 0;
    }

    /**
     * @dev Add a game to the whitelist
     * @param game The address of the game contract
     */
    function whitelist(address game) external onlyOwner {
        require(game != address(0), "GameHub: Invalid game address");
        isWhitelisted[game] = true;
        emit GameWhitelisted(game);
    }

    /**
     * @dev Remove a game from the whitelist
     * @param game The address of the game contract
     */
    function removeFromWhitelist(address game) external onlyOwner {
        isWhitelisted[game] = false;
        emit GameRemovedFromWhitelist(game);
    }

    /**
     * @notice Creates a new game session with specified players and time-to-live
     * @dev This is the primary function for whitelisted game contracts to create new sessions.
     *      It performs comprehensive validation, locks players, and initializes the session state.
     *
     * Process Flow:
     * 1. Validates caller is whitelisted game contract
     * 2. Validates player count and TTL are within limits
     * 3. Ensures no players are already locked in other sessions
     * 4. Checks for duplicate players in the array
     * 5. Creates session and locks all players
     * 6. Emits GameStarted event for tracking
     *
     * Requirements:
     * - Caller must be a whitelisted game contract
     * - Contract must not be paused
     * - Players array must not be empty
     * - Players array must not exceed MAX_PLAYERS (100)
     * - TTL must be between MIN_TTL (5 minutes) and MAX_TTL (24 hours)
     * - No player can be already locked in another active session
     * - No duplicate players in the array
     *
     * @param players Array of player addresses who will participate in the game session
     * @param ttl Time-to-live for the session in seconds (determines when session expires)
     * @return sessionId Unique identifier for the created session
     *
     * @dev Emits GameStarted(sessionId, gameContract, players) event
     * @dev Reverts with GameNotWhitelisted if caller is not whitelisted
     * @dev Reverts with EmptyPlayersArray if players array is empty
     * @dev Reverts with InvalidPlayerCount if too many players
     * @dev Reverts with InvalidTTL if TTL is outside allowed range
     * @dev Reverts with PlayerAlreadyInGame if any player is already locked
     * @dev Reverts with DuplicatePlayer if duplicate players found
     */
    function requestGameSession(
        address[] calldata players,
        uint256 ttl
    )
        external
        override
        onlyWhitelisted
        whenNotPaused
        nonReentrant
        returns (uint256 sessionId)
    {
        if (players.length == 0) {
            revert EmptyPlayersArray();
        }

        if (players.length > MAX_PLAYERS) {
            revert InvalidPlayerCount(players.length);
        }

        if (ttl < MIN_TTL || ttl > MAX_TTL) {
            revert InvalidTTL(ttl);
        }

        // Check that all players are not currently in a game and no duplicates
        for (uint256 i = 0; i < players.length; i++) {
            if (isInGame[players[i]]) {
                revert PlayerAlreadyInGame(players[i]);
            }

            // Check for duplicates
            for (uint256 j = i + 1; j < players.length; j++) {
                if (players[i] == players[j]) {
                    revert DuplicatePlayer(players[i]);
                }
            }
        }

        sessionId = _createNewSession(players, ttl, msg.sender);
        emit GameStarted(sessionId, msg.sender, players);
        return sessionId;
    }

    /**
     * @notice Ends a game session with multiple winners in ranking order
     * @dev This function allows game contracts to conclude sessions with ranked winners.
     *      Winners are ordered by rank, with index 0 being 1st place, index 1 being 2nd place, etc.
     *      This function handles all cleanup including player unlocking and session state updates.
     *
     * Process Flow:
     * 1. Validates session exists and is active
     * 2. Ensures session hasn't expired
     * 3. Confirms caller is the game contract that created the session
     * 4. Validates all winners are actual session participants
     * 5. Updates session state with winners and end time
     * 6. Unlocks all players from the session
     * 7. Emits GameEnded event with complete session information
     *
     * Requirements:
     * - Session must exist and be active (not already ended)
     * - Session must not have expired based on TTL
     * - Caller must be the original game contract that created the session
     * - Winners array must not be empty
     * - All winner addresses must be participants in the session
     * - Contract must not be paused
     *
     * @param sessionId Unique identifier of the session to end
     * @param winners Array of winner addresses in ranking order (first element = 1st place winner)
     *
     * @dev Emits GameEnded(sessionId, gameContract, winners, allPlayers, false) event
     * @dev Reverts with GameSessionNotFound if session doesn't exist
     * @dev Reverts with GameSessionAlreadyEnded if session was already ended
     * @dev Reverts with GameSessionExpired if session TTL has passed
     * @dev Reverts with UnauthorizedGameAccess if caller isn't the session's game contract
     * @dev Reverts with require message if winners array is empty or contains non-participants
     */
    function endGameWithWinners(
        uint256 sessionId,
        address[] calldata winners
    )
        external
        override
        validSessionId(sessionId)
        sessionNotEnded(sessionId)
        sessionNotExpired(sessionId)
        onlyGameForSession(sessionId)
        whenNotPaused
        nonReentrant
    {
        require(winners.length > 0, "GameHub: Must have at least one winner");

        // Validate all winners are players in the session
        GameSession storage session = gameSessions[sessionId];
        for (uint256 i = 0; i < winners.length; i++) {
            bool isPlayer = false;
            for (uint256 j = 0; j < session.players.length; j++) {
                if (session.players[j] == winners[i]) {
                    isPlayer = true;
                    break;
                }
            }
            require(
                isPlayer,
                "GameHub: Winner must be a player in the session"
            );
        }

        _endGameSession(sessionId, winners, false);
        emit GameEnded(
            sessionId,
            session.game,
            winners,
            session.players,
            false
        );
    }

    /**
     * @dev End a game session with a single winner (interface implementation)
     * @param sessionId The ID of the session to end
     * @param winner The address of the winner
     */
    function endGameWithWinner(
        uint256 sessionId,
        address winner
    )
        external
        override
        validSessionId(sessionId)
        sessionNotEnded(sessionId)
        sessionNotExpired(sessionId)
        onlyGameForSession(sessionId)
        whenNotPaused
        nonReentrant
    {
        // Convert single winner to winners array
        address[] memory winners = new address[](1);
        winners[0] = winner;

        GameSession storage session = gameSessions[sessionId];
        _endGameSession(sessionId, winners, false);
        emit GameEnded(
            sessionId,
            session.game,
            winners,
            session.players,
            false
        );
    }

    /**
     * @dev End a game session with a draw (interface implementation)
     * @param sessionId The ID of the session to end
     */
    function endGameWithDraw(
        uint256 sessionId
    )
        external
        override
        validSessionId(sessionId)
        sessionNotEnded(sessionId)
        sessionNotExpired(sessionId)
        onlyGameForSession(sessionId)
        whenNotPaused
        nonReentrant
    {
        GameSession storage session = gameSessions[sessionId];
        address[] memory emptyWinners = new address[](0);
        _endGameSession(sessionId, emptyWinners, true);
        emit GameEnded(
            sessionId,
            session.game,
            emptyWinners,
            session.players,
            true
        );
    }

    /**
     * @dev Start a new game session
     * @param players Array of player addresses
     * @param ttl Time to live for the session in seconds
     * @return sessionId The ID of the created session
     */
    function startGameSession(
        address[] calldata players,
        uint256 ttl
    )
        external
        onlyWhitelisted
        whenNotPaused
        nonReentrant
        returns (uint256 sessionId)
    {
        if (players.length == 0) {
            revert EmptyPlayersArray();
        }

        if (players.length > MAX_PLAYERS) {
            revert InvalidPlayerCount(players.length);
        }

        if (ttl < MIN_TTL || ttl > MAX_TTL) {
            revert InvalidTTL(ttl);
        }

        // Check that all players are not currently in a game and no duplicates
        for (uint256 i = 0; i < players.length; i++) {
            if (isInGame[players[i]]) {
                revert PlayerAlreadyInGame(players[i]);
            }

            // Check for duplicates
            for (uint256 j = i + 1; j < players.length; j++) {
                if (players[i] == players[j]) {
                    revert DuplicatePlayer(players[i]);
                }
            }
        }

        sessionId = _createNewSession(players, ttl, msg.sender);
        emit GameStarted(sessionId, msg.sender, players);
    }

    /**
     * @dev Force end an expired game session
     * @param sessionId The ID of the session to force end
     */
    function forceEndExpiredSession(
        uint256 sessionId
    )
        external
        validSessionId(sessionId)
        sessionNotEnded(sessionId)
        whenNotPaused
        nonReentrant
    {
        GameSession storage session = gameSessions[sessionId];

        // Check if session is actually expired
        require(
            block.timestamp > session.startTime + session.ttl,
            "GameHub: Session not expired"
        );

        address[] memory emptyWinners = new address[](0);
        _endGameSession(sessionId, emptyWinners, true);
        emit GameEnded(
            sessionId,
            session.game,
            emptyWinners,
            session.players,
            true
        );
    }

    /**
     * @dev Get game session details
     * @param sessionId The ID of the session
     * @return session The game session struct
     */
    function getGameSession(
        uint256 sessionId
    )
        external
        view
        validSessionId(sessionId)
        returns (GameSession memory session)
    {
        return gameSessions[sessionId];
    }

    /**
     * @dev Get players for a specific session
     * @param sessionId The ID of the session
     * @return players Array of player addresses
     */
    function getSessionPlayers(
        uint256 sessionId
    )
        external
        view
        override
        validSessionId(sessionId)
        returns (address[] memory players)
    {
        return gameSessions[sessionId].players;
    }

    /**
     * @dev Get winners for a specific session in ranking order
     * @param sessionId The ID of the session
     * @return winners Array of winners (index 0 = 1st place, index 1 = 2nd place, etc.)
     */
    function getSessionWinners(
        uint256 sessionId
    )
        external
        view
        override
        validSessionId(sessionId)
        returns (address[] memory winners)
    {
        return gameSessions[sessionId].winners;
    }

    /**
     * @dev Get the first place winner for a session (convenience function)
     * @param sessionId The ID of the session
     * @return winner Address of first place winner (address(0) if no winners or draw)
     */
    function getSessionWinner(
        uint256 sessionId
    ) external view validSessionId(sessionId) returns (address winner) {
        GameSession memory session = gameSessions[sessionId];
        if (session.winners.length > 0 && !session.isDrawn) {
            return session.winners[0]; // First place winner
        }
        return address(0);
    }

    /**
     * @dev Check if a session is active (not ended and not expired)
     * @param sessionId The ID of the session
     * @return active True if session is active
     */
    function isSessionActive(
        uint256 sessionId
    ) external view validSessionId(sessionId) returns (bool active) {
        GameSession storage session = gameSessions[sessionId];
        return
            !session.ended &&
            block.timestamp <= session.startTime + session.ttl;
    }

    /**
     * @dev Pause the contract (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Internal function to create a new session
     * @param players Array of player addresses
     * @param ttl Time to live for the session
     * @param game Address of the game contract
     * @return sessionId The ID of the created session
     */
    function _createNewSession(
        address[] calldata players,
        uint256 ttl,
        address game
    ) internal returns (uint256 sessionId) {
        sessionId = ++latestSessionId;

        // Lock all players
        for (uint256 i = 0; i < players.length; i++) {
            isInGame[players[i]] = true;
            playerCurrentSession[players[i]] = sessionId;
        }

        // Create and store session using your struct design
        GameSession storage session = gameSessions[sessionId];
        session.sessionId = sessionId;
        session.players = players;
        session.winners = new address[](0); // Empty winners array initially
        session.game = game;
        session.ttl = ttl;
        session.startTime = block.timestamp;
        session.ended = false;
        session.isDrawn = false;

        return sessionId;
    }

    /**
     * @dev Internal function to end a game session with ranked winners
     * @param sessionId The ID of the session to end
     * @param winners Array of winners in ranking order (index 0 = 1st place)
     * @param isDrawn Whether the game ended in a draw
     */
    function _endGameSession(
        uint256 sessionId,
        address[] memory winners,
        bool isDrawn
    ) internal {
        GameSession storage session = gameSessions[sessionId];

        // Unlock all players
        for (uint256 i = 0; i < session.players.length; i++) {
            isInGame[session.players[i]] = false;
            playerCurrentSession[session.players[i]] = 0;
        }

        // Update session with ranked winners
        session.winners = winners;
        session.ended = true;
        session.isDrawn = isDrawn;

        // Store winners in separate mapping for easy access
        sessionWinners[sessionId] = winners;
    }

    /**
     * @dev Get the version of the contract
     * @return version The version string
     */
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
