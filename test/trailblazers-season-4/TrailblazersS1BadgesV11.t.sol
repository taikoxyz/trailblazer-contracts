// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/src/Test.sol";

import { TrailblazersBadges } from "../../contracts/trailblazers-badges/TrailblazersBadges.sol";
import { Merkle } from "murky/Merkle.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UtilsScript } from "../../script/taikoon/sol/Utils.s.sol";
import { MockBlacklist } from "../util/Blacklist.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TrailblazersBadgesS2 } from
    "../../contracts/trailblazers-season-2/TrailblazersBadgesS2.sol";
import { TrailblazerBadgesS1MintTo } from "../util/TrailblazerBadgesS1MintTo.sol";
import { TrailblazersBadgesV7 } from
    "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV7.sol";
import "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV8.sol";
import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV9.sol";
import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV10.sol";
import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV11.sol";
import { BadgeRecruitment } from "../../contracts/trailblazers-season-2/BadgeRecruitment.sol";
import { BadgeRecruitmentV2 } from "../../contracts/trailblazers-season-2/BadgeRecruitmentV2.sol";
import "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV7.sol";

contract TrailblazersS1BadgesV11Test is Test {
    UtilsScript public utils;

    TrailblazersBadgesV11 public s1BadgesV11;
    TrailblazersBadgesV10 public s1BadgesV10;
    TrailblazersBadgesV9 public s1BadgesV9;
    TrailblazersBadgesV8 public s1BadgesV8;
    TrailblazersBadgesV7 public s1BadgesV7;
    TrailblazersBadgesS2 public s2Badges;

    address public owner = vm.addr(0x5);

    address[3] public minters = [vm.addr(0x1), vm.addr(0x2), vm.addr(0x3)];

    uint256 public BADGE_ID;

    MockBlacklist public blacklist;

    address mintSigner;
    uint256 mintSignerPk;

    uint256 public MAX_INFLUENCES = 3;
    uint256 public COOLDOWN_RECRUITMENT = 1 hours;
    uint256 public COOLDOWN_INFLUENCE = 5 minutes;
    uint256 public INFLUENCE_WEIGHT_PERCENT = 5;
    uint256 public MAX_INFLUENCES_DIVIDER = 100;
    uint256 public DEFAULT_CYCLE_DURATION = 7 days;

    BadgeRecruitment public recruitmentV1;
    BadgeRecruitmentV2 public recruitment;

    uint256 public SEASON_1_END = 1_000_000_000;
    uint256 public SEASON_2_END = 2_000_000_000;
    uint256 public SEASON_3_END = 3_000_000_000;
    uint256 public SEASON_4_END = 4_000_000_000;

    uint256 public TOKEN_ID = 1;

    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();
        blacklist = new MockBlacklist();
        // create whitelist merkle tree
        vm.startPrank(owner);

        (mintSigner, mintSignerPk) = makeAddrAndKey("mintSigner");

        // deploy token with empty root
        address impl = address(new TrailblazersBadges());
        address proxy = address(
            new ERC1967Proxy(
                impl,
                abi.encodeCall(
                    TrailblazersBadges.initialize, (owner, "ipfs://", mintSigner, blacklist)
                )
            )
        );

        TrailblazersBadges s1BadgesV2 = TrailblazersBadges(proxy);

        // upgrade s1 badges contract to use the mock version

        s1BadgesV2.upgradeToAndCall(
            address(new TrailblazerBadgesS1MintTo()),
            abi.encodeCall(TrailblazerBadgesS1MintTo.call, ())
        );

        BADGE_ID = s1BadgesV2.BADGE_RAVERS();

        // upgrade s1 contract to v4
        s1BadgesV2.upgradeToAndCall(
            address(new TrailblazersBadgesV7()), abi.encodeCall(TrailblazersBadgesV7.version, ())
        );

        s1BadgesV7 = TrailblazersBadgesV7(address(s1BadgesV2));

        // upgrade to v7
        s1BadgesV7.upgradeToAndCall(
            address(new TrailblazersBadgesV7()), abi.encodeCall(TrailblazersBadgesV7.version, ())
        );

        s1BadgesV7 = TrailblazersBadgesV7(address(s1BadgesV7));

        // set cooldown recruitment
        s1BadgesV7.setRecruitmentLockDuration(7 days);

        // deploy the s2 erc1155 token contract

        impl = address(new TrailblazersBadgesS2());
        proxy = address(
            new ERC1967Proxy(
                impl,
                abi.encodeCall(TrailblazersBadgesS2.initialize, (address(recruitmentV1), "ipfs://"))
            )
        );
        s2Badges = TrailblazersBadgesS2(proxy);

        // deploy the recruitment contract
        BadgeRecruitment.Config memory config = BadgeRecruitment.Config(
            COOLDOWN_RECRUITMENT,
            COOLDOWN_INFLUENCE,
            INFLUENCE_WEIGHT_PERCENT,
            MAX_INFLUENCES,
            MAX_INFLUENCES_DIVIDER,
            DEFAULT_CYCLE_DURATION
        );

        impl = address(new BadgeRecruitment());
        proxy = address(
            new ERC1967Proxy(
                impl,
                abi.encodeCall(
                    BadgeRecruitment.initialize,
                    (address(s1BadgesV2), address(s2Badges), mintSigner, config)
                )
            )
        );
        recruitmentV1 = BadgeRecruitment(proxy);

        s1BadgesV7.setRecruitmentContract(address(recruitmentV1));
        s2Badges.setMinter(address(recruitmentV1));
        // enable recruitment for BADGE_ID
        uint256[] memory enabledBadgeIds = new uint256[](1);
        enabledBadgeIds[0] = BADGE_ID;
        recruitmentV1.enableRecruitments(enabledBadgeIds);

        recruitmentV1.upgradeToAndCall(
            address(new BadgeRecruitmentV2()), abi.encodeCall(BadgeRecruitmentV2.version, ())
        );

        recruitment = BadgeRecruitmentV2(address(recruitmentV1));

        assertEq(recruitment.version(), "V2");

        s1BadgesV7.setRecruitmentContractV2(address(recruitment));

        // upgrade to v8
        s1BadgesV7.upgradeToAndCall(
            address(new TrailblazersBadgesV8()), abi.encodeCall(TrailblazersBadgesV8.version, ())
        );

        s1BadgesV8 = TrailblazersBadgesV8(address(s1BadgesV7));
        s1BadgesV8.setSeason2EndTimestamp(SEASON_2_END);
        s1BadgesV8.setSeason3EndTimestamp(SEASON_3_END);

        vm.stopPrank();
    }

    function wait(uint256 time) public {
        vm.warp(block.timestamp + time);
    }

    function _upgradeV9() public {
        vm.startPrank(owner);

        s1BadgesV8.upgradeToAndCall(
            address(new TrailblazersBadgesV9()), abi.encodeCall(TrailblazersBadgesV9.version, ())
        );
        s1BadgesV9 = TrailblazersBadgesV9(address(s1BadgesV8));
        assertEq(s1BadgesV9.version(), "V9");
        // s1
        s1BadgesV9.setSeasonEndTimestamp(1, SEASON_1_END);
        assertEq(s1BadgesV9.seasonEndTimestamps(1), SEASON_1_END);
        // s2
        s1BadgesV9.setSeasonEndTimestamp(2, SEASON_2_END);
        assertEq(s1BadgesV9.seasonEndTimestamps(2), SEASON_2_END);
        // s3
        s1BadgesV9.setSeasonEndTimestamp(3, SEASON_3_END);
        assertEq(s1BadgesV9.seasonEndTimestamps(3), SEASON_3_END);
        // s4
        s1BadgesV9.setSeasonEndTimestamp(4, SEASON_4_END);
        assertEq(s1BadgesV9.seasonEndTimestamps(4), SEASON_4_END);

        vm.stopPrank();
    }

    function _upgradeV10() public {
        vm.startPrank(owner);

        s1BadgesV9.upgradeToAndCall(
            address(new TrailblazersBadgesV10()), abi.encodeCall(TrailblazersBadgesV10.version, ())
        );
        s1BadgesV10 = TrailblazersBadgesV10(address(s1BadgesV8));
        assertEq(s1BadgesV10.version(), "V10");
        vm.stopPrank();
    }

    function _upgradeV11() public {
        vm.startPrank(owner);

        s1BadgesV10.upgradeToAndCall(
            address(new TrailblazersBadgesV11()), abi.encodeCall(TrailblazersBadgesV11.version, ())
        );
        s1BadgesV11 = TrailblazersBadgesV11(address(s1BadgesV10));
        assertEq(s1BadgesV11.version(), "V11");
        vm.stopPrank();
    }

    function test_getCurrentSeasonId() public {
        _upgradeV9();
        _upgradeV10();
        vm.warp(SEASON_1_END - 1);
        assertEq(s1BadgesV10.getCurrentSeasonId(), 1);
        vm.warp(SEASON_1_END + 1);
        assertEq(s1BadgesV10.getCurrentSeasonId(), 2);
    }

    function test_getCurrentSeasonEndTimestamp() public {
        _upgradeV9();
        _upgradeV10();
        vm.warp(SEASON_1_END - 1);
        assertEq(s1BadgesV10.getCurrentSeasonEndTimestamp(), SEASON_1_END);
        vm.warp(SEASON_1_END + 1);
        assertEq(s1BadgesV10.getCurrentSeasonEndTimestamp(), SEASON_2_END);
    }

    // v9 method
    function test_migrateS2_transferAfter() public {
        // mint a badge
        _upgradeV9();
        vm.warp(SEASON_1_END + 1);
        // set up recruitments
        uint256[] memory enabledBadgeIds = new uint256[](1);
        enabledBadgeIds[0] = BADGE_ID;
        vm.prank(owner);
        recruitment.enableRecruitments(enabledBadgeIds);

        address minter = minters[0];
        vm.startPrank(minter);

        // mint the s1 badge
        bytes32 _hash = s1BadgesV9.getHash(minter, BADGE_ID);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintSignerPk, _hash);

        bool canMint = s1BadgesV9.canMint(abi.encodePacked(r, s, v), minter, BADGE_ID);
        assertTrue(canMint);

        s1BadgesV9.mint(abi.encodePacked(r, s, v), BADGE_ID);
        uint256 tokenId = s1BadgesV9.tokenOfOwnerByIndex(minter, 0);

        // mint and transfer to minter a secondary badge with id 0

        vm.startPrank(minters[1]);
        _hash = s1BadgesV9.getHash(minters[1], BADGE_ID);
        (v, r, s) = vm.sign(mintSignerPk, _hash);
        canMint = s1BadgesV9.canMint(abi.encodePacked(r, s, v), minters[1], BADGE_ID);
        assertTrue(canMint);

        s1BadgesV9.mint(abi.encodePacked(r, s, v), BADGE_ID);
        uint256 secondTokenId = s1BadgesV9.tokenOfOwnerByIndex(minters[1], 0);

        s1BadgesV9.transferFrom(minters[1], minter, secondTokenId);

        // ensure balances
        assertEq(s1BadgesV9.balanceOf(minter), 2);
        assertEq(s1BadgesV9.balanceOf(minters[1]), 0);
        vm.stopPrank();

        // start migration with first badge, using v1 methods
        vm.startPrank(minter);
        wait(100);
        s1BadgesV9.startRecruitment(BADGE_ID, tokenId);
        assertEq(recruitment.isRecruitmentActive(minter), true);
        assertEq(s1BadgesV9.balanceOf(minter), 2);
        assertEq(s1BadgesV9.unlockTimestamps(tokenId), SEASON_2_END);

        // and end it
        wait(COOLDOWN_INFLUENCE);
        wait(COOLDOWN_RECRUITMENT);

        // generate the claim hash for the current recruitment
        bytes32 claimHash = recruitment.generateClaimHash(
            BadgeRecruitment.HashType.End,
            minter,
            0 // experience points
        );

        // simulate the backend signing the hash
        (v, r, s) = vm.sign(mintSignerPk, claimHash);

        // exercise the randomFromSignature function
        recruitment.endRecruitment(claimHash, v, r, s, 0);

        // check for s2 state reset
        assertEq(recruitment.isRecruitmentActive(minter), false);
        assertEq(recruitment.isInfluenceActive(minter), false);

        // check for s2 mint
        assertEq(s2Badges.balanceOf(minter, 1), 1);

        // open a second migration cycle
        vm.stopPrank();
        vm.startPrank(owner);

        // enable recruitment for BADGE_ID
        recruitment.forceDisableAllRecruitments();
        recruitment.enableRecruitments(enabledBadgeIds);
        vm.stopPrank();

        // expect legacy method to fail
        vm.startPrank(minter);
        wait(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailblazersBadgesV9.BADGE_STILL_LOCKED.selector, 2, SEASON_2_END, block.timestamp
            )
        );
        s1BadgesV9.startRecruitment(BADGE_ID, tokenId);
        // time to start the second migration
        wait(100);

        s1BadgesV9.startRecruitment(BADGE_ID, secondTokenId);
        assertEq(recruitment.isRecruitmentActive(minter), true);
        assertEq(s1BadgesV9.balanceOf(minter), 2);
        assertEq(s1BadgesV9.unlockTimestamps(secondTokenId), SEASON_2_END);

        // ensure badge is frozen during season 2
        vm.warp(SEASON_2_END - block.timestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailblazersBadgesV9.BADGE_STILL_LOCKED.selector, 1, SEASON_1_END, block.timestamp
            )
        );
        s1BadgesV9.transferFrom(minter, minters[1], tokenId);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailblazersBadgesV9.BADGE_STILL_LOCKED.selector, 1, SEASON_1_END, block.timestamp
            )
        );
        s1BadgesV9.transferFrom(minter, minters[1], secondTokenId);

        // finish the cycle
        vm.stopPrank();

        vm.startPrank(owner);
        recruitment.forceDisableAllRecruitments();

        // finish the season
        vm.warp(SEASON_2_END + 1);
        // start recruitments

        recruitment.enableRecruitments(enabledBadgeIds);

        assertEq(s1BadgesV9.getCurrentSeasonId(), 3);
        assertEq(s1BadgesV9.getCurrentSeasonEndTimestamp(), SEASON_3_END);
        assertEq(s1BadgesV9.unlockTimestamps(secondTokenId), SEASON_2_END);

        vm.stopPrank();

        vm.startPrank(minter);
        // properly transfer secondTokenId
        s1BadgesV9.transferFrom(minter, minters[1], secondTokenId);

        // run full recruitment with s1 badge again
        wait(100);
        s1BadgesV9.startRecruitment(BADGE_ID, tokenId);
        assertEq(recruitment.isRecruitmentActive(minter), true);
        assertEq(s1BadgesV9.unlockTimestamps(tokenId), SEASON_3_END);

        // and end it
        wait(COOLDOWN_INFLUENCE);
        wait(COOLDOWN_RECRUITMENT);

        // generate the claim hash for the current recruitment
        claimHash = recruitment.generateClaimHash(
            BadgeRecruitment.HashType.End,
            minter,
            0 // experience points
        );

        // simulate the backend signing the hash
        (v, r, s) = vm.sign(mintSignerPk, claimHash);

        // exercise the randomFromSignature function
        recruitment.endRecruitment(claimHash, v, r, s, 0);

        // ensure the badge is frozen during s2
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailblazersBadgesV9.BADGE_STILL_LOCKED.selector, 3, SEASON_3_END, block.timestamp
            )
        );
        s1BadgesV9.transferFrom(minter, minters[1], tokenId);

        // end s3 now
        vm.warp(SEASON_3_END + 1);

        // ensure the badge can be transferred
        s1BadgesV9.transferFrom(minter, minters[1], tokenId);
        assertEq(s1BadgesV9.balanceOf(minters[1]), 2);
        assertEq(s1BadgesV9.balanceOf(minter), 0);

        vm.stopPrank();
    }

    function test_s4_monkCase() public {
        // mint a badge
        vm.warp(SEASON_3_END + 1);
        // set up recruitments
        uint256[] memory enabledBadgeIds = new uint256[](1);
        uint256 monksBadgeId = s1BadgesV8.BADGE_MONKS();
        enabledBadgeIds[0] = monksBadgeId;
        vm.prank(owner);
        recruitment.enableRecruitments(enabledBadgeIds);

        address minter = minters[0];
        vm.startPrank(minter);

        // mint the s1 badge
        bytes32 _hash = s1BadgesV8.getHash(minter, monksBadgeId);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintSignerPk, _hash);

        bool canMint = s1BadgesV8.canMint(abi.encodePacked(r, s, v), minter, monksBadgeId);
        assertTrue(canMint);

        s1BadgesV8.mint(abi.encodePacked(r, s, v), monksBadgeId);
        uint256 tokenId = s1BadgesV8.tokenOfOwnerByIndex(minter, 0);

        // mint and transfer to minter a secondary badge with id 0

        vm.startPrank(minters[1]);
        _hash = s1BadgesV8.getHash(minters[1], monksBadgeId);
        (v, r, s) = vm.sign(mintSignerPk, _hash);
        canMint = s1BadgesV8.canMint(abi.encodePacked(r, s, v), minters[1], monksBadgeId);
        assertTrue(canMint);

        s1BadgesV8.mint(abi.encodePacked(r, s, v), monksBadgeId);
        uint256 secondTokenId = s1BadgesV8.tokenOfOwnerByIndex(minters[1], 0);

        s1BadgesV8.transferFrom(minters[1], minter, secondTokenId);

        // ensure balances
        assertEq(s1BadgesV8.balanceOf(minter), 2);
        assertEq(s1BadgesV8.balanceOf(minters[1]), 0);
        vm.stopPrank();

        // start migration with first badge, using v1 methods
        vm.startPrank(minter);
        wait(100);
        s1BadgesV8.startRecruitment(monksBadgeId, tokenId);
        assertEq(recruitment.isRecruitmentActive(minter), true);
        assertEq(s1BadgesV8.balanceOf(minter), 2);
        // here's the issue
        assertEq(s1BadgesV8.unlockTimestamps(tokenId), SEASON_3_END);

        wait(COOLDOWN_RECRUITMENT);

        // generate the claim hash for the current recruitment
        bytes32 claimHash = recruitment.generateClaimHash(
            BadgeRecruitment.HashType.End,
            minter,
            0 // experience points
        );

        // simulate the backend signing the hash
        (v, r, s) = vm.sign(mintSignerPk, claimHash);

        // exercise the randomFromSignature function
        recruitment.endRecruitment(claimHash, v, r, s, 0);

        vm.stopPrank();
        _upgradeV9();
        assertTrue(s1BadgesV9.isLocked(tokenId));
        // can transfer, shouldn't
        vm.prank(minter);
        s1BadgesV9.transferFrom(minter, minters[1], tokenId);

        assertEq(s1BadgesV9.unlockTimestamps(tokenId), SEASON_3_END);

        assertTrue(s1BadgesV9.isLocked(tokenId));

        // run the current update
        _upgradeV10();

        vm.prank(minters[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailblazersBadgesV9.BADGE_STILL_LOCKED.selector, 4, SEASON_4_END, block.timestamp
            )
        );
        s1BadgesV10.transferFrom(minters[1], minter, tokenId);

    }

    function test_v11() public {
       test_s4_monkCase();
        _upgradeV11();
        vm.warp(SEASON_3_END + 1);

       uint256 tokenId = s1BadgesV11.tokenOfOwnerByIndex(minters[0], 0);
        uint256 secondTokenId = s1BadgesV11.tokenOfOwnerByIndex(minters[1], 0);

       assertFalse(s1BadgesV11.isLocked(tokenId));
         assertFalse(s1BadgesV11.isLocked(secondTokenId));

         // re-enable recruitment cycle
         vm.prank(owner);
                 recruitment.forceDisableAllRecruitments();
         uint256[] memory enabledBadgeIds = new uint256[](1);
        uint256 monksBadgeId = s1BadgesV8.BADGE_MONKS();
        enabledBadgeIds[0] = monksBadgeId;
        vm.prank(owner);
        recruitment.enableRecruitments(enabledBadgeIds);

         // conduct a recruitment
            vm.startPrank(minters[0]);
        s1BadgesV11.startRecruitment(s1BadgesV11.BADGE_MONKS(), tokenId);
        assertEq(s1BadgesV11.unlockTimestamps(tokenId), SEASON_4_END);
        vm.stopPrank();
// check updated states
        assertTrue(s1BadgesV11.isLocked(tokenId));
        assertFalse(s1BadgesV11.isLocked(secondTokenId));
        assertEq(s1BadgesV11.unlockTimestamps(tokenId), SEASON_4_END);
        assertEq(s1BadgesV11.unlockTimestamps(secondTokenId), SEASON_3_END);
    }
}
