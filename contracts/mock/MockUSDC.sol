// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    address _owner;
    mapping(address => bool) _transferables;

    event TransferableUpdate(address account, bool oldValue, bool newValue);

    constructor(uint256 initialSupply) ERC20("USDC", "USDC") {
        _owner = msg.sender;
        _transferables[msg.sender] = true;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        require(_transferables[msg.sender], "Untransferable");
        super._update(from, to, value);
    }

    function setTransferable(address account, bool value) external {
        require(msg.sender == _owner, "Owner Only");
        emit TransferableUpdate(account, _transferables[account], value);
        _transferables[account] = value;
    }
}
