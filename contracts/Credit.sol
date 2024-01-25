// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IERC20Extend.sol";
import "hardhat/console.sol";
import "./libs/Base.sol";

struct CreditConfig {
    address creditToken;
    uint256 minTopupAmount;
    uint256 maxWithdrawAmount;
}

contract Credit is OwnableUpgradeable, Base {
    uint64 public constant WEI6 = 10 ** 6; // base for calculation
    bytes32 public constant X1000V2 = keccak256("X1000V2");
    event Topup(address from, address to, uint256 amount);
    event TopupSystem(address from, uint256 amount);
    event Withdraw(address from, address to, uint256 amount);
    event CreditTo(address account, uint256 amount);
    event CreditFrom(address account, uint256 amount);
    event UpdateMintTopupAmount(uint256 oldValue, uint256 newValue);
    event UpdateMaxWithdrawAmount(uint256 oldValue, uint256 newValue);

    error ErrorMinTopupAmount(uint256 minAmount);
    error ErrorMaxWithdrawAmount(uint256 maxAmount);

    struct CreditStorage {
        CreditConfig config;
        mapping(address => uint256) credits;
        uint256 platform;
        uint256 fee;
        uint256 totalTopup;
        uint256 totalWithdraw;
    }

    // keccak256(abi.encode(uint256(keccak256("x1000.storage.credit")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CreditStorageLocation =
        0x61ac7db12115f048078a0d98a419d1b6e0364eec44a215b3bd04f8734bdacc00;

    function _getOwnStorage() private pure returns (CreditStorage storage $) {
        assembly {
            $.slot := CreditStorageLocation
        }
    }

    function initialize(
        address bookieAddress,
        address creditToken,
        uint256 initMinTopupAmount,
        uint256 initMaxWithdrawAmount
    ) public initializer {
        __Ownable_init(msg.sender);
        __Base_init(bookieAddress);
        CreditStorage storage $ = _getOwnStorage();
        $.config.creditToken = creditToken;
        // init
        $.config.minTopupAmount = initMinTopupAmount;
        $.config.maxWithdrawAmount = initMaxWithdrawAmount;
    }

    //////////////////
    /////// USER /////
    //////////////////

    // Topup credit for user
    // credit into topupBalances
    function topup(uint256 amount) external {
        topupTo(msg.sender, amount);
    }

    function topupTo(address account, uint256 amount) public {
        CreditStorage storage $ = _getOwnStorage();
        if ($.config.minTopupAmount > amount) {
            revert ErrorMinTopupAmount($.config.minTopupAmount);
        }
        IERC20Extend creditToken = IERC20Extend($.config.creditToken);
        // transfer credit
        creditToken.transferFrom(msg.sender, address(this), amount);
        uint256 creditAmount = convertErc20ToCredit(amount);
        // then credit for account
        $.credits[account] += creditAmount;
        $.totalTopup += creditAmount;
        emit Topup(msg.sender, account, creditAmount);
    }

    function convertErc20ToCredit(uint256 amount) private returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        IERC20Extend creditToken = IERC20Extend($.config.creditToken);
        uint8 decimals = creditToken.decimals();
        // transfer credit
        return (amount / (10 ** decimals)) * WEI6;
    }

    function convertCreditToErc20(uint256 amount) private returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        IERC20Extend creditToken = IERC20Extend($.config.creditToken);
        uint8 decimals = creditToken.decimals();
        // transfer credit
        return (amount / WEI6) * (10 ** decimals);
    }

    // Withdraw credit into zkusd
    // debit from withdrawBalances
    function withdraw(uint256 amount) external {
        withdrawTo(msg.sender, amount);
    }

    function withdrawTo(address account, uint256 amount) public {
        CreditStorage storage $ = _getOwnStorage();
        require($.credits[msg.sender] >= amount, "Insufficient Credit");
        if ($.config.maxWithdrawAmount < amount) {
            revert ErrorMaxWithdrawAmount($.config.maxWithdrawAmount);
        }

        $.credits[account] -= amount;
        $.totalWithdraw += amount;
        IERC20Extend creditToken = IERC20Extend($.config.creditToken);
        // transfer credit
        uint256 erc20Amount = convertCreditToErc20(amount);
        creditToken.transfer(account, erc20Amount);
        emit Withdraw(msg.sender, account, amount);
    }

    function topupSystem(uint256 amount) external {
        CreditStorage storage $ = _getOwnStorage();
        IERC20Extend creditToken = IERC20Extend($.config.creditToken);
        // transfer credit
        uint256 creditAmount = convertErc20ToCredit(amount);
        creditToken.transferFrom(msg.sender, address(this), amount);
        // then credit for account
        $.platform += creditAmount;
        bytes32 x = keccak256(
            abi.encode(uint256(keccak256("goal3.storage.X1000V4")) - 1)
        ) & ~bytes32(uint256(0xff));
        console.logBytes32(x);

        emit TopupSystem(msg.sender, creditAmount);
    }

    ////////////////////
    /////// ADMIN /////
    ////////////////////
    function transfer(
        address account,
        uint256 amount,
        uint256 fee
    ) external onlyFrom(X1000V2) {
        CreditStorage storage $ = _getOwnStorage();
        $.credits[account] += amount;
        $.fee += fee;
        $.platform -= (amount + fee);
    }

    function transferFrom(
        address account,
        uint256 amount,
        uint256 fee
    ) external onlyFrom(X1000V2) {
        CreditStorage storage $ = _getOwnStorage();
        require(amount > fee, "Invalid amount and fee");
        $.credits[account] -= amount;
        $.fee += fee;
        $.platform += (amount - fee);
    }

    ////////////////////
    /////// SETTER /////
    ////////////////////
    function setCredit(
        address account,
        uint256 amount
    ) external onlyFrom(X1000V2) {
        CreditStorage storage $ = _getOwnStorage();
        $.credits[account] = amount;
        emit CreditTo(account, amount);
    }

    function setFee(uint256 amount) external onlyFrom(X1000V2) {
        CreditStorage storage $ = _getOwnStorage();
        $.fee = amount;
    }

    function setPlatform(uint256 amount) external onlyFrom(X1000V2) {
        CreditStorage storage $ = _getOwnStorage();
        $.platform = amount;
    }

    function setMinTopupAmount(
        uint256 newMinTopupAmount
    ) external onlyRole(ADMIN_ROLE) {
        CreditStorage storage $ = _getOwnStorage();
        uint256 oldValue = $.config.minTopupAmount;
        $.config.minTopupAmount = newMinTopupAmount;
        emit UpdateMintTopupAmount(oldValue, newMinTopupAmount);
    }

    function setMaxWithdrawAmount(
        uint256 newMaxWithdrawAmount
    ) external onlyRole(ADMIN_ROLE) {
        CreditStorage storage $ = _getOwnStorage();
        uint256 oldValue = $.config.maxWithdrawAmount;
        $.config.maxWithdrawAmount = newMaxWithdrawAmount;
        emit UpdateMaxWithdrawAmount(oldValue, newMaxWithdrawAmount);
    }

    ////////////////////
    /////// GETTER /////
    ////////////////////
    function getFee() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.fee;
    }

    function getCredit(address account) external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.credits[account];
    }

    function totalTopup() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.totalTopup;
    }

    function totalWithdraw() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.totalWithdraw;
    }

    function platformCredit() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.platform;
    }

    function minTopupAmount() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.config.minTopupAmount;
    }

    function maxWithdrawAmount() external view returns (uint256) {
        CreditStorage storage $ = _getOwnStorage();
        return $.config.maxWithdrawAmount;
    }
}
