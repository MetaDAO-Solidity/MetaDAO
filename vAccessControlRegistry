// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts@4.9.0/access/AccessControl.sol";
import "@openzeppelin/contracts@4.9.0/security/Pausable.sol";
import "../../interfaces/core/IVAccessControlRegistry.sol";
contract VAccessControlRegistry is IAccessControlRegistry, AccessControl, Pausable {
	bytes32 public constant GOVERANCE_ROLE = keccak256("GOVERANCE_ROLE");
	bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
	bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
	bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");
	bytes32 public constant SUPPORT_ROLE = keccak256("SUPPORT_ROLE");
	bytes32 public constant FOUNDER_ROLE = keccak256("FOUNDER_ROLE"); 
	bytes32 public constant CO_FOUNDER_ROLE = keccak256("CO_FOUNDER_ROLE"); 
	bytes32 public constant SPONSOR_ROLE = keccak256("SPONSOR_ROLE");
	bytes32 public constant CO_SPONSOR_ROLE = keccak256("CO_SPONSOR_ROLE"); 
	bytes32 public constant SUPER_EVAGENLIST_ROLE = keccak256("SUPER_EVAGENLIST_ROLE"); 
	bytes32 public constant EVAGENLIST_ROLE = keccak256("EVAGENLIST_ROLE"); 
	bytes32 public constant MEDAL_OF_CREATION_ROLE = keccak256("MEDAL_OF_CREATION_ROLE"); 
	bytes32 public constant JOINT_CREATION_MEDAL_ROLE = keccak256("JOINT_CREATION_MEDAL_ROLE");
	bytes32 public constant COMMUNITY_MEDAL_ROLE = keccak256("COMMUNITY_MEDAL_ROLE");	
	bytes32 public constant TEAM_MEDAL_ROLE = keccak256("TEAM_MEDAL_ROLE"); 
	bytes32 public constant IRON_Army_MEDAL_ROLE = keccak256("IRON_Army_MEDAL_ROLE"); 

	address public immutable timelockAddressImmutable;
	address public governanceAddress;
	bool public timelockActivated = false;
	constructor(address _governance, address _timelock) Pausable() {
		governanceAddress = _governance;
		timelockAddressImmutable = _timelock;
		_setupRole(GOVERANCE_ROLE, _governance);
		_setupRole(EMERGENCY_ROLE, _governance);
		_setupRole(SUPPORT_ROLE, _governance);
		_setupRole(TEAM_ROLE, _governance);
		_setupRole(PROTOCOL_ROLE, _governance);
		_setRoleAdmin(GOVERANCE_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(PROTOCOL_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(SUPPORT_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(TEAM_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(EMERGENCY_ROLE, GOVERANCE_ROLE);
		_setupRole(FOUNDER_ROLE, _governance);
		_setupRole(CO_FOUNDER_ROLE, _governance);
		_setupRole(SPONSOR_ROLE, _governance);		
		_setupRole(CO_SPONSOR_ROLE, _governance);
		_setupRole(SUPER_EVAGENLIST_ROLE, _governance);
		_setupRole(EVAGENLIST_ROLE, _governance);
		_setupRole(MEDAL_OF_CREATION_ROLE, _governance);
		_setupRole(JOINT_CREATION_MEDAL_ROLE, _governance);
		_setupRole(COMMUNITY_MEDAL_ROLE, _governance);	
		_setupRole(TEAM_MEDAL_ROLE, _governance);
		_setupRole(IRON_Army_MEDAL_ROLE, _governance);

		
	}


	function flipTimelockDeadmanSwitch() external onlyRole(GOVERANCE_ROLE) {
		require(
			!timelockActivated,
			"VaultAccessControlRegistry: Deadmanswitch already flipped"
		);
		timelockActivated = true;
		emit DeadmanSwitchFlipped();
	}

	function pauseProtocol() external onlyRole(EMERGENCY_ROLE) {
		_pause();
	}

	function unpauseProtocol() external onlyRole(EMERGENCY_ROLE) {
		_unpause();
	}

	function changeGovernanceAddress(address _governanceAddress) external {
		require(
			_governanceAddress != address(0x0),
			"VaultAccessControlRegistry: Governance cannot be null address"
		);
		require(
			msg.sender == governanceAddress,
			"VaultAccessControlRegistry: Only official goverance address can change goverance address"
		);
	
		_revokeRole(GOVERANCE_ROLE, governanceAddress);

		_grantRole(GOVERANCE_ROLE, _governanceAddress);
		governanceAddress = _governanceAddress;
	
		emit GovernanceChange(_governanceAddress);
	}

	function isCallerGovernance(
		address _account
	) external view whenNotPaused returns (bool isGovernance_) {
		isGovernance_ = hasRole(GOVERANCE_ROLE, _account);
	}

	function isCallerEmergency(
		address _account
	) external view whenNotPaused returns (bool isEmergency_) {
		isEmergency_ = hasRole(EMERGENCY_ROLE, _account);
	}

	function isCallerProtocol(
		address _account
	) external view whenNotPaused returns (bool isProtocol_) {
		isProtocol_ = hasRole(PROTOCOL_ROLE, _account);
	}


	function isCallerTeam(
		address _account
	) external view whenNotPaused returns (bool isTeam_) {
		isTeam_ = hasRole(TEAM_ROLE, _account);
	}

	function isCallerSupport(
		address _account
	) external view whenNotPaused returns (bool isSupport_) {
		isSupport_ = hasRole(SUPPORT_ROLE, _account);
	}
	function isProtocolPaused() external view returns (bool isPaused_) {
		isPaused_ = paused();
	}
}
