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
    uint256 outcomeId;
    address account;
}

struct Ticket {
    //first block
    uint88 amount;
    uint88 positionAmount;
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
        //tracking the maximum payout
        mapping(uint40 => uint88) maxPayout;
        mapping(uint256 => Position) positions;
        //tracking the total outcomeVolume and eventVolume
        mapping(uint256 => uint88) totalOcVolume;
        mapping(uint40 => uint88) totalEventVolume;
        //tracking the total outcome positions
        mapping(uint256 => uint88) totalOutcomePosition;
        //tracking the outcome which is winner or loser
        mapping(uint256 => bool) isOutcomeWinner;
        //tickets
        mapping(uint256 => Ticket) tickets;
        //tracking the ticket which position belongs to
        mapping(uint256 => uint256) positionTicket;
        //tracking the event which outcome belongs to
        mapping(uint256 => uint40) outcomeEvent;
        mapping(uint256 => uint88) outcomeMinLiquid;
        mapping(uint256 => uint88) outcomeInitialLiquid;
        Credit credit;
        uint32 rake;
        //trading fee
        uint32 tradingFee;
        //pnl fee
        uint32 pnlFee;
        //buy slippage boost base 1000
        uint88 minimumLiquidityPool;
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
        $.minimumLiquidityPool = 5000 * (10 ** 6);
    }

    function createEvent(
        uint40 eventId,
        uint256 startTime,
        uint256 expireTime,
        uint256 threshold,
        uint256[] memory outcomeIds,
        uint88[] memory outcomeMinLiquid,
        uint88[] memory outcomeInitialLiquid
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        require($.events[eventId].status == 0, "Event Already Existed");
        require(
            outcomeIds.length == outcomeMinLiquid.length &&
                outcomeIds.length == outcomeInitialLiquid.length,
            "Invalid input"
        );
        $.events[eventId].status = EVENT_STATUS_OPEN;
        $.events[eventId].startTime = startTime;
        $.events[eventId].expireTime = expireTime;
        $.events[eventId].threshold = threshold;
        for (uint i = 0; i < outcomeIds.length; i++) {
            $.outcomeEvent[outcomeIds[i]] = eventId;
            $.totalOcVolume[outcomeIds[i]] = outcomeInitialLiquid[i];
            $.totalEventVolume[eventId] += outcomeInitialLiquid[i];
            $.outcomeMinLiquid[outcomeIds[i]] = outcomeMinLiquid[i];
        }
        emit EventCreated(eventId);
    }

    function buyPosition(
        uint88 amount,
        uint256 outcome,
        bytes memory signature
    ) external {
        PredictStorage storage $ = _getOwnStorage();
        //check the signature
        bytes32 hash = keccak256(
            abi.encodePacked(address(this), msg.sender, amount, outcome)
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

        uint88 positionAmount;
        uint88 fee;
        uint256 ticketId = _buildTicketId(msg.sender, outcome);
        $.lastPosId++;
        //calculate the trading fee
        fee = (amount * $.tradingFee) / 1000;
        uint88 rAmount = amount - fee;
        //calculate the price and position
        uint40 price;
        //handle in case totalEventVolume and totalOcVolume is 0
        if ($.totalEventVolume[eventId] == 0 && $.totalOcVolume[outcome] == 0) {
            price = 10 ** 6;
            $.totalEventVolume[eventId] += rAmount;
            $.totalOcVolume[outcome] += rAmount;
        } else {
            //handle if event already have volume
            console.log("run here ====>", $.totalEventVolume[eventId]);
            console.log("11111111 ========>", $.totalOcVolume[outcome]);
            $.totalEventVolume[eventId] += rAmount;
            $.totalOcVolume[outcome] += rAmount;
            price = uint40(
                ($.totalEventVolume[eventId] * 100 * WEI6) /
                    ($.totalOcVolume[outcome] * (100 + $.rake))
            );
        }
        console.log("price: ", price);
        //calculate the position
        positionAmount = uint88((price * rAmount) / WEI6);
        console.log("positionAmount ==========>", positionAmount);
        //check the threshold
        if (
            $.totalOutcomePosition[outcome] + positionAmount >
            $.maxPayout[eventId]
        ) {
            console.log("run here 2323232323", $.totalEventVolume[eventId]);
            require(
                $.totalEventVolume[eventId] + $.events[eventId].threshold >=
                    $.totalOutcomePosition[outcome] + positionAmount,
                "Threshold reached"
            );
        } else {
            require(
                $.totalEventVolume[eventId] + $.events[eventId].threshold >=
                    $.maxPayout[eventId],
                "Threshold reached"
            );
        }
        Position memory newPos = Position(
            POSITION_STATUS_OPEN,
            price,
            rAmount,
            positionAmount,
            outcome,
            msg.sender
        );
        $.maxPayout[eventId] = $.totalOutcomePosition[outcome] + positionAmount;
        $.totalOutcomePosition[outcome] += positionAmount;
        $.tickets[ticketId].amount += rAmount;
        $.tickets[ticketId].positionAmount += positionAmount;
        $.positions[$.lastPosId] = newPos;
        $.positionTicket[$.lastPosId] = ticketId;
        //transfer credit
        $.credit.predicMarketTransferFrom(msg.sender, amount, fee);
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
        uint256 outcomeId,
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
                outcomeId
            )
        );
        address recoverBooker = MessageHashUtils
            .toEthSignedMessageHash(hash)
            .recover(signature);
        require(
            bookie.hasRole(BOOKER_ROLE, recoverBooker),
            "Invalid Signature"
        );
        require(
            _buildTicketId(msg.sender, outcomeId) == ticketId,
            "Invalid ticketId"
        );
        //calculate the next price if sell this position
        uint40 eventId = uint40(outcomeId >> 64);
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
        require(
            $.totalOcVolume[outcomeId] >= $.outcomeMinLiquid[outcomeId],
            "Outcome liquid too low"
        );
        (uint88 amount, uint88 positionLeft) = _calPositionReturnAmount(
            outcomeId,
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
    // remove this function
    // function resolveInitializePool(
    //     uint40 eventId
    // ) external onlyRole(RESOLVER_ROLE) {
    //     PredictStorage storage $ = _getOwnStorage();
    //     require(
    //         $.events[eventId].status == EVENT_STATUS_POOL_INITIALIZE,
    //         "Event not open"
    //     );
    //     //calculate the price and position of each posIds
    //     $.events[eventId].status = EVENT_STATUS_OPEN;
    //     emit EventResolveInitialize(eventId);
    // }

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
    ) external view returns (uint256, uint40, uint88, uint88, uint8) {
        return _getPosition(posId);
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

    function getMinimumLiquidPool() external view returns (uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return $.minimumLiquidityPool;
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

    function setThreshold(
        uint40 eventId,
        uint256 newThreshold
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.events[eventId].threshold = newThreshold;
    }

    function setMinimumLiquidityPool(
        uint88 newMinimumLiquidityPool
    ) external onlyRole(OPERATOR_ROLE) {
        PredictStorage storage $ = _getOwnStorage();
        $.minimumLiquidityPool = newMinimumLiquidityPool;
    }

    ////////////////////
    /////// PRIVATE ////
    ////////////////////
    function _buildTicketId(
        address account,
        uint256 outcome
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(account, outcome)));
    }

    function _calPositionReturnAmount(
        uint256 outcomeId,
        uint88 posAmount,
        uint40 eventId,
        uint256 ticketId
    ) private returns (uint88, uint88) {
        PredictStorage storage $ = _getOwnStorage();
        console.log("$.tickets[ticketId].amount: ", $.tickets[ticketId].amount);
        require(
            posAmount <= $.tickets[ticketId].positionAmount,
            "Invalid posAmount"
        );
        uint88 amount;
        uint256 _outcomeId = outcomeId;
        //calculate the amount
        if ($.events[eventId].status == EVENT_STATUS_OPEN) {
            //calculate the sell amount by posAmount
            uint88 sellAmount = ($.tickets[ticketId].amount * posAmount) /
                $.tickets[ticketId].positionAmount;
            console.log("sellAmount: ", sellAmount);
            console.log("totalEventVolume: ", $.totalEventVolume[eventId]);
            console.log("totalOcVolume: ", $.totalOcVolume[_outcomeId]);
            //calculate the amount must transfer to user
            //calculate the price
            uint88 price = (($.totalOcVolume[_outcomeId] - sellAmount) *
                (10 ** 6)) / ($.totalEventVolume[eventId] - sellAmount);
            amount = (price * posAmount) / (10 ** 6);
            //minus the sell position and sell amount
            $.tickets[ticketId].positionAmount -= posAmount;
            $.tickets[ticketId].amount -= sellAmount;
            $.totalEventVolume[eventId] -= amount;
            $.totalOcVolume[_outcomeId] -= amount;
        } else if ($.events[eventId].status == EVENT_STATUS_CLOSED) {
            //calculate the price after event close
            if (!$.isOutcomeWinner[_outcomeId]) {
                amount = 0;
            } else {
                require(
                    posAmount == $.tickets[ticketId].positionAmount,
                    "Event closed force to sell all"
                );
                uint88 sellAmount = $.tickets[ticketId].amount;
                $.totalEventVolume[eventId] >= sellAmount
                    ? $.totalEventVolume[eventId] -= sellAmount
                    : $.totalEventVolume[eventId] = 0;
                $.totalOcVolume[_outcomeId] >= sellAmount
                    ? $.totalOcVolume[_outcomeId] -= sellAmount
                    : $.totalOcVolume[_outcomeId] = 0;
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
    ) private view returns (uint256, uint40, uint88, uint88, uint8) {
        PredictStorage storage $ = _getOwnStorage();
        Position memory pos = $.positions[posId];
        return (pos.position, pos.price, pos.amount, pos.position, pos.status);
    }

    function _getTicketAmount(
        uint256 ticketId,
        uint256[] memory posIds
    ) private view returns (uint88, uint88) {
        PredictStorage storage $ = _getOwnStorage();
        return ($.tickets[ticketId].positionAmount, $.tickets[ticketId].amount);
    }
}
