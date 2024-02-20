// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
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
    uint256 threshold;
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
    address account;
}

struct Ticket {
    //first block
    uint88 amount;
    uint88 positionAmount;
    bool isFirstSell;
}

contract PredictMarket is OwnableUpgradeable, Base {
    using ECDSA for bytes32;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant BOOKER_ROLE = keccak256("BOOKER_ROLE");
    //event status
    uint8 public constant EVENT_STATUS_POOL_INITIALIZE = 1;
    uint8 public constant EVENT_STATUS_OPEN = 2;
    uint8 public constant EVENT_STATUS_CLOSED = 3;
    uint8 public constant EVENT_STATUS_CANCEL = 4;

    //position status
    uint8 public constant POSITION_STATUS_INITIALIZE = 1;
    uint8 public constant POSITION_STATUS_OPEN = 2;
    uint8 public constant POSITION_STATUS_CLOSE = 3;

    uint256 public constant WEI6 = 10 ** 6;

    event EventCreated(uint40 eventId);
    event EventOpen(uint40 eventId);
    event TicketBuy(
        uint88 amount,
        uint256 outcome,
        address account,
        uint88 positionAmount,
        uint256 posId,
        uint256 ticketId,
        uint256 fee
    );
    event TicketSell(
        uint256 ticketId,
        uint88 posAmount,
        uint88 returnAmount,
        address account,
        uint256 fee,
        uint88 posLeft
    );
    event EventResolveInitialize(uint40 eventId);
    event EventResolved(uint40 eventId);

    struct PredictStorage {
        uint256 initializeTime;
        uint256 lastPosId;
        uint256 systemPnlFee;
        mapping(uint40 => Event) events;
        mapping(uint256 => Position) positions;
        //tracking the total outcomeVolume and eventVolume
        mapping(uint256 => uint88) totalOcVolume;
        mapping(uint40 => uint88) totalEventVolume;
        //tracking the total outcomeVolume and eventVolume when event in initialize time
        mapping(uint40 => uint88) totalEventVolumeInitial;
        mapping(uint256 => uint88) totalOcVolumeInitial;
        //tracking the outcome which is winner or loser
        mapping(uint256 => bool) isOutcomeWinner;
        //total win and lost and pnlFee when event closed
        mapping(uint40 => uint88) totalWinEvent;
        mapping(uint40 => uint88) totalLostEvent;
        mapping(uint40 => uint88) totalPnlFee;
        //tickets
        mapping(uint256 => Ticket) tickets;
        //tracking the ticket which position belongs to
        mapping(uint256 => uint256) positionTicket;
        //tracking the event which outcome belongs to
        mapping(uint256 => uint40) outcomeEvent;
        Credit credit;
        uint32 rake;
        //trading fee
        uint32 tradingFee;
        //pnl fee
        uint32 pnlFee;
        //buy slippage boost base 1000
        uint32 buySlippage;
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
        $.rake = 10;
        //tradingFee base 1000
        $.tradingFee = 5;
        //pnlFee base 1000
        $.pnlFee = 50;
        $.buySlippage = 1000;
    }

    function createEvent(
        uint40 eventId,
        uint256 startTime,
        uint256 expireTime,
        uint256 threshold,
        uint256[] memory outcomeIds
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require($.events[eventId].status == 0, "Event Already Existed");

        $.events[eventId].status = EVENT_STATUS_POOL_INITIALIZE;
        $.events[eventId].startTime = startTime;
        $.events[eventId].expireTime = expireTime;
        $.events[eventId].threshold = threshold;
        for (uint i = 0; i < outcomeIds.length; i++) {
            $.outcomeEvent[outcomeIds[i]] = eventId;
        }
        emit EventCreated(eventId);
    }

    function buyPosition(
        uint88 amount,
        uint256 outcome,
        uint256 maxPayout,
        bytes memory signature
    ) external {
        PredictStorage storage $ = _getOwnStorage();
        //check the signature
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                amount,
                outcome,
                maxPayout
            )
        );
        address recoverBooker = MessageHashUtils
            .toEthSignedMessageHash(hash)
            .recover(signature);
        require(
            bookie.hasRole(BOOKER_ROLE, recoverBooker),
            "Invalid Signature"
        );
        //check condition
        require(amount <= $.credit.getCredit(msg.sender), "Not enough credit");
        uint40 eventId = uint40(outcome >> 64);
        console.log("eventId: ", eventId);
        require($.events[eventId].status != 0, "Event not existed");
        require($.outcomeEvent[outcome] == eventId, "Invalid outcome");
        require(
            $.events[eventId].status != EVENT_STATUS_CLOSED &&
                $.events[eventId].status != EVENT_STATUS_CANCEL,
            "Event closed"
        );
        require(
            block.timestamp <= $.events[eventId].expireTime,
            "Event expired"
        );
        //check the threshold
        require(
            $.totalEventVolume[eventId] + amount <=
                maxPayout + $.events[eventId].threshold,
            "Threshold reached"
        );
        uint88 positionAmount;
        uint88 fee;
        uint256 ticketId = _buildTicketId(msg.sender, outcome);
        if ($.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE) {
            $.lastPosId++;
            //calculate the trading fee
            fee = (amount * $.tradingFee) / 1000;
            uint88 rAmount = amount - fee;
            $.totalEventVolume[eventId] += rAmount;
            $.totalOcVolume[outcome] += rAmount;
            $.totalOcVolumeInitial[outcome] += rAmount;
            $.totalEventVolumeInitial[eventId] += rAmount;
            Position memory newPos = Position(
                POSITION_STATUS_INITIALIZE,
                0,
                rAmount,
                0,
                block.timestamp,
                outcome,
                msg.sender
            );
            $.positions[$.lastPosId] = newPos;
            $.positionTicket[$.lastPosId] = ticketId;
            //transfer credit
            $.credit.predicMarketTransferFrom(msg.sender, amount, fee);
        } else if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            $.lastPosId++;
            //calculate the trading fee
            fee = (amount * $.tradingFee) / 1000;
            uint88 rAmount = amount - fee;
            //calculate the price and position
            uint40 price;
            //handle in case totalEventVolume and totalOcVolume is 0
            if (
                $.totalEventVolume[eventId] == 0 &&
                $.totalOcVolume[outcome] == 0
            ) {
                price = 10 ** 6;
                $.totalEventVolume[eventId] += rAmount;
                $.totalOcVolume[outcome] += rAmount;
            } else {
                //handle if event already have volume
                $.totalEventVolume[eventId] += rAmount;
                $.totalOcVolume[outcome] += rAmount;
                if (
                    $.totalEventVolume[eventId] * 100 <
                    $.totalOcVolume[outcome] * (100 + $.rake)
                ) {
                    price = uint40(
                        ($.totalEventVolume[eventId] * WEI6) /
                            $.totalOcVolume[outcome]
                    );
                } else {
                    price = uint40(
                        ($.totalEventVolume[eventId] * 100 * WEI6) /
                            ($.totalOcVolume[outcome] * (100 + $.rake))
                    );
                }
            }
            console.log("price: ", price);
            //calculate the position
            positionAmount = uint88((price * rAmount) / WEI6);
            console.log("positionAmount: ", positionAmount);
            Position memory newPos = Position(
                POSITION_STATUS_OPEN,
                price,
                rAmount,
                positionAmount,
                block.timestamp,
                outcome,
                msg.sender
            );
            $.tickets[ticketId].isFirstSell = false;
            $.positions[$.lastPosId] = newPos;
            $.positionTicket[$.lastPosId] = ticketId;
            //transfer credit
            $.credit.predicMarketTransferFrom(msg.sender, amount, fee);
        }
        emit TicketBuy(
            amount,
            outcome,
            msg.sender,
            positionAmount,
            $.lastPosId,
            ticketId,
            uint256(fee)
        );
    }

    function sellPosition(
        uint256 ticketId,
        uint88 posAmount,
        uint256[] memory posIds,
        bytes memory signature
    ) external {
        PredictStorage storage $ = _getOwnStorage();
        //check the signature
        bytes32 hash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                ticketId,
                posAmount,
                posIds
            )
        );
        address recoverBooker = MessageHashUtils
            .toEthSignedMessageHash(hash)
            .recover(signature);
        require(
            bookie.hasRole(BOOKER_ROLE, recoverBooker),
            "Invalid Signature"
        );
        require(posIds.length > 0, "Invalid posIds");
        for (uint i = 0; i < posIds.length; i++) {
            require(
                $.positionTicket[posIds[i]] == ticketId,
                "Invalid ticketId"
            );
        }
        require(
            $.positions[posIds[0]].account == msg.sender,
            "Invalid account"
        );
        uint256 _outcomeId = $.positions[posIds[0]].outcomeId;
        //calculate the next price if sell this position
        uint40 eventId = uint40(_outcomeId >> 64);
        require(
            $.events[eventId].status == EVENT_STATUS_OPEN ||
                $.events[eventId].status == EVENT_STATUS_CLOSED ||
                $.events[eventId].status == EVENT_STATUS_CANCEL,
            "Event in initialize"
        );
        if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            require(
                block.timestamp <= $.events[eventId].expireTime,
                "Event Expired"
            );
        }
        (uint88 amount, uint88 positionLeft) = _calPositionReturnAmount(
            posIds,
            posAmount,
            eventId,
            ticketId
        );
        console.log("posAmount sell: ", posAmount);
        console.log("amount return when sell: ", amount);
        if (amount == 0) {
            revert("Ticket lost");
        }
        uint256 fee = uint256((amount * $.tradingFee) / 1000);
        //transfer credit
        $.credit.predicMarketTransfer(msg.sender, amount, fee);

        emit TicketSell(
            ticketId,
            posAmount,
            (amount - (amount * $.tradingFee) / 1000),
            msg.sender,
            fee,
            positionLeft
        );
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
        emit EventResolveInitialize(eventId);
    }

    function resolveEvent(
        uint40 eventId,
        uint40[] memory marketIds,
        uint256[] memory winnerOutcomes,
        uint256[] memory loserOutcomes
    ) external onlyRole(RESOLVER_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require(
            $.events[eventId].status == EVENT_STATUS_OPEN,
            "Invalid event status"
        );
        require(winnerOutcomes.length == marketIds.length, "Invalid Input");
        //calculate the winner
        for (uint i = 0; i < winnerOutcomes.length; i++) {
            $.isOutcomeWinner[winnerOutcomes[i]] = true;
        }
        //calculate the loser
        for (uint i = 0; i < loserOutcomes.length; i++) {
            $.isOutcomeWinner[loserOutcomes[i]] = false;
        }
        $.events[eventId].status = EVENT_STATUS_CLOSED;
        emit EventResolved(eventId);
    }

    ////////////////////
    /////// GETTER /////
    ////////////////////
    function getPosition(
        uint256 posId
    ) external view returns (uint256, uint40, uint88, uint88, uint256, uint8) {
        return _getPosition(posId);
    }

    function getTicketData(
        uint256 ticketId,
        uint256[] memory posIds
    ) external view returns (uint88, uint88) {
        return _getTicketAmount(ticketId, posIds);
    }

    function getEventData(uint40 eventId) external view returns (Event memory) {
        PredictStorage storage $ = _getOwnStorage();
        return $.events[eventId];
    }

    function getEventByOutcome(
        uint256 outcomeId
    ) external view returns (uint40) {
        PredictStorage storage $ = _getOwnStorage();
        return $.outcomeEvent[outcomeId];
    }

    function getSystemPnlFee() external view returns (uint256) {
        PredictStorage storage $ = _getOwnStorage();
        return $.systemPnlFee;
    }

    function getPnlFeeByEvent(uint40 eventId) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalPnlFee[eventId];
    }

    function getTotalEventVolumeInitial(
        uint40 eventId
    ) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalEventVolumeInitial[eventId];
    }

    function getTotalOcVolumeInitial(
        uint256 outcomeId
    ) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalOcVolumeInitial[outcomeId];
    }

    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        PredictStorage storage $ = _getOwnStorage();
        return $.tickets[ticketId];
    }

    function getTotalOutcomeVolume(
        uint256 outcomeId
    ) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalOcVolume[outcomeId];
    }

    function getTotalEventVolume(
        uint40 eventId
    ) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalEventVolume[eventId];
    }

    function getRake() external view returns (uint32) {
        PredictStorage storage $ = _getOwnStorage();
        return $.rake;
    }

    function getEventVolume(uint40 eventId) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalEventVolume[eventId];
    }

    function getOutcomeVolume(
        uint256 outcomeId
    ) external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.totalOcVolume[outcomeId];
    }

    ////////////////////
    /////// SETTER /////
    ////////////////////
    function setInitializeTime(
        uint256 newInitializeTime
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.initializeTime = newInitializeTime;
    }

    function setRake(uint32 newRake) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.rake = newRake;
    }

    function setTradingFee(
        uint32 newTradingFee
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.tradingFee = newTradingFee;
    }

    function setEventExpiredTime(
        uint40 eventId,
        uint256 newExpireTime
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.events[eventId].expireTime = newExpireTime;
    }

    function setPnlFee(uint32 newPnlFee) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.pnlFee = newPnlFee;
    }

    function setBuySlippage(
        uint32 newBuySlippage
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.buySlippage = newBuySlippage;
    }

    function setThreshold(
        uint40 eventId,
        uint256 newThreshold
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.events[eventId].threshold = newThreshold;
    }

    ////////////////////
    /////// PRIVATE ////
    ////////////////////
    function _calBuySlippage(
        uint88 posAmount,
        uint88 totalEventVolume,
        uint88 totalOcVolume
    ) internal view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return
            uint88(
                posAmount -
                    (posAmount * totalEventVolume * 1000) /
                    ((totalEventVolume + totalOcVolume) * $.buySlippage)
            );
    }

    function _buildTicketId(
        address account,
        uint256 outcome
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(account, outcome)));
    }

    function _calPositionReturnAmount(
        uint256[] memory posIds,
        uint88 posAmount,
        uint40 eventId,
        uint256 ticketId
    ) private returns (uint88, uint88) {
        PredictStorage storage $ = _getOwnStorage();
        if (!$.tickets[ticketId].isFirstSell) {
            for (uint i = 0; i < posIds.length; i++) {
                (, , uint88 _amount, uint88 _position, , ) = _getPosition(
                    posIds[i]
                );
                $.tickets[ticketId].amount += _amount;
                $.tickets[ticketId].positionAmount += _position;
            }
            $.tickets[ticketId].isFirstSell = true;
        }
        require(
            posAmount <= $.tickets[ticketId].positionAmount,
            "Invalid posAmount"
        );
        uint88 amount;
        //calculate the amount
        if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            //calculate the sell amount by posAmount
            uint256 _outcomeId = $.positions[posIds[0]].outcomeId;
            uint88 sellAmount = ($.tickets[ticketId].amount * posAmount) /
                $.tickets[ticketId].positionAmount;
            console.log("sellAmount: ", sellAmount);
            // $.totalEventVolume[eventId] -= sellAmount;
            // $.totalOcVolume[_outcomeId] -= sellAmount;
            console.log("totalEventVolume: ", $.totalEventVolume[eventId]);
            console.log("totalOcVolume: ", $.totalOcVolume[_outcomeId]);
            //calculate the amount must transfer to user
            //if totalOutcomeVolume = 0 <=> user sell all the remain outcome volume => return exactly sellAmount
            if ($.totalOcVolume[_outcomeId] < sellAmount) {
                amount =
                    sellAmount -
                    (((sellAmount * (100 + $.rake)) *
                        (sellAmount - $.totalOcVolume[_outcomeId])) /
                        $.totalEventVolume[eventId]) /
                    100;
            } else {
                amount =
                    sellAmount +
                    ((
                        (sellAmount *
                            ($.totalOcVolume[_outcomeId] - sellAmount))
                    ) / $.totalEventVolume[eventId]);
            }
            console.log("amount earn: ", amount);
            //minus the sell position and sell amount
            $.tickets[ticketId].positionAmount -= posAmount;
            $.tickets[ticketId].amount -= sellAmount;
            //update the event volume and outcome volume
            $.totalEventVolume[eventId] = $.totalEventVolume[eventId] - amount;
            $.totalOcVolume[_outcomeId] = $.totalOcVolume[_outcomeId] - amount;
        } else if ($.events[eventId].status == EVENT_STATUS_CLOSED) {
            //calculate the price after event close
            uint256 _outcomeId = $.positions[posIds[0]].outcomeId;
            if (!$.isOutcomeWinner[_outcomeId]) {
                amount = 0;
            } else {
                require(
                    posAmount == $.tickets[ticketId].positionAmount,
                    "Event closed force to sell all"
                );
                uint88 sellAmount = $.tickets[ticketId].amount;
                $.totalEventVolume[eventId] -= sellAmount;
                $.totalOcVolume[_outcomeId] -= sellAmount;
                //calculate the amount must transfer to user
                //apply the slippage
                amount = posAmount;
                //minus the sell position and sell amount
                $.tickets[ticketId].positionAmount = 0;
                $.tickets[ticketId].amount = 0;
            }
        } else if ($.events[eventId].status == EVENT_STATUS_CANCEL) {
            amount = $.tickets[ticketId].amount;
            $.tickets[ticketId].positionAmount = 0;
            $.tickets[ticketId].amount = 0;
        }
        return (amount, $.tickets[ticketId].positionAmount);
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
                uint88 position = uint88(price * pos.amount);
                console.log("position amount in bidding time: ", position);
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

    function _getTicketAmount(
        uint256 ticketId,
        uint256[] memory posIds
    ) private view returns (uint88, uint88) {
        PredictStorage storage $ = _getOwnStorage();
        uint88 posAmount;
        uint88 amount;
        if ($.tickets[ticketId].isFirstSell) {
            posAmount = $.tickets[ticketId].positionAmount;
            amount = $.tickets[ticketId].amount;
        } else {
            for (uint i = 0; i < posIds.length; i++) {
                if ($.positionTicket[posIds[i]] != ticketId) {
                    posAmount = 0;
                    break;
                }
                (, , uint88 _amount, uint88 _posAmount, , ) = _getPosition(
                    posIds[i]
                );
                posAmount += _posAmount;
                amount += _amount;
            }
        }
        return (posAmount, amount);
    }

    function _getTotalEventReturn(
        uint40 eventId
    ) internal view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return
            $.totalWinEvent[eventId] +
            $.totalLostEvent[eventId] -
            $.totalPnlFee[eventId];
    }
}
