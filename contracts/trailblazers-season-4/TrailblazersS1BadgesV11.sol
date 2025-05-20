// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TrailblazersS1BadgesV10.sol";

contract TrailblazersBadgesV11 is TrailblazersBadgesV10 {
    /// @notice Updated version function
    /// @return Version string
    function version() external pure virtual override returns (string memory) {
        return "V11";
    }

    /// @notice Check if a badge is locked
    /// @param _tokenId Badge token id
    /// @return True if locked
    function isLocked(uint256 _tokenId) public view virtual override returns (bool) {
        uint256 unlockTimestamp = unlockTimestamps[_tokenId];
        uint256 seasonEndTimestamp = getCurrentSeasonEndTimestamp();
        if (
            unlockTimestamp > 0 && block.timestamp < seasonEndTimestamp
                && block.timestamp < unlockTimestamp
        ) {
            return true;
        }
        return false;
    }

    /// @notice Modifier to ensure a badge isn't locked on a recruitment for that season
    /// @param _tokenId Badge token id
    modifier isNotLockedV11(uint256 _tokenId) virtual {
        if (isLocked(_tokenId)) {
            revert BADGE_STILL_LOCKED(
                getCurrentSeasonId(), getCurrentSeasonEndTimestamp(), block.timestamp
            );
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
        isNotLockedV11(tokenId)
        returns (address)
    {
        return TrailblazersBadgesV3._update(to, tokenId, auth);
    }

    /// @notice Start recruitment for a badge
    /// @param _badgeId Badge ID
    /// @param _tokenId Token ID
    function startRecruitment(uint256 _badgeId, uint256 _tokenId) public virtual override {
        if (recruitmentLockDuration == 0) {
            revert RECRUITMENT_LOCK_DURATION_NOT_SET();
        }
        if (ownerOf(_tokenId) != _msgSender()) {
            revert NOT_OWNER();
        }

        uint256 seasonEndTimestamp = getCurrentSeasonEndTimestamp();

        // monk patch
        if (_badgeId == BADGE_MONKS && seasonEndTimestamps[3] == unlockTimestamps[_tokenId]) {
            unlockTimestamps[_tokenId] = seasonEndTimestamps[4];
        } else if (isLocked(_tokenId)) {
            revert BADGE_STILL_LOCKED(getCurrentSeasonId(), seasonEndTimestamp, block.timestamp);
        } else {
            unlockTimestamps[_tokenId] = seasonEndTimestamp;
        }

        recruitmentContractV2.startRecruitment(_msgSender(), _badgeId, _tokenId);
    }
}
