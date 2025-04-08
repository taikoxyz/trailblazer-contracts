// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../trailblazers-season-2/TrailblazersS1BadgesV8.sol";

contract TrailblazersBadgesV9 is TrailblazersBadgesV8 {
    /// @notice Errors
    error BADGE_STILL_LOCKED(uint256 seasonId, uint256 seasonEnd, uint256 ts);
    error NO_ACTIVE_SEASON();

    /// @notice Updated version function
    /// @return Version string
    function version() external pure virtual override returns (string memory) {
        return "V9";
    }

    /// @notice Contains the ts for each season's end, index 1 being season 1
    mapping(uint256 season => uint256 endTimestamp) public seasonEndTimestamps;
    /// @notice Helper variable to track the last known steason
    uint256 public lastKnownSeason;

    /// @notice Setter for season end timestamps
    /// @param _season Season number
    /// @param _timestamp Timestamp
    /// @dev Only owner can set the timestamp
    function setSeasonEndTimestamp(uint256 _season, uint256 _timestamp) public virtual onlyOwner {
        seasonEndTimestamps[_season] = _timestamp;

        if (_season > lastKnownSeason) {
            lastKnownSeason = _season;
        }
    }

    /// @notice Get the current season ID
    /// @return Season ID
    function getCurrentSeasonId() public view virtual returns (uint256) {
        for (uint256 i = 0; i <= lastKnownSeason; i++) {
            if (block.timestamp < seasonEndTimestamps[i]) {
                return i;
            }
        }
        revert NO_ACTIVE_SEASON();
    }

    /// @notice Get the current season's end timestamp
    /// @return Season end timestamp
    function getCurrentSeasonEndTimestamp() public view virtual returns (uint256) {
        uint256 seasonId = getCurrentSeasonId();
        return seasonEndTimestamps[seasonId];
    }

    /// @notice Modifier to ensure a badge isn't locked on a recruitment for that season
    /// @param _tokenId Badge token id
    modifier isNotLockedV9(uint256 _tokenId) virtual {
        uint256 unlockTimestamp = unlockTimestamps[_tokenId];
        uint256 seasonEndTimestamp = getCurrentSeasonEndTimestamp();
        if (
            unlockTimestamp > 0 && block.timestamp < seasonEndTimestamp
                && block.timestamp < unlockTimestamp
        ) {
            revert BADGE_STILL_LOCKED(getCurrentSeasonId(), seasonEndTimestamp, block.timestamp);
        }
        _;
    }

    /// @notice Overwritten update function that prevents locked badges from being transferred
    /// @param to Address to transfer badge to
    /// @param tokenId Badge token id
    /// @param auth Address to authorize transfer
    /// @return Address of the recipient
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        virtual
        override
        isNotLockedV9(tokenId)
        returns (address)
    {
        return TrailblazersBadgesV3._update(to, tokenId, auth);
    }

    /// @notice Start recruitment for a badge
    /// @param _badgeId Badge ID
    /// @param _tokenId Token ID
    function startRecruitment(
        uint256 _badgeId,
        uint256 _tokenId
    )
        public
        virtual
        override
        isNotLockedV9(_tokenId)
    {
        if (recruitmentLockDuration == 0) {
            revert RECRUITMENT_LOCK_DURATION_NOT_SET();
        }
        if (ownerOf(_tokenId) != _msgSender()) {
            revert NOT_OWNER();
        }

        uint256 seasonEndTimestamp = getCurrentSeasonEndTimestamp();
        unlockTimestamps[_tokenId] = seasonEndTimestamp;

        recruitmentContractV2.startRecruitment(_msgSender(), _badgeId, _tokenId);
    }

    /// @notice Check if a badge is locked
    /// @param tokenId Badge token id
    /// @return True if locked
    function isLocked(uint256 tokenId) public view virtual override returns (bool) {
        uint256 seasonEndTimestamp = getCurrentSeasonEndTimestamp();
        if (unlockTimestamps[tokenId] > 0 && block.timestamp < seasonEndTimestamp) {
            return true;
        }
        return false;
    }
}
