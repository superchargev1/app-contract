// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract Bookie is Initializable, OwnableUpgradeable, AccessControlUpgradeable {
    // new role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // bytes32 public constant BOOKMAKER_ROLE = keccak256("BOOKMAKER_ROLE");
    mapping(bytes32 => address) addresses;

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setAddress(
        bytes32 name,
        address contractAddress
    ) external onlyRole(ADMIN_ROLE) {
        addresses[name] = contractAddress;
    }

    function getAddress(bytes32 name) external view returns (address) {
        return addresses[name];
    }
}
