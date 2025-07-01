# TaikoGameHub Integration Guide

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Environment Setup](#development-environment-setup)
3. [Building Your First Game](#building-your-first-game)
4. [Advanced Features](#advanced-features)
5. [Testing Your Game](#testing-your-game)
6. [Deployment Guide](#deployment-guide)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Getting Started

The TaikoGameHub provides a complete infrastructure for building multiplayer games on the Taiko network. This guide will walk you through creating your first game contract.

### Prerequisites

- Solidity ^0.8.24
- Foundry development framework
- Basic understanding of smart contracts
- Node.js and npm/pnpm (for package management)

### Architecture Overview

```
Your Game Contract
       ↓
   BaseGame (inherit)
       ↓
   TaikoGameHub (proxy)
       ↓
   Player Management & Sessions
```

## Development Environment Setup

### 1. Clone the Repository

```bash
git clone https://github.com/taikoxyz/trailblazer-contracts
cd trailblazer-contracts
```

### 2. Install Dependencies

```bash
# Install Foundry dependencies
forge install

# Install Node.js dependencies
pnpm install
```

### 3. Set Up Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# Add RPC URLs, private keys, etc.
```

### 4. Run Tests

```bash
# Test the TaikoGameHub system
forge test --match-path "test/game-hub/*"

# Run with verbose output
forge test --match-path "test/game-hub/*" -vvv
```

## Advanced Features

### Multi-Round Games

For games with multiple rounds or phases:

```solidity
enum GamePhase { Preparation, Playing, Voting, Complete }

struct GameState {
    GamePhase phase;
    uint256 currentRound;
    uint256 maxRounds;
    mapping(uint256 => RoundState) rounds;
}

function advancePhase(uint256 sessionId) internal {
    GameState storage gameState = gameStates[sessionId];
    
    if (gameState.phase == GamePhase.Preparation) {
        gameState.phase = GamePhase.Playing;
    } else if (gameState.phase == GamePhase.Playing) {
        gameState.phase = GamePhase.Voting;
    } else if (gameState.phase == GamePhase.Voting) {
        if (gameState.currentRound < gameState.maxRounds) {
            gameState.currentRound++;
            gameState.phase = GamePhase.Playing;
        } else {
            gameState.phase = GamePhase.Complete;
            _determineWinner(sessionId);
        }
    }
}
```

### Ranked Winners

For games with multiple winners:

```solidity
function endGameWithRankedWinners(uint256 sessionId) internal {
    // Calculate player scores
    address[] memory players = _getSessionPlayers(sessionId);
    uint256[] memory scores = new uint256[](players.length);
    
    for (uint256 i = 0; i < players.length; i++) {
        scores[i] = calculatePlayerScore(sessionId, players[i]);
    }
    
    // Sort players by score (implement sorting algorithm)
    (address[] memory sortedPlayers, ) = _sortPlayersByScore(players, scores);
    
    // Take top 3 as winners
    address[] memory winners = new address[](3);
    for (uint256 i = 0; i < 3 && i < sortedPlayers.length; i++) {
        winners[i] = sortedPlayers[i];
    }
    
    this.endGameWithWinners(sessionId, winners);
}
```

### Time-based Mechanics

For games with time limits or phases:

```solidity
mapping(uint256 => uint256) sessionDeadlines;

modifier withinTimeLimit(uint256 sessionId) {
    require(block.timestamp <= sessionDeadlines[sessionId], "Time limit exceeded");
    _;
}

function extendTimeLimit(uint256 sessionId, uint256 extension) internal {
    sessionDeadlines[sessionId] += extension;
}
```

## Testing Your Game

### Testing Strategies

1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test TaikoGameHub integration
3. **Edge Case Tests**: Test error conditions
4. **Gas Tests**: Optimize gas usage


## Deployment Guide

### 1. Prepare Environment

```bash
# Set up environment variables
export PRIVATE_KEY="your_private_key"
export GAME_HUB_ADDRESS="deployed_gamehub_address"
export RPC_URL="your_rpc_url"
```

Configure your deployment script, e.g. `DeployYourFancyGame.s.sol`

### 2. Deploy Your Game

```bash
forge script script/game-hub/DeployYourFancyGame.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify
```

### 3. Whitelist Your Game

After deployment, the TaikoGameHub owner must whitelist your game:

```solidity
// Call this function as TaikoGameHub owner
gameHub.addToWhitelist(yourGameAddress);
```

Reach out to our team via provided channels. Please note we will only accept decent quality games and verified contracts.

### 4. Verify Deployment

```bash
# Check if game is whitelisted
cast call $GAME_HUB_ADDRESS "isWhitelisted(address)" $YOUR_GAME_ADDRESS --rpc-url $RPC_URL
```

## Best Practices

### Security

1. **Validate All Inputs**: Always check parameters
2. **Prevent Reentrancy**: Use proper modifiers
3. **Handle Edge Cases**: Test boundary conditions
4. **Secure Randomness**: Use proper random sources
5. **Access Control**: Implement proper permissions

### Gas Optimization

1. **Batch Operations**: Reduce transaction count
2. **Efficient Storage**: Minimize storage operations
3. **Event Emission**: Use events for off-chain data
4. **Loop Limits**: Avoid unbounded loops

### User Experience

1. **Clear Error Messages**: Provide helpful feedback
2. **Event Emission**: Keep users informed
3. **Gas Estimation**: Provide gas estimates
4. **Documentation**: Write clear function docs


## Troubleshooting

### Common Issues

#### 1. "Game not whitelisted" Error

**Problem**: Your game contract isn't approved by TaikoGameHub

**Solution**:
```solidity
// Have TaikoGameHub owner call:
gameHub.addToWhitelist(yourGameAddress);
```

#### 2. "Player already locked" Error

**Problem**: Player is already in another active session

**Solution**: Check player status before starting:
```solidity
require(!gameHub.isPlayerLocked(player), "Player is busy");
```

#### 3. Session Not Found

**Problem**: Using invalid session ID

**Solution**: Always validate session existence:
```solidity
require(gameHub.isSessionActive(sessionId), "Invalid session");
```

#### 4. Gas Limit Issues

**Problem**: Transactions running out of gas

**Solution**: Optimize loops and storage:
```solidity
// Instead of:
for (uint256 i = 0; i < largeArray.length; i++) {
    // expensive operation
}

// Use:
function processInBatches(uint256 startIndex, uint256 batchSize) external {
    uint256 endIndex = startIndex + batchSize;
    if (endIndex > largeArray.length) endIndex = largeArray.length;
    
    for (uint256 i = startIndex; i < endIndex; i++) {
        // expensive operation
    }
}
```

### Debug Tools

```solidity
// Add debug events for testing
event Debug(string message, uint256 value);
emit Debug("Player count", players.length);

// Use require with descriptive messages
require(condition, "Specific error description");

// Add view functions for state inspection
function getGameStateForDebug(uint256 sessionId) external view returns (...) {
    // Return internal state for debugging
}
```

### Getting Help

1. **Documentation**: Check the API docs
2. **Tests**: Look at test files for patterns
4. **Community**: Join the Taiko Discord
4. **Issues**: Report bugs on GitHub

---

This guide should get you started with building games on the TaikoGameHub platform. For more advanced features and patterns, check out the full API documentation.
