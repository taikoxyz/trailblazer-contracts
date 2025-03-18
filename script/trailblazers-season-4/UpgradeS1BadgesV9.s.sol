// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { UtilsScript } from "../trailblazers-season-2/Utils.s.sol";
import { Script, console } from "forge-std/src/Script.sol";
import { Merkle } from "murky/Merkle.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TrailblazersBadges } from "../../contracts/trailblazers-badges/TrailblazersBadges.sol";
import { IMinimalBlacklist } from "@taiko/blacklist/IMinimalBlacklist.sol";

import "../../contracts/trailblazers-season-2/TrailblazersS1BadgesV8.sol";
import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV9.sol";

contract UpgradeS1BadgesV9 is Script {
    UtilsScript public utils;
    string public jsonLocation;
    uint256 public deployerPrivateKey;
    address public deployerAddress;
    // hekla
    //address public s1TokenAddress = 0xEB310b20b030e9c227Ac23e0A39FE6a6e09Ba755;
    // mainnet
     address public s1TokenAddress = 0xa20a8856e00F5ad024a55A663F06DCc419FFc4d5;

    TrailblazersBadgesV9 public token;

    uint256 public SEASON_2_END_TS = 1_734_350_400;
    uint256 public SEASON_3_END_TS = 1_742_212_800;
uint256 public SEASON_4_END_TS = 1_750_075_200;

    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();

        jsonLocation = utils.getContractJsonLocation();
        deployerPrivateKey = utils.getPrivateKey();
        deployerAddress = utils.getAddress();
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TrailblazersBadgesV8 tokenV8 = TrailblazersBadgesV8(s1TokenAddress);

        tokenV8.upgradeToAndCall(
            address(new TrailblazersBadgesV9()), abi.encodeCall(TrailblazersBadgesV9.version, ())
        );

        token = TrailblazersBadgesV9(address(tokenV8));

        console.log("Upgraded TrailblazersBadgesV9 on:", address(token));

        // apply the season timestamps
        token.setSeasonEndTimestamp(2, SEASON_2_END_TS);
        token.setSeasonEndTimestamp(3, SEASON_3_END_TS);
        token.setSeasonEndTimestamp(4, SEASON_4_END_TS);
        console.log("Set season end timestamps");
    }
}
