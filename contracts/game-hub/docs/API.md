# TaikoGameHub API Documentation

## Table of Contents

1. [TaikoGameHub Contract](#gamehub-contract)
2. [BaseGame Contract](#basegame-contract)
3. [ITaikoGameHub Interfaces](#igamehub-interfaces)
4. [ExampleGame Contract](#examplegame-contract)
5. [Events Reference](#events-reference)
6. [Error Reference](#error-reference)
7. [Integration Guide](#integration-guide)

## TaikoGameHub Contract

The main contract that manages all game sessions and player interactions.

### Core Functions

#### Session Management

##### `requestGameSession(address[] calldata players, uint256 ttl) → uint256 sessionId`

Creates a new game session with specified players and time-to-live.

**Parameters:**
- `players`: Array of player addresses (2-100 players)
- `ttl`: Session timeout in seconds (5 minutes - 24 hours)

**Returns:**
- `sessionId`: Unique identifier for the created session

**Requirements:**
- Caller must be whitelisted game contract
- All players must not be locked in other sessions
- Player count must be within limits
- TTL must be within allowed range

**Events Emitted:**
- `SessionStarted(sessionId, game, players, ttl)`

---

##### `endGameWithWinners(uint256 sessionId, address[] calldata winners)`

Ends a session with ranked winners.

**Parameters:**
- `sessionId`: The session to end
- `winners`: Array of winners in ranking order (index 0 = 1st place)

**Requirements:**
- Caller must be the game that created the session
- Session must be active
- Winners must be session participants

**Events Emitted:**
- `SessionEnded(sessionId, winners, false)`

---

##### `endGameWithDraw(uint256 sessionId)`

Ends a session with no winners (draw).

**Parameters:**
- `sessionId`: The session to end

**Requirements:**
- Caller must be the game that created the session
- Session must be active

**Events Emitted:**
- `SessionEnded(sessionId, [], true)`

---

##### `forceEndSession(uint256 sessionId)`

Forcibly ends a session (admin only, for expired/stuck sessions).

**Parameters:**
- `sessionId`: The session to force end

**Requirements:**
- Caller must be contract owner
- Session must exist

**Events Emitted:**
- `SessionForceEnded(sessionId, reason)`

---

#### Query Functions

##### `getSession(uint256 sessionId) → GameSession memory`

Retrieves complete session information.

**Returns:**
- `GameSession`: Struct containing all session data

---

##### `isSessionActive(uint256 sessionId) → bool`

Checks if a session is currently active.

**Returns:**
- `bool`: True if session is active

---

##### `isPlayerLocked(address player) → bool`

Checks if a player is locked in an active session.

**Returns:**
- `bool`: True if player is locked

---

##### `getPlayerCurrentSession(address player) → uint256`

Gets the current session ID for a locked player.

**Returns:**
- `uint256`: Session ID (0 if not locked)

---

#### Administrative Functions

##### `addToWhitelist(address game)`

Adds a game contract to the whitelist (owner only).

##### `removeFromWhitelist(address game)`

Removes a game contract from the whitelist (owner only).

##### `isWhitelisted(address game) → bool`

Checks if a game contract is whitelisted.

##### `pause()` / `unpause()`

Emergency pause/unpause functions (owner only).

---

## BaseGame Contract

Abstract base contract for third-party games to inherit from.

### Protected Functions (for game contracts)

#### `requestGameSession(address[] calldata players, uint256 ttl) → uint256`

Request a new session from TaikoGameHub. Only callable by the game contract itself.

#### `endGameWithWinners(uint256 sessionId, address[] calldata winners)`

End session with ranked winners.

#### `endGameWithWinner(uint256 sessionId, address winner)`

End session with single winner (convenience function).

#### `endGameWithDraw(uint256 sessionId)`

End session as draw.

### Virtual Functions (override in game contracts)

#### `_onGameSessionStarted(uint256 sessionId, address[] calldata players)`

Hook called when session starts. Override to initialize game state.

#### `_onGameSessionEnded(uint256 sessionId, address[] memory winners)`

Hook called when session ends. Override to clean up and handle results.

### Abstract Functions (must implement)

#### `gameName() → string memory`

Return the name of your game.

#### `gameVersion() → string memory`

Return the version of your game.

#### `minPlayers() → uint256`

Return minimum number of players.

#### `maxPlayers() → uint256`

Return maximum number of players.

#### `supportsPlayerCount(uint256 playerCount) → bool`

Check if a player count is supported (default implementation provided).

---

## ITaikoGameHub Interfaces

### ITaikoGameHubIntegration

Interface for game contracts to interact with TaikoGameHub.

```solidity
interface ITaikoGameHubIntegration {
    function requestGameSession(address[] calldata players, uint256 ttl) external returns (uint256);
    function endGameWithWinners(uint256 sessionId, address[] calldata winners) external;
    function endGameWithDraw(uint256 sessionId) external;
    function getSessionPlayers(uint256 sessionId) external view returns (address[] memory);
}
```

### IThirdPartyGame

Interface that game contracts must implement.

```solidity
interface IThirdPartyGame {
    function gameName() external view returns (string memory);
    function gameVersion() external view returns (string memory);
    function minPlayers() external view returns (uint256);
    function maxPlayers() external view returns (uint256);
    function supportsPlayerCount(uint256 playerCount) external view returns (bool);
}
```

---

## ExampleGame Contract

Complete Rock Paper Scissors implementation demonstrating best practices.

### Public Functions

#### `startGame(address[] calldata players) → uint256`

Start a new Rock Paper Scissors game (owner only).

#### `submitMove(uint256 sessionId, uint8 move)`

Submit a move for the game:
- 1 = Rock
- 2 = Paper
- 3 = Scissors

#### `getPlayerMove(uint256 sessionId, address player) → Move`

Get a player's move after game completion.

### Game Rules

- Rock beats Scissors
- Paper beats Rock
- Scissors beats Paper
- Same moves = Draw
- Players have 30 minutes to submit moves
- Game auto-resolves when all moves submitted

---

## Events Reference

### TaikoGameHub Events

```solidity
event SessionStarted(uint256 indexed sessionId, address indexed game, address[] players, uint256 ttl);
event SessionEnded(uint256 indexed sessionId, address[] winners, bool isDraw);
event GameWhitelisted(address indexed game);
event GameRemovedFromWhitelist(address indexed game);
event SessionForceEnded(uint256 indexed sessionId, string reason);
```

### BaseGame Events

```solidity
event GameSessionRequested(uint256 indexed sessionId, address[] players);
event GameSessionEnded(uint256 indexed sessionId, address winner);
```

### ExampleGame Events

```solidity
event MoveSubmitted(uint256 indexed sessionId, address indexed player);
event GameComplete(uint256 indexed sessionId, address winner);
```

---

## Error Reference

### TaikoGameHub Errors

```solidity
error PlayerAlreadyLocked(address player);
error GameNotWhitelisted(address game);
error InvalidTTL(uint256 ttl);
error SessionNotFound(uint256 sessionId);
error SessionNotActive(uint256 sessionId);
error InvalidWinners(address[] winners);
error TooManyPlayers(uint256 count);
error TooFewPlayers(uint256 count);
error WinnerNotInSession(address winner);
```

### BaseGame Errors

```solidity
error OnlyTaikoGameHub();
error NoActiveSession();
error InvalidSession(uint256 sessionId);
error SessionAlreadyActive(uint256 sessionId);
```

### ExampleGame Errors

```solidity
error MoveAlreadySubmitted();
error InvalidMove();
error GameNotInRevealPhase();
error RevealDeadlinePassed();
```

---

## Integration Guide

### Quick Start for Game Developers

1. **Inherit from BaseGame**
```solidity
contract MyGame is BaseGame {
    constructor(address _gameHub) BaseGame(_gameHub) {}
}
```

2. **Implement required functions**
```solidity
function gameName() external pure override returns (string memory) {
    return "My Game";
}

function gameVersion() external pure override returns (string memory) {
    return "1.0.0";
}

function minPlayers() external pure override returns (uint256) {
    return 2;
}

function maxPlayers() external pure override returns (uint256) {
    return 8;
}
```

3. **Add game logic**
```solidity
function playGame(address[] calldata players) external returns (uint256 sessionId) {
    sessionId = this.requestGameSession(players, 1 hours);
    
    // Your game logic here
    
    // End with winner or draw
    if (hasWinner) {
        address[] memory winners = new address[](1);
        winners[0] = winnerAddress;
        this.endGameWithWinners(sessionId, winners);
    } else {
        this.endGameWithDraw(sessionId);
    }
    
    return sessionId;
}
```

4. **Handle session lifecycle**
```solidity
function _onGameSessionStarted(uint256 sessionId, address[] calldata players) internal override {
    // Initialize game state
}

function _onGameSessionEnded(uint256 sessionId, address[] memory winners) internal override {
    // Clean up and emit events
}
```

### Best Practices

1. **Always validate session state** before game actions
2. **Clean up state** in session end hooks
3. **Use appropriate TTL** for your game type
4. **Handle edge cases** like timeouts and draws
5. **Emit events** for transparency
6. **Test thoroughly** with the test suite
7. **Verify** your contracts for transparency
8. **Open source** your project code

### Common Patterns

#### Single Winner Games
```solidity
this.endGameWithWinner(sessionId, winnerAddress);
```

#### Multiple Winner Games (Ranked)
```solidity
address[] memory winners = new address[](3);
winners[0] = firstPlace;
winners[1] = secondPlace;
winners[2] = thirdPlace;
this.endGameWithWinners(sessionId, winners);
```

#### Draw Games
```solidity
this.endGameWithDraw(sessionId);
```

#### Player Count Validation
```solidity
require(
    this.supportsPlayerCount(players.length),
    "Invalid player count"
);
```

---

## Testing

See the test files for comprehensive examples:
- `test/game-hub/TaikoGameHubSimple.t.sol` - Core TaikoGameHub functionality
- `test/game-hub/BaseGame.t.sol` - BaseGame integration patterns

Run tests with:
```bash
forge test --match-path "test/game-hub/*"
```
