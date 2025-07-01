// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../../contracts/game-hub/TaikoGameHub.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployTaikoGameHub
 * @dev Script to deploy TaikoGameHub contract with proxy pattern
 * @author Taiko Labs
 */
contract DeployTaikoGameHub is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        TaikoGameHub gameHubImpl = new TaikoGameHub();
        console.log(
            "TaikoGameHub implementation deployed at:",
            address(gameHubImpl)
        );

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            TaikoGameHub.initialize.selector,
            owner
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(gameHubImpl), initData);

        console.log("TaikoGameHub proxy deployed at:", address(proxy));
        console.log("Owner set to:", owner);

        // Verify the deployment
        TaikoGameHub gameHub = TaikoGameHub(address(proxy));
        console.log("TaikoGameHub version:", gameHub.version());
        console.log("TaikoGameHub owner:", gameHub.owner());

        vm.stopBroadcast();
    }
}
