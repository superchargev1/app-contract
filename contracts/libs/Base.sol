// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./IBookie.sol";

abstract contract Base is Initializable {
    using SignatureChecker for address;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IBookie bookie;
    bool paused;

    modifier onlyRole(bytes32 role) {
        // AMIN_ROLE - also can do other roles
        if (
            !bookie.hasRole(role, msg.sender) &&
            !bookie.hasRole(ADMIN_ROLE, msg.sender)
        ) revert("Missing Role");
        _;
    }
    modifier onlyFrom(bytes32 name) {
        if (bookie.getAddress(name) != msg.sender) revert("Invalid Caller");
        _;
    }
    modifier onlyFromIn(bytes32[] memory names) {
        bool isValid;
        for (uint256 i; isValid == false && i < names.length; i++) {
            if (bookie.getAddress(names[i]) == msg.sender) isValid = true;
        }
        if (!isValid) revert("Invalid Caller");
        _;
    }

    modifier whenActive() {
        require(paused == false);
        _;
    }

    function __Base_init(address bookieAddress) internal onlyInitializing {
        bookie = IBookie(bookieAddress);
    }

    function setBookie(address bookieAddress) external onlyRole(ADMIN_ROLE) {
        bookie = IBookie(bookieAddress);
    }

    function setPaused(bool isPaused) external onlyRole(ADMIN_ROLE) {
        paused = isPaused;
    }

    function isValidSignature(
        address _address,
        bytes32 _hash,
        bytes memory _signature
    ) public view returns (bool) {
        return _address.isValidSignatureNow(_hash, _signature);
    }
}
