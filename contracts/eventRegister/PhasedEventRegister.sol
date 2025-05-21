// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title PhasedEventRegister
 * @notice A contract that allows authorized managers to create multi-phase events, manage user registrations per phase,
 *         and track whether a user participated in any or all phases using role-based access control.
 * @dev Utilizes OpenZeppelin's AccessControl for role management. The contract does not hold any Ether.
 */
contract PhasedEventRegister is Ownable2StepUpgradeable, AccessControlUpgradeable {
    bytes32 public constant EVENT_MANAGER_ROLE = keccak256("EVENT_MANAGER_ROLE");

    struct Event {
        uint256 id;
        string name;
        uint256 totalPhases;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => mapping(uint256 => bool)) public phaseOpen;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public registrations;

    event EventCreated(uint256 indexed id, string name);
    event Registered(address indexed registrant, uint256 indexed eventId, uint256 indexed phaseId);
    event Unregistered(address indexed registrant, uint256 indexed eventId, uint256 indexed phaseId);
    event PhaseOpened(uint256 indexed eventId, uint256 indexed phaseId);
    event PhaseClosed(uint256 indexed eventId, uint256 indexed phaseId);

    uint256 private nextEventId;

    /**
     * @notice Initializes the contract and grants roles to the deployer.
     * @dev Grants `DEFAULT_ADMIN_ROLE` and `EVENT_MANAGER_ROLE` to the deployer.
     */
    function initialize() external initializer {
        __Context_init();
        _grantRole(EVENT_MANAGER_ROLE, _msgSender());
        _transferOwnership(_msgSender());
    }

    /**
     * @notice Constructor for compatibility. Grants admin role to deployer.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @notice Grants the EVENT_MANAGER_ROLE to a specified account.
     * @param account The address to be granted the EVENT_MANAGER_ROLE.
     */
    function grantEventManagerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(EVENT_MANAGER_ROLE, account);
    }

    /**
     * @notice Revokes the EVENT_MANAGER_ROLE from a specified account.
     * @param account The address from which the EVENT_MANAGER_ROLE will be revoked.
     */
    function revokeEventManagerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(EVENT_MANAGER_ROLE, account);
    }

    /**
     * @notice Creates a new event with the given name and number of phases.
     * @param _name The name of the event to be created.
     * @param _totalPhases The number of registration phases.
     *
     * Requirements:
     * - Event IDs start from 1.
     * - All phase IDs for this event will be [1.._totalPhases].
     */
    function createEvent(string memory _name, uint256 _totalPhases) external onlyRole(EVENT_MANAGER_ROLE) {
        nextEventId++;
        uint256 eventId = nextEventId;

        events[eventId] = Event({ id: eventId, name: _name, totalPhases: _totalPhases });

        for (uint256 i = 1; i <= _totalPhases; i++) {
            phaseOpen[eventId][i] = true;
            emit PhaseOpened(eventId, i);
        }

        emit EventCreated(eventId, _name);
    }

    /**
     * @notice Opens registrations for a specific phase of an event.
     * @param _eventId The ID of the event.
     * @param _phaseId The phase to be opened.
     */
    function openPhase(uint256 _eventId, uint256 _phaseId) external onlyRole(EVENT_MANAGER_ROLE) {
        _validateIds(_eventId, _phaseId);
        phaseOpen[_eventId][_phaseId] = true;
        emit PhaseOpened(_eventId, _phaseId);
    }

    /**
     * @notice Closes registrations for a specific phase of an event.
     * @param _eventId The ID of the event.
     * @param _phaseId The phase to be closed.
     */
    function closePhase(uint256 _eventId, uint256 _phaseId) external onlyRole(EVENT_MANAGER_ROLE) {
        _validateIds(_eventId, _phaseId);
        phaseOpen[_eventId][_phaseId] = false;
        emit PhaseClosed(_eventId, _phaseId);
    }

    /**
     * @notice Registers the caller for a specific phase of an event.
     * @param _eventId The ID of the event.
     * @param _phaseId The phase to register for.
     */
    function register(uint256 _eventId, uint256 _phaseId) external {
        _validateIds(_eventId, _phaseId);
        require(phaseOpen[_eventId][_phaseId], "Phase closed");

        registrations[_eventId][_phaseId][msg.sender] = block.timestamp;
        emit Registered(msg.sender, _eventId, _phaseId);
    }

    /**
     * @notice Unregisters a user from a specific phase.
     * @param _eventId The ID of the event.
     * @param _phaseId The ID of the phase.
     * @param _user The address of the user to unregister.
     */
    function unregister(uint256 _eventId, uint256 _phaseId, address _user) external onlyRole(EVENT_MANAGER_ROLE) {
        _validateIds(_eventId, _phaseId);
        registrations[_eventId][_phaseId][_user] = 0;
        emit Unregistered(_user, _eventId, _phaseId);
    }

    /**
     * @notice Retrieves the registration status for a user in all phases of an event.
     * @param _eventId The ID of the event.
     * @param _user The address to check.
     * @return registered An array of booleans representing registration status for each phase.
     */
    function getRegistrationStatus(uint256 _eventId, address _user)
        external
        view
        returns (bool[] memory registered)
    {
        require(_eventId > 0 && _eventId <= nextEventId, "Invalid event ID");

        uint256 total = events[_eventId].totalPhases;
        registered = new bool[](total);

        for (uint256 i = 1; i <= total; i++) {
            registered[i - 1] = registrations[_eventId][i][_user] > 0;
        }
    }

    /**
     * @notice Retrieves event details.
     * @param _eventId The ID of the event.
     * @return id Event ID.
     * @return name Event name.
     * @return totalPhases Total number of phases.
     */
    function getEvent(uint256 _eventId)
        external
        view
        returns (uint256 id, string memory name, uint256 totalPhases)
    {
        require(_eventId > 0 && _eventId <= nextEventId, "Invalid event ID");
        Event memory e = events[_eventId];
        return (e.id, e.name, e.totalPhases);
    }

    /**
     * @dev Validates event and phase IDs.
     */
    function _validateIds(uint256 _eventId, uint256 _phaseId) internal view {
        require(_eventId > 0 && _eventId <= nextEventId, "Invalid event ID");
        require(_phaseId > 0 && _phaseId <= events[_eventId].totalPhases, "Invalid phase ID");
    }
}