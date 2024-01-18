//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

interface IBookie {
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    function getAddress(bytes32 name) external view returns (address);
}
