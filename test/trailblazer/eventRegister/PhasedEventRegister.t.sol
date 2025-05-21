// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/src/Test.sol";
import { PhasedEventRegister } from "../../../contracts/eventRegister/PhasedEventRegister.sol";

contract PhasedEventRegisterTest is Test {
    PhasedEventRegister public reg;
    address public owner = address(0x1);
    address public manager = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    function setUp() public {
        vm.startPrank(owner);
        reg = new PhasedEventRegister();
        reg.initialize();
        reg.grantEventManagerRole(manager);
        vm.stopPrank();
    }

    function testDeployerHasAdminRole() public view {
        assertTrue(reg.hasRole(reg.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testManagerHasEventManagerRole() public view {
        assertTrue(reg.hasRole(reg.EVENT_MANAGER_ROLE(), manager));
    }

    function testAdminCanGrantAndRevokeEventManagerRole() public {
        vm.startPrank(owner);
        reg.grantEventManagerRole(user1);
        assertTrue(reg.hasRole(reg.EVENT_MANAGER_ROLE(), user1));
        reg.revokeEventManagerRole(user1);
        assertFalse(reg.hasRole(reg.EVENT_MANAGER_ROLE(), user1));
        vm.stopPrank();
    }

    function testCreateEventAndPhases() public {
        uint256 phases = 2;
        vm.startPrank(manager);
        reg.createEvent("Test Event", phases);
        vm.stopPrank();
        (uint256 id, string memory name, uint256 totalPhases) = reg.getEvent(1);
        assertEq(id, 1);
        assertEq(name, "Test Event");
        assertEq(totalPhases, 2);
    }

    function testRegisterAndUnregister() public {
        vm.startPrank(manager);
        reg.createEvent("Test Event", 1);
        reg.openPhase(1, 1); // Open phase before registration
        vm.stopPrank();

        vm.startPrank(user1);
        reg.register(1, 1);
        vm.stopPrank();

        bool[] memory status = reg.getRegistrationStatus(1, user1);
        assertTrue(status[0]);

        vm.startPrank(manager);
        reg.unregister(1, 1, user1);
        vm.stopPrank();

        status = reg.getRegistrationStatus(1, user1);
        assertFalse(status[0]);
    }

    function testPhaseOpenClose() public {
        vm.startPrank(manager);
        reg.createEvent("Test Event", 1);
        reg.closePhase(1, 1);
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert();
        reg.register(1, 1);
        vm.stopPrank();
        vm.startPrank(manager);
        reg.openPhase(1, 1);
        vm.stopPrank();
        vm.startPrank(user1);
        reg.register(1, 1);
        vm.stopPrank();
    }

    function testOnlyManagerCanCreateEvent() public {
        vm.startPrank(user1);
        vm.expectRevert();
        reg.createEvent("Test Event", 1);
        vm.stopPrank();
    }

    function testInvalidPhaseId() public {
        vm.startPrank(manager);
        reg.createEvent("Test Event", 1);
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert();
        reg.register(1, 2); // phase 2 does not exist
        vm.stopPrank();
    }
}
