// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import { AccessControlUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import { IMinimalBlacklist } from "@taiko/blacklist/IMinimalBlacklist.sol";
import { UUPSUpgradeable } from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./TrailblazersS1BadgesV8.sol";
import "./TrailblazersBadgesS2.sol";

contract FactionBattleArena is
    PausableUpgradeable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable
{
    /*
    struct Champion {
        address owner;
        address badgeContract;
        uint256 tokenId;
        uint256 leagueId;
        uint256 color; // 0 = neutral, 1 = pink, 2 = purple
    }

    struct League {
        uint64 openTime; // registration starts
        uint64 closeTime; // registration ends
        uint64 startTime; // league starts (requires admin action)
        uint256 seed;
    }

    mapping(uint256 leagueId => League league) public leagues;
    uint256 public currentLeagueId = 0;

    TrailblazersBadges public season1Badges;
    TrailblazersBadgesS2 public season2Badges;

    event LeagueCreated(
        uint256 indexed leagueId, uint256 openTime, uint256 startTime, uint256 endTime
    );
    event LeagueStarted(uint256 leagueId, uint256 seed);

    event ParticipantRegistered(
        uint256 indexed leagueId,
        address indexed owner,
        address badgesContract,
        uint256 tokenId,
        uint256 power,
        uint256 badgeId
    );

    error ELEMENT_NOT_FOUND();
    error TOURNAMENT_NOT_STARTED();
    error TOURNAMENT_NOT_OPEN();
    error TOURNAMENT_NOT_CLOSED();
    error TOURNAMENT_NOT_ENDED();
    error CHAMPION_NOT_OWNED();
    error INVALID_PARTICIPANT_COUNT();
    error INVALID_ROUND();
    error INVALID_CHAMPION_CONTRACT();
    error INVALID_MATCH();

    modifier leagueOpen(uint256 _leagueId) {
        League memory league = leagues[_leagueId];
        if (block.timestamp < league.openTime || block.timestamp > league.closeTime) {
            revert TOURNAMENT_NOT_OPEN();
        }

        _;
    }

    modifier ownedToken(address _badgeContract, uint256 _badgeId) {
        // TODO: erc1155 ownership checkup for s2 badges
        uint256 tokenId = season1Badges.getTokenId(_msgSender(), _badgeId);

        if (
            season1Badges.ownerOf(tokenId) != _msgSender()
                && season1Badges.getApproved(tokenId) != address(this)
                && season1Badges.isApprovedForAll(_msgSender(), address(this))
        ) {
            revert CHAMPION_NOT_OWNED();
        }

        _;
    }

    function initialize(address _season1Badges, address _season2Badges) external initializer {
        __Context_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _transferOwnership(_msgSender());
        season1Badges = TrailblazersBadges(_season1Badges);
        season2Badges = TrailblazersBadgesS2(_season2Badges);
    }

    function getCurrentLeague() public view returns (League memory league) {
        return getLeague(currentLeagueId);
    }

    function getLeague(uint256 _leagueId) public view returns (League memory league) {
        return leagues[_leagueId];
    }

    function createLeague(
        uint64 _openTime,
        uint64 _closeTime,
        uint64 _startTime
    )
        public
        onlyOwner
    {
        League memory league =
            League({ openTime: _openTime, closeTime: _closeTime, startTime: _startTime, seed: 0 });
        currentLeagueId += 1;

        leagues[currentLeagueId] = league;

        emit LeagueCreated(currentLeagueId, _openTime, _closeTime, _startTime);
    }

    function calculatePower(uint256 _badgeId) public pure returns (uint256) {
        return ((1 + _badgeId) * 125) / 10;
        //return powerLevels[_badgeId % powerLevels.length];
    }

    function _registerChampionFor(
        address _player,
        address _badgeContract,
        uint256 _badgeId
    )
        internal
    {
        if (_badgeContract != address(season1Badges) && _badgeContract != address(season2Badges)) {
            revert INVALID_CHAMPION_CONTRACT();
        }

        uint256 tokenId = season1Badges.getTokenId(_player, _badgeId);
        uint256 power = calculatePower(_badgeId);

        emit ParticipantRegistered(currentLeagueId, _player, _badgeContract, tokenId, power, _badgeId);
    }

    function registerChampionFor(
        address _player,
        address _badgeContract,
        uint256 _badgeId
    )
        public
        onlyOwner
    {
        _registerChampionFor(_player, _badgeContract, _badgeId);
    }

    function registerChampion(
        address _badgeContract,
        uint256 _badgeId
    )
        public
        leagueOpen(currentLeagueId)
        ownedToken(_badgeContract, _badgeId)
    {
        _registerChampionFor(_msgSender(), _badgeContract, _badgeId);
    }

    function startLeague(uint256 seed) public onlyOwner {
        League storage league = leagues[currentLeagueId];
        league.seed = seed;
        emit LeagueStarted(currentLeagueId, seed);
    }

    function calculateAdvantage(
        uint256 _colorLeft,
        uint256 _colorRight
    )
        public
        pure
        returns (bool leftAdvantage, bool rightAdvantage)
    {
        // neutral >> pink >> purple
        // 0 >> 1 >> 2
        if (_colorLeft == 0 && _colorRight == 1) {
            return (true, false);
        } else if (_colorLeft == 0 && _colorRight == 2) {
            return (true, false);
        } else if (_colorLeft == 1 && _colorRight == 0) {
            return (false, true);
        } else if (_colorLeft == 1 && _colorRight == 2) {
            return (true, false);
        } else if (_colorLeft == 2 && _colorRight == 0) {
            return (false, true);
        } else if (_colorLeft == 2 && _colorRight == 1) {
            return (false, true);
        } else {
            return (false, false);
        }
    }

    function getChampionId(
        uint256 _leagueId,
        address _owner,
        address _badgeContract,
        uint256 _tokenId
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_owner, _badgeContract, _tokenId, _leagueId));
    }


*/
/////////////////////////////////
/*
struct Participant {
   bytes32 id;
   uint256 leagueId;
   address owner;
   uint256 badgeSeason;
   uint256 badgeId;
   uint256 tokenId;
}*/

/// @notice Movement types
    enum MovementType {
        Dev, // unused
        Whale, // s1 based/pink
        Minnow // s1 boosted/purple
    }

struct League {
        uint256 openTime; // registration starts
        uint256 executeTime; // league starts (requires admin action)
        uint256 seed;
    }


struct Config {
    uint64 leagueDuration;
    address s1Badges;
    address s2Badges;
}

Config public config;

    mapping(uint256 leagueId => League league) public leagues;
    mapping(uint256 leagueId => mapping(uint256 tokenId => bool registered)) participants;
    uint256 public currentLeagueId = 0;

 event LeagueCreated(
        uint256 indexed leagueId, uint256 openTime, uint256 executeTime
    );
    event LeagueExecuted(uint256 leagueId, uint256 seed);

    event ParticipantRegistered(
        uint256 indexed leagueId,
        address indexed owner,
        bytes32 participantId,
        uint256 badgeSeason,
        uint256 badgeId,
        MovementType movementType,
        uint256 tokenId
    );

    // Errors

    error EXECUTION_TOO_EARLY();
error TOKEN_NOT_OWNED();
error INVALID_SEASON();
error TOKEN_ALREADY_REGISTERED();

modifier canAlterLeague() {
    if (block.timestamp < leagues[currentLeagueId].executeTime) {
        revert EXECUTION_TOO_EARLY();
    }
    _;
}

    function initialize(Config memory _config) external initializer {
        __Context_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _transferOwnership(_msgSender());
        config = _config;
    }

function getChampionId(
        uint256 _leagueId,
        address _owner,
        uint256 _badgeSeason,
        uint256 _tokenId
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_owner, _badgeSeason, _tokenId, _leagueId));
    }

