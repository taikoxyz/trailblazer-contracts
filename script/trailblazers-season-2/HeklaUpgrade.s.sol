// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { UtilsScript } from "./Utils.s.sol";
import { Script, console } from "forge-std/src/Script.sol";
import { BadgeRecruitment } from "../../contracts/trailblazers-season-2/BadgeRecruitment.sol";
import { BadgeRecruitmentV2 } from "../../contracts/trailblazers-season-2/BadgeRecruitmentV2.sol";

contract HeklaUpgradeScript is Script {
    UtilsScript public utils;
    string public jsonLocation;
    uint256 public deployerPrivateKey;

    address recruitmentAddress = 0x4BB626aA38F3C0884b4f3D7D4051124Ce4160225;
    BadgeRecruitmentV2 public recruitmentV2;

    function setUp() public {
        utils = new UtilsScript();
        utils.setUp();

        jsonLocation = utils.getContractJsonLocation();
        deployerPrivateKey = utils.getPrivateKey();
    }

    function run() public {
        /*
        vm.startBroadcast(deployerPrivateKey);
        recruitmentV1 = BadgeRecruitment(recruitmentAddress);

        recruitmentV1.upgradeToAndCall(
        address(new BadgeRecruitmentV2()), abi.encodeCall(BadgeRecruitmentV2.version, ())
        );

        recruitmentV2 = BadgeRecruitmentV2(address(recruitmentV1));

        console.log("Upgraded BadgeRecruitmentV2 to:", address(recruitmentV2));*/

        // assign permission to korbi's hekla address as an owner:

        vm.startBroadcast(deployerPrivateKey);
        recruitmentV2 = BadgeRecruitmentV2(recruitmentAddress);

        recruitmentV2.grantRole(
            recruitmentV2.DEFAULT_ADMIN_ROLE(), 0xFE5124f99f544a84C3C6D0A26339a04937cD2Ff4
        );
    }
}
