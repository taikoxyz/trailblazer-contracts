// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { UtilsScript } from "../trailblazers-season-2/Utils.s.sol";
import { Script, console } from "forge-std/src/Script.sol";
import { Merkle } from "murky/Merkle.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TrailblazersBadges } from "../../contracts/trailblazers-badges/TrailblazersBadges.sol";
import { IMinimalBlacklist } from "@taiko/blacklist/IMinimalBlacklist.sol";

import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV10.sol";
import "../../contracts/trailblazers-season-4/TrailblazersS1BadgesV11.sol";

contract UpgradeS1BadgesV11 is Script {
    UtilsScript public utils;
    string public jsonLocation;
    uint256 public deployerPrivateKey;
    address public deployerAddress;
    // hekla
    //address public s1TokenAddress = 0xEB310b20b030e9c227Ac23e0A39FE6a6e09Ba755;
    // mainnet
    address public s1TokenAddress = 0xa20a8856e00F5ad024a55A663F06DCc419FFc4d5;

    TrailblazersBadgesV11 public token;

    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();

        jsonLocation = utils.getContractJsonLocation();
        deployerPrivateKey = utils.getPrivateKey();
        deployerAddress = utils.getAddress();
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TrailblazersBadgesV10 tokenV10 = TrailblazersBadgesV10(s1TokenAddress);

        tokenV10.upgradeToAndCall(
            address(new TrailblazersBadgesV11()), abi.encodeCall(TrailblazersBadgesV11.version, ())
        );

        token = TrailblazersBadgesV11(address(tokenV10));

        console.log("Upgraded TrailblazersBadgesV11 on:", address(token));
    }
}
