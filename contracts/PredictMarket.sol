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
    uint8 status;
    uint40 price;
    uint88 amount;
    uint88 position;
    //second block
    uint256 openTime;
    //third block
    uint256 outcomeId;
}

contract PredictMarket is OwnableUpgradeable, Base {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    //event status
    uint8 public constant EVENT_STATUS_POOL_INITIALIZE = 1;
    uint8 public constant EVENT_STATUS_OPEN = 2;
    uint8 public constant EVENT_STATUS_CLOSED = 3;
    uint8 public constant EVENT_STATUS_CANCEL = 4;

    //position status
    uint8 public constant POSITION_STATUS_INITIALIZE = 1;
    uint8 public constant POSITION_STATUS_OPEN = 2;
    uint8 public constant POSITION_STATUS_CLOSE = 3;

    event EventCreated(uint40 eventId);
    event EventOpen(uint40 eventId);

    struct PredictStorage {
        uint40 boost;
        uint256 initializeTime;
        uint256 eventCount;
        uint256 lastPosId;
        mapping(uint40 => Event) events;
        mapping(uint256 => Position) positions;
        mapping(uint256 => uint88) totalOcVolume;
        mapping(uint40 => uint88) totalEventVolume;
        mapping(uint40 => uint88) totalEventVolumeInitial;
        mapping(uint256 => uint88) totalOcVolumeInitial;
        mapping(uint256 => bool) isOutcomeWinner;
        mapping(uint40 => uint88) totalWinEvent;
        mapping(uint40 => uint88) totalLostEvent;
        Credit credit;
    }

    // keccak256(abi.encode(uint256(keccak256("supercharge.storage.predictmarket")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PredictStorageLocation =
        0xa1ac3d3fe1e76bceced0444d5b3228772613774f50f0e5c8d91d6495c9028000;

    function _getOwnStorage() private pure returns (PredictStorage storage $) {
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
        PredictStorage storage $ = _getOwnStorage();
        $.credit = Credit(creditContractAddress);
        $.initializeTime = 30 * 60;
        //boost is percentage
        //for example 10% boost
        $.boost = 10;
    }

    function createEvent(
        uint40 eventId,
        uint256 startTime,
        uint256 expireTime,
        uint40[] memory marketIds
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require($.events[eventId].marketHash == 0, "Event Already Existed");

        $.events[eventId].status = EVENT_STATUS_POOL_INITIALIZE;
        $.events[eventId].startTime = startTime;
        $.events[eventId].expireTime = expireTime;
        $.events[eventId].marketHash = uint256(
            keccak256(abi.encodePacked(marketIds))
        );
        $.eventCount++;
        emit EventCreated(eventId);
    }

    function buyPosition(uint88 amount, uint256 outcome) external {
        PredictStorage storage $ = _getOwnStorage();
        require(amount <= $.credit.getCredit(msg.sender), "Not enough credit");
        //check condition
        uint40 eventId = uint40(outcome >> 64);
        require(
            $.events[eventId].status != EVENT_STATUS_CLOSED &&
                $.events[eventId].status != EVENT_STATUS_CANCEL,
            "Event closed"
        );
        require(
            block.timestamp <= $.events[eventId].expireTime,
            "Event expired"
        );
        if ($.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE) {
            $.lastPosId++;
            $.totalEventVolume[eventId] += amount;
            $.totalOcVolume[outcome] += amount;
            $.totalOcVolumeInitial[outcome] += amount;
            Position memory newPos = Position(
                POSITION_STATUS_INITIALIZE,
                0,
                amount,
                0,
                block.timestamp,
                outcome
            );
            $.positions[$.lastPosId] = newPos;
            //transfer credit
            $.credit.predicMarketTransferFrom(msg.sender, amount, 0);
        } else if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            $.lastPosId++;
            //calculate the price and position
            $.totalEventVolume[eventId] += uint88(amount);
            $.totalOcVolume[outcome] += uint88(amount);
            //calculate the price
            uint40 price = uint40(
                $.totalEventVolume[eventId] / $.totalOcVolume[outcome]
            );
            //calculate the position
            uint88 position = uint88(price * amount);
            Position memory newPos = Position(
                POSITION_STATUS_OPEN,
                price,
                amount,
                position,
                block.timestamp,
                outcome
            );
            $.positions[$.lastPosId] = newPos;
            //transfer credit
            $.credit.predicMarketTransferFrom(msg.sender, amount, 0);
        }
    }

    function sellPosition(uint256 posId) external {
        PredictStorage storage $ = _getOwnStorage();
        (
            uint256 _outcomeId,
            uint40 _price,
            uint88 _amount,
            uint88 _position,
            ,
            uint8 status
        ) = _getPosition(posId);
        //calculate the next price if sell this position
        uint40 eventId = uint40(_outcomeId >> 64);
        require(
            $.events[eventId].status == EVENT_STATUS_OPEN ||
                $.events[eventId].status == EVENT_STATUS_CLOSED ||
                $.events[eventId].status == EVENT_STATUS_CANCEL,
            "Event in initialize"
        );
        uint88 amount = _calPositionReturnAmount(posId);
        if (amount == 0) {
            revert("Position lost");
        }
        //transfer credit
        $.credit.predicMarketTransfer(msg.sender, amount, 0);
    }

    ////////////////////
    /////// ADMIN //////
    ////////////////////
    function resolveInitializePool(
        uint40 eventId
    ) external onlyRole(RESOLVER_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require(
            $.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE,
            "Event not open"
        );
        //calculate the price and position of each posIds
        $.events[eventId].status = EVENT_STATUS_OPEN;
    }

    function resolveEvent(
        uint40 eventId,
        uint40[] memory marketIds,
        uint40[] memory winnerOutcomes,
        uint40[] memory loserOutcomes
    ) external onlyRole(RESOLVER_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require(
            $.events[eventId].marketHash ==
                uint256(keccak256(abi.encodePacked(marketIds))),
            "Invalid marketIds"
        );
        require(
            $.events[eventId].status == EVENT_STATUS_OPEN,
            "Invalid event status"
        );
        require(winnerOutcomes.length == marketIds.length, "Invalid Input");
        //calculate the winner
        for (uint i = 0; i < winnerOutcomes.length; i++) {
            $.totalWinEvent[eventId] += $.totalOcVolume[winnerOutcomes[i]];
            $.isOutcomeWinner[winnerOutcomes[i]] = true;
        }
        //calculate the loser
        for (uint i = 0; i < loserOutcomes.length; i++) {
            $.totalLostEvent[eventId] += $.totalOcVolume[loserOutcomes[i]];
            $.isOutcomeWinner[loserOutcomes[i]] = false;
        }
        $.events[eventId].status = EVENT_STATUS_CLOSED;
    }

    ////////////////////
    /////// GETTER /////
    ////////////////////
    function getPosition(
        uint256 posId
    ) external view returns (uint256, uint40, uint88, uint88, uint256, uint8) {
        return _getPosition(posId);
    }

    function getEventData(uint40 eventId) external view returns (Event memory) {
        PredictStorage storage $ = _getOwnStorage();
        return $.events[eventId];
    }

    ////////////////////
    /////// SETTER /////
    ////////////////////
    function setBoost(uint40 newBoost) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.boost = newBoost;
    }

    function setInitializeTime(
        uint256 newInitializeTime
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.initializeTime = newInitializeTime;
    }

    ////////////////////
    /////// PRIVATE ////
    ////////////////////
    function _calPositionReturnAmount(uint256 posId) private returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        Position memory pos = $.positions[posId];
        uint40 eventId = uint40(pos.outcomeId >> 64);
        uint88 amount;
        //calculate the amount
        if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            $.totalEventVolume[eventId] -= pos.amount;
            $.totalOcVolume[pos.outcomeId] -= pos.amount;
            //calculate the amount must transfer to user
            amount = uint88(
                (pos.position * $.totalOcVolume[pos.outcomeId]) /
                    $.totalEventVolume[eventId]
            );
        } else if ($.events[eventId].status == EVENT_STATUS_CLOSED) {
            //calculate the price after event close
            uint88 totalWin = $.totalWinEvent[eventId];
            uint88 totalLost = $.totalLostEvent[eventId];
            if (!$.isOutcomeWinner[pos.outcomeId]) {
                amount = 0;
            } else {
                uint88 totalVolume = totalWin + totalLost;
                uint88 price = totalVolume / totalWin;
                //calculate the amount must transfer to user
                amount = uint88(pos.position * price);
            }
        } else if ($.events[eventId].status == EVENT_STATUS_CANCEL) {
            amount = pos.amount;
        }
        return amount;
    }

    function _getPosition(
        uint256 posId
    ) private view returns (uint256, uint40, uint88, uint88, uint256, uint8) {
        PredictStorage storage $ = _getOwnStorage();
        Position memory pos = $.positions[posId];
        uint40 eventId = uint40(pos.outcomeId >> 64);
        console.log("eventId: ", $.events[eventId].status);
        if ($.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE) {
            console.log("run here 1");
            return (pos.outcomeId, 0, pos.amount, 0, pos.openTime, pos.status);
        } else {
            if (pos.status == POSITION_STATUS_INITIALIZE) {
                console.log("run here 2");
                //calculate the price
                uint40 price = uint40(
                    $.totalEventVolumeInitial[eventId] /
                        $.totalOcVolumeInitial[pos.outcomeId]
                );
                //calculate the position
                uint88 position = uint88(
                    (price * pos.amount * (100 + $.boost)) / 100
                );
                return (
                    pos.outcomeId,
                    price,
                    pos.amount,
                    position,
                    pos.openTime,
                    pos.status
                );
            } else {
                return (
                    pos.outcomeId,
                    pos.price,
                    pos.amount,
                    pos.position,
                    pos.openTime,
                    pos.status
                );
            }
        }
    }
}
