// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { UtilsScript, MockBlacklist } from "./Utils.s.sol";
import { Script, console } from "forge-std/src/Script.sol";
import { Merkle } from "murky/Merkle.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TrailblazersBadges } from "../../contracts/trailblazers-badges/TrailblazersBadges.sol";
import { IMinimalBlacklist } from "@taiko/blacklist/IMinimalBlacklist.sol";
import { TrailblazersBadgesS2 } from
    "../../contracts/trailblazers-season-2/TrailblazersBadgesS2.sol";
import "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV8.sol";
import { BadgeRecruitment } from "../../contracts/trailblazers-season-2/BadgeRecruitment.sol";
import "../../contracts/trailblazers-season-2/FactionBattleArena.sol";

contract FactionBattleArenaDeployScript is Script {
    UtilsScript public utils;
    string public jsonLocation;
    uint256 public deployerPrivateKey;
    address public deployerAddress;

    BadgeRecruitment recruitment;

    uint64 public constant CONFIG_LEAGUE_DURATION = 1 hours;
    TrailblazersBadgesV8 public s1Token;
    TrailblazersBadgesS2 public s2Token;

    FactionBattleArena public arena;

    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();

        jsonLocation = utils.getFbaContractJsonLocation();

        deployerPrivateKey = utils.getPrivateKey();
        deployerAddress = utils.getAddress();
    }

    function run() public {
        string memory jsonRoot = "root";

        address impl;
        address proxy;
        vm.startBroadcast(deployerPrivateKey);

        if (block.chainid == 167_000) {
            // mainnet
            s1Token = TrailblazersBadgesV8(0xa20a8856e00F5ad024a55A663F06DCc419FFc4d5);
            s2Token = TrailblazersBadgesS2(0x52A7dBeC10B404548066F59DE89484e27b4181dA);
        } else {
            // hekla
            s1Token = TrailblazersBadgesV8(0xEB310b20b030e9c227Ac23e0A39FE6a6e09Ba755);
            s2Token = TrailblazersBadgesS2(0xC50b384b26a0118A6F896Cb58C331e83d51973d2);
        }

        // deploy the recruitment contract

        FactionBattleArena.Config memory config =
            FactionBattleArena.Config(CONFIG_LEAGUE_DURATION, address(s1Token), address(s2Token));

        impl = address(new FactionBattleArena());

        proxy =
            address(new ERC1967Proxy(impl, abi.encodeCall(FactionBattleArena.initialize, (config))));

        arena = FactionBattleArena(proxy);

        console.log("Deployed FactionBattleArena to:", address(arena));

        // Register deployment
        vm.serializeAddress(jsonRoot, "TrailblazersBadges", address(s1Token));
        vm.serializeAddress(jsonRoot, "TrailblazersBadgesS2", address(s2Token));
        string memory finalJson =
            vm.serializeAddress(jsonRoot, "FactionBattleArena", address(arena));
        vm.writeJson(finalJson, jsonLocation);

        vm.stopBroadcast();
    }
}