function registerParticipant(
     uint256 _badgeSeason,
     uint256 _badgeId,
    uint256 _tokenId
) public {
    // ensure the token isn't registered in the current league
    if (participants[currentLeagueId][_tokenId]) {
        revert TOKEN_ALREADY_REGISTERED();
    }
    // ensure ownership of the token, season-driven
    if (_badgeSeason == 1 && ERC721(config.s1Badges).ownerOf(_tokenId) != _msgSender()) {
        revert TOKEN_NOT_OWNED();
    } else if (_badgeSeason == 2 && ERC1155(config.s2Badges).balanceOf(_msgSender(), _tokenId) == 0) {
        revert TOKEN_NOT_OWNED();
    } else if (_badgeSeason < 1 || _badgeSeason > 2) {
        revert INVALID_SEASON();
    }

    // assign the movement for the badge
    MovementType movementType = _badgeSeason == 1 ?
    MovementType.Dev
    : TrailblazersBadgesS2(config.s2Badges).getBadge(_tokenId).movementType == TrailblazersBadgesS2.MovementType.Whale ? MovementType.Whale : MovementType.Minnow;


    bytes32 participantId = getChampionId(currentLeagueId, _msgSender(), _badgeSeason, _tokenId);

    emit ParticipantRegistered(currentLeagueId, _msgSender(),
    participantId,
    _badgeSeason,
    _badgeId,
    movementType,
    _tokenId);

    participants[currentLeagueId][_tokenId] = true;
}


// admin methods


function _startLeague(uint256 _startTs)  internal {
    currentLeagueId += 1;
    leagues[currentLeagueId] = League({
        openTime: _startTs,
        executeTime: _startTs + config.leagueDuration,
        seed: 0
    });

    emit LeagueCreated(currentLeagueId,
    leagues[currentLeagueId].openTime, leagues[currentLeagueId].executeTime);
}

function _executeLeague(uint256 _seed)  internal {
    League memory league = leagues[currentLeagueId];
    league.seed = _seed;
    leagues[currentLeagueId] = league;
    emit LeagueExecuted(currentLeagueId, league.seed);
}

function executeLeagueAndStartNext(uint256 _seed) public onlyOwner canAlterLeague {
    _executeLeague(_seed);
    _startLeague(block.timestamp);
}

function startLeague() public onlyOwner canAlterLeague {
    _startLeague(block.timestamp);
}

function startLeague(uint256 _startTs) public onlyOwner canAlterLeague {
    _startLeague(_startTs);
}
function executeLeague(uint256 _seed) public onlyOwner canAlterLeague {
    _executeLeague(_seed);
}

// todo: flush current league
function abortLeague()  public onlyOwner{}


function getCurrentLeague() public view returns (League memory league) {
        return leagues[currentLeagueId];
    }

    ///////////////////////////////////////

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address) internal virtual override onlyOwner { }
}
