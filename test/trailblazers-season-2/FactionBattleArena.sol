// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/src/Test.sol";

import { TrailblazersBadges } from "../../contracts/trailblazers-badges/TrailblazersBadges.sol";
import { FactionBattleArena } from "../../contracts/trailblazers-season-2/FactionBattleArena.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UtilsScript } from "../../script/taikoon/sol/Utils.s.sol";
import { MockBlacklist } from "../util/Blacklist.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV8.sol";
import "../util/TrailblazerBadgesS1MintTo.sol";

contract FactionBattleArenaTest is Test {
    UtilsScript public utils;

    TrailblazersBadges public token;

    address public owner = vm.addr(0x5);

    address[8] public minters = [
        vm.addr(0x1),
        vm.addr(0x2),
        vm.addr(0x3),
        vm.addr(0x4),
        vm.addr(0x5),
        vm.addr(0x6),
        vm.addr(0x7),
        vm.addr(0x8)
    ];

    uint256 constant TOURNAMENT_SEED = 1_234_567_890;

    uint256[8] public BADGE_IDS = [0, 1, 2, 3, 4, 5, 6, 7];

    MockBlacklist public blacklist;

    address mintSigner;
    uint256 mintSignerPk;

    FactionBattleArena public badgeChampions;

    mapping(address player => uint256 badgeId) public playersToBadgeIds;
    mapping(address player => uint256 tokenId) public playersToTokenIds;

    uint64 constant OPEN_TIME = 10_000;
    uint64 constant EXECUTE_TIME = 20_000;
    TrailblazersBadgesV8 public s1Badges;

        TrailblazersBadgesS2 public s2Badges;

    BadgeRecruitment public recruitmentV1;
    BadgeRecruitmentV2 public recruitment;


    uint256 public SEASON_2_END = 2_000_000_000;
    uint256 public SEASON_3_END = 3_000_000_000;

    function _deployBadges() public {
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


        // upgrade s1 contract to v4
        s1BadgesV2.upgradeToAndCall(
            address(new TrailblazersBadgesV7()), abi.encodeCall(TrailblazersBadgesV7.version, ())
        );

        TrailblazersBadgesV7 s1BadgesV7 = TrailblazersBadgesV7(address(s1BadgesV2));

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
            1 hours,
            5 minutes,
            5,
            3,
            100,
            7
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
        enabledBadgeIds[0] = BADGE_IDS[0];
        recruitmentV1.enableRecruitments(enabledBadgeIds);

        recruitmentV1.upgradeToAndCall(
            address(new BadgeRecruitmentV2()), abi.encodeCall(BadgeRecruitmentV2.version, ())
        );

        recruitment = BadgeRecruitmentV2(address(recruitmentV1));

        assertEq(recruitment.version(), "V2");

        s1BadgesV7.setRecruitmentContractV2(address(recruitment));

        vm.stopPrank();

        vm.startPrank(owner);
        s1BadgesV7.upgradeToAndCall(
            address(new TrailblazersBadgesV8()), abi.encodeCall(TrailblazersBadgesV8.version, ())
        );

        s1Badges = TrailblazersBadgesV8(address(s1BadgesV7));
        s1Badges.setSeason2EndTimestamp(SEASON_2_END);
        s1Badges.setSeason3EndTimestamp(SEASON_3_END);
        assertEq(s1Badges.version(), "V8");
        vm.stopPrank();

    }
    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();
        blacklist = new MockBlacklist();

        _deployBadges();


        // create whitelist merkle tree
        vm.startPrank(owner);

        (mintSigner, mintSignerPk) = makeAddrAndKey("mintSigner");


        // deploy badge champions
        address impl = address(new FactionBattleArena());
        address proxy = address(
            new ERC1967Proxy(
                impl, abi.encodeCall(FactionBattleArena.initialize,
                 FactionBattleArena.Config({
                    leagueDuration: 1 hours,
                    s1Badges: address(s1Badges),
                    s2Badges: address(s2Badges)
                    }))
            )
        );

        badgeChampions = FactionBattleArena(proxy);
        vm.stopPrank();

        // mint some badges
        for (uint256 i = 0; i < minters.length; i++) {
            bytes32 _hash = token.getHash(minters[i], BADGE_IDS[i]);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(mintSignerPk, _hash);

            vm.startPrank(minters[i]);
            token.mint(abi.encodePacked(r, s, v), BADGE_IDS[i]);
            vm.stopPrank();
    uint256 tokenId = token.tokenOfOwnerByIndex(minters[i], 0);
            playersToTokenIds[minters[i]] = tokenId;
            playersToBadgeIds[minters[i]] = BADGE_IDS[i];
        }
    }

    function test_metadata_badges() public view {
        assertEq(token.BADGE_RAVERS(), 0);
        assertEq(token.BADGE_ROBOTS(), 1);
        assertEq(token.BADGE_BOUNCERS(), 2);
        assertEq(token.BADGE_MASTERS(), 3);
        assertEq(token.BADGE_MONKS(), 4);
        assertEq(token.BADGE_DRUMMERS(), 5);
        assertEq(token.BADGE_ANDROIDS(), 6);
        assertEq(token.BADGE_SHINTO(), 7);
    }

    function test_admin_startLeague() public {
        // create league
        vm.prank(owner);
        badgeChampions.startLeague();

        // check league
        FactionBattleArena.League memory league = badgeChampions.getCurrentLeague();

        assertEq(league.openTime, OPEN_TIME);
        assertEq(league.executeTime, EXECUTE_TIME);
        assertEq(league.seed, 0);
    }

    function test_revert_leagueNotOpen() public {
        test_admin_startLeague();
        vm.startPrank(minters[0]);
        vm.expectRevert();
        badgeChampions.registerParticipant(
            1, // static season 1 set
            playersToTokenIds[minters[0]], playersToBadgeIds[minters[0]]);
        vm.stopPrank();
    }

    function wait(uint256 time) public {
        vm.warp(block.timestamp + time);
    }

    function test_registerParticipant() public {
        test_admin_startLeague();

        wait(OPEN_TIME + 1);
        // register champion
        vm.prank(minters[0]);
        badgeChampions.registerParticipant(
            1, // static season 1 set
            playersToTokenIds[minters[0]], playersToBadgeIds[minters[0]]);

        // check league
        FactionBattleArena.League memory league = badgeChampions.getCurrentLeague();

        assertEq(league.openTime, OPEN_TIME);
        assertEq(league.executeTime, EXECUTE_TIME);

        assertEq(league.seed, 0);
    }

    function test_revert_registerParticipant_notOwned() public {
        test_admin_startLeague();

        wait(OPEN_TIME + 1);
        // register champion
        vm.startPrank(minters[1]);
        vm.expectRevert();
        badgeChampions.registerParticipant(
            1, // static season 1 set
            playersToTokenIds[minters[1]], playersToBadgeIds[minters[1]]);
        vm.stopPrank();
    }

    function test_registerParticipant_all() public {
        test_admin_startLeague();

        wait(OPEN_TIME + 1);
        // register champion
        for (uint256 i = 0; i < minters.length; i++) {
            vm.prank(minters[i]);
            badgeChampions.registerParticipant(
            1, // static season 1 set
            playersToTokenIds[minters[i]], playersToBadgeIds[minters[i]]);
        }

        // check league
        FactionBattleArena.League memory league = badgeChampions.getCurrentLeague();

        assertEq(league.openTime, OPEN_TIME);
        assertEq(league.executeTime, EXECUTE_TIME);

        assertEq(league.seed, 0);
    }

    function test_revert_startLeague_notAdmin() public {
        test_registerParticipant_all();

        wait(EXECUTE_TIME + 1);
        // start league
        vm.startPrank(minters[0]);
        vm.expectRevert();
        badgeChampions.startLeague(TOURNAMENT_SEED);
        vm.stopPrank();
    }

    function test_register_erc1155() public{
        // todo
    }
}
