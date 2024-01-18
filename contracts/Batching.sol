// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./X1000.sol";

import "hardhat/console.sol";

struct OpenPositionParams {
    address account;
    bytes32 poolId;
    uint256 value;
    uint256 leverage;
    uint256 price;
    bool isLong;
    uint256 plId;
}

contract Batching is OwnableUpgradeable, Base {
    bytes32 public constant X1000_BATCHER_ROLE =
        keccak256("X1000_BATCHER_ROLE");
    struct BatchingStorage {
        X1000 x1000;
    }

    //keccak256(abi.encode(uint256(keccak256("goal3.storage.Batching")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BatchingStorageLocation =
        0xc05c5f10a19e05ef10e0a1de72aa3919058141c9f7c29ca3afb777f4a67d5c00;

    event OpenPositionFailed(uint256 pLId);

    function _getOwnStorage() private pure returns (BatchingStorage storage $) {
        assembly {
            $.slot := BatchingStorageLocation
        }
    }

    function initialize(
        address bookieAddress,
        address x1000ContractAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __Base_init(bookieAddress);

        BatchingStorage storage $ = _getOwnStorage();
        $.x1000 = X1000(x1000ContractAddress);
    }

    function openBatchPosition(
        OpenPositionParams[] memory positions
    ) external onlyRole(X1000_BATCHER_ROLE) {
        BatchingStorage storage $ = _getOwnStorage();
        bool[] memory executionResults = new bool[](positions.length);
        for (uint i = 0; i < positions.length; i++) {
            if (positions[i].isLong) {
                try
                    $.x1000.openLongPosition(
                        positions[i].account,
                        positions[i].poolId,
                        positions[i].value,
                        positions[i].leverage,
                        positions[i].price
                    )
                {
                    // Thành công, không làm gì cả
                    executionResults[i] = true;
                } catch Error(string memory errorMessage) {
                    // Xử lý lỗi nếu cần thiết
                    executionResults[i] = false;
                } catch (bytes memory) {
                    // Xử lý lỗi nếu cần thiết
                    executionResults[i] = false;
                }
            } else {
                try
                    $.x1000.openShortPosition(
                        positions[i].account,
                        positions[i].poolId,
                        positions[i].value,
                        positions[i].leverage,
                        positions[i].price
                    )
                {
                    // Thành công, không làm gì cả
                    executionResults[i] = true;
                } catch Error(string memory errorMessage) {
                    // Xử lý lỗi nếu cần thiết
                    executionResults[i] = false;
                } catch (bytes memory) {
                    // Xử lý lỗi nếu cần thiết
                    executionResults[i] = false;
                }
            }
        }
        for (uint i = 0; i < executionResults.length; i++) {
            if (!executionResults[i]) {
                emit OpenPositionFailed(positions[i].plId);
            }
        }
    }
}
