// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "hardhat/console.sol";

contract X1000 is Initializable, OwnableUpgradeable, AccessControlUpgradeable {
    struct Config {
        uint256 gap;
        mapping(uint8 => uint64) poolLevels; // pool level => size, maximum WEI6 => full size
        uint256 leverage;
    }

    struct Credit {
        mapping(address => uint256) balances;
        uint256 total;
        uint256 platform;
        uint256 fee;
    }

    struct Position {
        bytes32 poolId;
        uint8 ptype;
        uint8 status;
        uint64 amount;
        uint32 leverage;
        uint64 size;
        uint88 openPrice;
        uint88 atPrice;
        uint88 liqPrice;
        uint88 closePrice;
        address user;
    }

    struct Pool {
        uint8 level; // pool level
        uint64 lpos; // total open Long Position
        uint64 spos; // total open Short Position
        uint256 lvalue; // open long value
        uint256 svalue; // open short value
    }

    function initialize() public initializer {}
}
