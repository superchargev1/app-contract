// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Credit.sol";
import "./libs/Base.sol";
import "hardhat/console.sol";

struct Event {
    //first block
    uint88 volume;
    uint88 totalPosition;
    uint8 status;
    //second block;
    uint256 startTime;
    //third block;
    uint256 expireTime;
    //fourth block;
    uint256 marketHash;
}

struct Position {
    //first block;
    uint40 outcomeId;
    uint40 price;
    uint88 amount;
    uint88 position;
    //second block
    uint256 openTime;
    //third block
    uint8 status;
}

contract PredicMarket is OwnableUpgradeable, Base {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    //event status
    uint8 public constant EVENT_STATUS_OPEN = 1;
    uint8 public constant EVENT_STATUS_POOL_INITIALIZE = 2;
    uint8 public constant EVENT_STATUS_CLOSED = 3;
    uint8 public constant EVENT_STATUS_CANCEL = 4;

    //position status
    uint8 public constant POSITION_STATUS_OPEN = 1;
    uint8 public constant POSITION_STATUS_CLOSE = 2;

    event EventCreated(uint40 eventId);

    struct PredicStorage {
        uint256 initializeTime;
        uint256 eventCount;
        uint256 lastPosId;
        mapping(uint40 => Event) events;
        mapping(uint256 => Position) positions;
        mapping(uint40 => uint88) totalOcVolume;
        mapping(uint40 => uint88) totalOcPosition;
        Credit credit;
    }

    // keccak256(abi.encode(uint256(keccak256("supercharge.storage.predictmarket")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PredictStorageLocation =
        0xa1ac3d3fe1e76bceced0444d5b3228772613774f50f0e5c8d91d6495c9028000;

    function _getOwnStorage() private pure returns (PredicStorage storage $) {
        assembly {
            $.slot := PredictStorageLocation
        }
    }

    function initialize(
        address bookieAddress,
        address creditContractAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __Base_init(bookieAddress);
        PredicStorage storage $ = _getOwnStorage();
        $.credit = Credit(creditContractAddress);
        $.initializeTime = 30 * 60;
    }

    function createEvent(
        uint40 eventId,
        uint256 startTime,
        uint256 expireTime,
        uint40[] memory marketIds
    ) external onlyRole(OPERATOR_ROLE) {
        PredicStorage storage $ = _getOwnStorage();
        require($.events[eventId].marketHash == 0, "Event Already Existed");

        $.events[eventId].status = EVENT_STATUS_OPEN;
        $.events[eventId].startTime = startTime;
        $.events[eventId].expireTime = expireTime;
        $.events[eventId].marketHash = uint256(
            keccak256(abi.encodePacked(marketIds))
        );
        $.eventCount++;
        emit EventCreated(eventId);
    }

    function buyPosition(uint256 amount, uint256 outcome) external {
        PredicStorage storage $ = _getOwnStorage();
        //check condition
        uint40 eventId = uint40(outcome >> 64);
        require(
            $.events[eventId].status != EVENT_STATUS_CLOSED &&
                $.events[eventId].status != EVENT_STATUS_CANCEL,
            "Event closed"
        );

        if ($.events[eventId].status == EVENT_STATUS_OPEN) {} else if (
            $.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE
        ) {}
    }

    function sellPosition() external {}
}
