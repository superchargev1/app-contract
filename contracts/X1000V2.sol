// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Credit.sol";
import "./libs/Base.sol";
import "hardhat/console.sol";

struct Config {
    uint64 rake;
    uint256 leverage;
    uint256 platformFeePercent;
    uint256 burst;
    uint64 profitUnderExpectValue;
    uint64 profitOverExpectValue;
}

struct Position {
    bytes32 poolId;
    uint8 ptype;
    uint8 status;
    uint256 amount;
    uint256 leverage;
    uint256 size;
    uint88 openPrice;
    uint88 burnPrice;
    uint88 closePrice;
    uint88 expectPrice;
    address user;
}

struct Pool {
    uint8 level;
    uint256 longSize;
    uint256 shortSize;
    uint256 longPosition;
    uint256 shortPosition;
}

contract X1000V2 is OwnableUpgradeable, Base {
    using ECDSA for bytes32;
    // Position types
    uint8 public constant POSITION_TYPE_LONG = 1;
    uint8 public constant POSITION_TYPE_SHORT = 2;

    // Position status
    uint8 public constant POSITION_STATUS_OPEN = 1;
    uint8 public constant POSITION_STATUS_CLOSED = 2;
    uint8 public constant POSITION_STATUS_BURNT = 3;

    uint256 public constant WEI6 = 10 ** 6;
    bytes32 public constant BATCHING = keccak256("BATCHING");
    bytes32 public constant X1000_BATCHER_ROLE =
        keccak256("X1000_BATCHER_ROLE");

    event OpenPosition(
        uint256 pid,
        uint256 value,
        uint256 leverage,
        uint256 inPrice,
        uint256 openPrice,
        uint256 burnPrice,
        uint256 expectPrice,
        uint256 openFee,
        uint256 size,
        uint256 plId
    );

    event ClosePosition(
        uint256 pid,
        uint256 returnAmount,
        uint256 feeAmount,
        uint256 closePrice
    );

    struct X1000V2Storage {
        Config config;
        Credit credit;
        mapping(uint256 => Position) positions;
        uint256 lastPosId;
        mapping(bytes32 => Pool) pools;
    }

    // keccak256(abi.encode(uint256(keccak256("goal3.storage.X1000V4")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant X1000V2StorageLocation =
        0x005fcd49fdbf6f43ec7feab828b4f7d0f873044ab6296aaa7ce86a05d55b6700;

    function _getOwnStorage() private pure returns (X1000V2Storage storage $) {
        assembly {
            $.slot := X1000V2StorageLocation
        }
    }

    function initialize(
        address bookieAddress,
        address creditContractAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __Base_init(bookieAddress);

        X1000V2Storage storage $ = _getOwnStorage();
        // init default ETH, BTC pool
        $.pools[bytes32("BTC")].level = 1;
        $.pools[bytes32("ETH")].level = 1;
        // system leverage
        $.config.leverage = 100;
        $.config.platformFeePercent = 1;
        $.config.burst = WEI6;
        $.config.rake = 80;
        $.config.profitUnderExpectValue = 90;
        $.config.profitOverExpectValue = 10;
        $.credit = Credit(creditContractAddress);
    }

    function getPoolLiquidity(bytes32 poolId) private view returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        return
            ($.credit.platformCredit() / $.pools[poolId].level) *
            $.config.leverage;
    }

    function getPlatformFee(uint256 value) private view returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        return (value * $.config.platformFeePercent) / 10000;
    }

    //////////////////////////////////////////
    /////////////// V2 //////////////////////
    ////////////////////////////////////////

    function openLongPositionV2(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price,
        uint256 plId
    ) public onlyFrom(BATCHING) {
        require(
            leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
            "Invalid leverage"
        );
        require(value > 0, "Invalid Value");
        X1000V2Storage storage $ = _getOwnStorage();
        Pool storage pool = $.pools[poolId];
        require($.credit.getCredit(account) >= value, "Not Enough Credit");
        require(pool.level > 0, "Invalid Pool");
        uint256 _size = (value * leverage) / WEI6;
        uint256 _platformFee = getPlatformFee(_size);
        require(_platformFee < value, "Invalid Platform Fee");
        // revert("run here 1234");
        uint256 _openValue = value - _platformFee;
        uint256 _openSize = (_openValue * leverage) / WEI6;
        uint256 _expectPrice = _getLongExpectPrice(
            poolId,
            value,
            leverage,
            price
        );
        uint256 _liqPrice = (price *
            (leverage - (WEI6 * $.config.rake) / 100)) / leverage;
        console.log("_liqPrice: ", _liqPrice);
        Position memory newPos = Position(
            poolId,
            POSITION_TYPE_LONG,
            POSITION_STATUS_OPEN,
            _openValue,
            leverage,
            _openSize,
            uint88(price),
            uint88(_liqPrice),
            uint88(0),
            uint88(_expectPrice),
            account
        );
        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;
        pool.longSize += _openSize;
        // revert("run here 555");
        pool.longPosition += (_openSize * WEI6) / price;
        $.credit.transferFrom(account, value, _platformFee);
        emit OpenPosition(
            $.lastPosId,
            value,
            leverage,
            price,
            price,
            _liqPrice,
            _expectPrice,
            _platformFee,
            (_openSize * WEI6) / price,
            plId
        );
    }

    function openShortPositionV2(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price,
        uint256 plId
    ) public onlyFrom(BATCHING) {
        require(
            leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
            "Invalid leverage"
        );
        require(value > 0, "Invalid Value");
        X1000V2Storage storage $ = _getOwnStorage();
        Pool storage pool = $.pools[poolId];
        require($.credit.getCredit(account) >= value, "Not Enough Credit");
        require(pool.level > 0, "Invalid Pool");
        uint256 _size = (value * leverage) / WEI6;
        uint256 _platformFee = getPlatformFee(_size);
        require(_platformFee < value, "Invalid Platform Fee");
        uint256 _openValue = value - _platformFee;
        uint256 _openSize = (_openValue * leverage) / WEI6;
        //calculate gap price
        uint256 _expectPrice = _getShortExpectPrice(
            poolId,
            value,
            leverage,
            price
        );
        uint256 _liqPrice = (price *
            (leverage + (WEI6 * $.config.rake) / 100)) / leverage;
        Position memory newPos = Position(
            poolId,
            POSITION_TYPE_SHORT,
            POSITION_STATUS_OPEN,
            _openValue,
            leverage,
            _openSize,
            uint88(price),
            uint88(_liqPrice),
            uint88(0),
            uint88(_expectPrice),
            account
        );
        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;
        pool.shortSize += _openSize;
        uint256 _pos = (_openSize * WEI6) / price;
        pool.shortPosition += _pos;
        $.credit.transferFrom(account, value, _platformFee);
        emit OpenPosition(
            $.lastPosId,
            value,
            leverage,
            price,
            price,
            _liqPrice,
            _expectPrice,
            _platformFee,
            _pos,
            plId
        );
    }

    function closePosition(
        uint256 posId,
        uint256 price
    ) public onlyFrom(BATCHING) {
        X1000V2Storage storage $ = _getOwnStorage();
        Position storage pos = $.positions[posId];
        Pool storage pool = $.pools[pos.poolId];
        require(pos.status == POSITION_STATUS_OPEN, "Invalid Position Status");
        uint256 _size = (pos.amount * pos.leverage) / WEI6;
        //calculate position pnl
        uint256 _pnl = pos.ptype == POSITION_TYPE_LONG
            ? price > pos.openPrice
                ? (_size * price - _size * pos.openPrice) / pos.openPrice
                : 0
            : price < pos.openPrice
            ? (_size * pos.openPrice - _size * price) / pos.openPrice
            : 0;
        //_pnl = 151612.24961007261366795621504201 (short)
        uint256 _pnlGap = pos.ptype == POSITION_TYPE_LONG
            ? ((pos.expectPrice - pos.openPrice) * _size) / pos.openPrice
            : ((pos.openPrice - pos.expectPrice) * _size) / pos.openPrice;
        //_pnlGap = 651386
        uint256 _returnValue;
        uint256 _profitFee;
        if (_pnl > 0) {
            //calculate fee
            console.log("_pnl: ", _pnl);
            console.log("price: ", price);
            console.log("openPrice: ", pos.openPrice);
            console.log("expectPrice: ", pos.expectPrice);
            _profitFee = _getProfitFee(
                price,
                pos.expectPrice,
                _pnl,
                _pnlGap,
                pos.ptype
            );
            console.log("_profitFee: ", _profitFee);
            //caculate returnValue
            _returnValue = pos.amount + _pnl - _profitFee;
            console.log("_returnValue: ", _returnValue);
            //update position status
            pos.status = POSITION_STATUS_CLOSED;
            pos.closePrice = uint88(price);
            if (pos.ptype == POSITION_TYPE_LONG) {
                pool.longSize = pool.longSize < pos.size
                    ? 0
                    : pool.longSize - pos.size;
                pool.longPosition = pool.longPosition <
                    (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : pool.longPosition - (pos.size * WEI6) / pos.openPrice;
            } else {
                pool.shortSize = pool.shortSize < pos.size
                    ? 0
                    : pool.shortSize - pos.size;
                pool.shortPosition = pool.shortPosition <
                    (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : pool.shortPosition - (pos.size * WEI6) / pos.openPrice;
            }
            console.log("done process");
            $.credit.transfer(pos.user, _returnValue, _profitFee);
        } else {
            _returnValue = pos.ptype == POSITION_TYPE_LONG
                ? pos.amount -
                    ((pos.openPrice - price) * pos.size) /
                    pos.openPrice
                : pos.amount -
                    ((price - pos.openPrice) * pos.size) /
                    pos.openPrice;
            console.log("_returnValue: ", _returnValue);
            if (pos.ptype == POSITION_TYPE_LONG) {
                console.log(
                    "pool long size after close: ",
                    pool.longSize - pos.size
                );
                pool.longSize = pool.longSize < pos.size
                    ? 0
                    : pool.longSize - pos.size;
                pool.longPosition = pool.longPosition <
                    (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : pool.longPosition - (pos.size * WEI6) / pos.openPrice;
            } else {
                pool.shortSize = pool.shortSize < pos.size
                    ? 0
                    : pool.shortSize - pos.size;
                pool.shortPosition = pool.shortPosition <
                    (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : pool.shortPosition - (pos.size * WEI6) / pos.openPrice;
            }
            $.credit.transfer(pos.user, _returnValue, 0);
        }
        emit ClosePosition(posId, _returnValue, _profitFee, price);
    }

    function burnPosition(
        uint256 posId
    ) public onlyFrom(BATCHING) returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        if (
            $.positions[posId].status != POSITION_STATUS_CLOSED &&
            $.positions[posId].status != POSITION_STATUS_BURNT
        ) {
            $.positions[posId].status = POSITION_STATUS_BURNT;
            Position storage pos = $.positions[posId];
            if (pos.ptype == POSITION_TYPE_LONG) {
                $.pools[pos.poolId].longSize = $.pools[pos.poolId].longSize <
                    pos.size
                    ? 0
                    : $.pools[pos.poolId].longSize - pos.size;
                $.pools[pos.poolId].longPosition = $
                    .pools[pos.poolId]
                    .longPosition < (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : $.pools[pos.poolId].longPosition -
                        (pos.size * WEI6) /
                        pos.openPrice;
            } else {
                $.pools[pos.poolId].shortSize = $.pools[pos.poolId].shortSize <
                    pos.size
                    ? 0
                    : $.pools[pos.poolId].shortSize - pos.size;
                $.pools[pos.poolId].shortPosition = $
                    .pools[pos.poolId]
                    .shortPosition < (pos.size * WEI6) / pos.openPrice
                    ? 0
                    : $.pools[pos.poolId].shortPosition -
                        (pos.size * WEI6) /
                        pos.openPrice;
            }
            return (posId);
        }
    }

    //////////////////////////////////////////
    /////////////// SETTER ///////////////////
    //////////////////////////////////////////

    function setBurst(uint256 burst) external onlyRole(ADMIN_ROLE) {
        X1000V2Storage storage $ = _getOwnStorage();
        $.config.burst = burst;
    }

    function setRake(uint64 rake) external onlyRole(ADMIN_ROLE) {
        X1000V2Storage storage $ = _getOwnStorage();
        $.config.rake = rake;
    }

    //////////////////////////////////////////
    /////////////// GETTER ///////////////////
    //////////////////////////////////////////
    function getPosition(
        uint256 posId
    ) external view returns (Position memory) {
        X1000V2Storage storage $ = _getOwnStorage();
        return $.positions[posId];
    }

    //////////////////////////////////////////
    /////////////// PRIVATE //////////////////
    //////////////////////////////////////////
    function _getLongExpectPrice(
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) internal view returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        uint256 _size = (value * leverage) / WEI6;
        uint256 _platformFee = getPlatformFee(_size);
        _size = ((value - _platformFee) * leverage) / WEI6;
        //calculate total long position
        uint256 _tempLongPosition = $.pools[poolId].longPosition +
            (_size * WEI6) /
            price;
        uint256 _tmpLongSize = $.pools[poolId].longSize + _size;
        //calculate delta pnl
        uint256 _deltaPNL = _tempLongPosition > (_tmpLongSize * WEI6) / price
            ? _tempLongPosition - (_tmpLongSize * WEI6) / price
            : 0;
        // if _deltaPNL  > 0 => system is coming to lost
        // inject _deltaPNL into formula
        uint256 _pLiquid = getPoolLiquidity(poolId);
        uint256 _openPrice;
        // uint256 _rateLong = _tmpLongSize / $.pools[poolId].shortSize;
        if ($.pools[poolId].shortSize > 0) {
            _openPrice =
                price +
                (((price / WEI6) * _size * _tmpLongSize * $.config.burst)) /
                (_pLiquid + _tmpLongSize - (_deltaPNL * price) / WEI6) /
                $.pools[poolId].shortSize;
        } else {
            _openPrice = (((_pLiquid +
                _tmpLongSize +
                (_size * $.config.burst) /
                WEI6 -
                (_deltaPNL * price) /
                WEI6) * price) /
                (_pLiquid + _tmpLongSize - (_deltaPNL * price) / WEI6));
        }
        return _openPrice;
    }

    function _getShortExpectPrice(
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) private returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        Pool storage pool = $.pools[poolId];
        uint256 _size = (value * leverage) / WEI6;
        uint256 _platformFee = getPlatformFee(_size);
        _size = ((value - _platformFee) * leverage) / WEI6;
        uint256 _position = (_size * WEI6) / price;
        //calculate total short position
        uint256 _tempShortPosition = pool.shortPosition + _position;
        uint256 _tmpShortSize = pool.shortSize + _size;
        //calculate normalize long position
        uint256 _normPosition = (_tmpShortSize * WEI6) / price;
        //calculate delta pnl
        uint256 _deltaPNL = _tempShortPosition < _normPosition
            ? _normPosition - _tempShortPosition
            : 0;
        uint256 _pLiquid = getPoolLiquidity(poolId);
        uint256 _openPrice;
        // uint256 _rateShort = _tmpShortSize / $.pools[poolId].longSize;
        if ($.pools[poolId].longSize > 0) {
            _openPrice =
                price -
                ((price * _size * _tmpShortSize * $.config.burst) / WEI6) /
                (_pLiquid + _tmpShortSize - (_deltaPNL * price) / WEI6) /
                $.pools[poolId].longSize;
        } else {
            _openPrice = (((_pLiquid +
                _tmpShortSize -
                (_size * $.config.burst) /
                WEI6 -
                (_deltaPNL * price) /
                WEI6) * price) /
                (_pLiquid + _tmpShortSize - (_deltaPNL * price) / WEI6));
        }
        return _openPrice;
    }

    function _getProfitFee(
        uint256 closePrice,
        uint256 expectPrice,
        uint256 pnl,
        uint256 pnlGap,
        uint8 ptype
    ) private view returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        if (ptype == POSITION_TYPE_LONG) {
            if (closePrice < expectPrice) {
                return ($.config.profitUnderExpectValue * pnl) / 100;
            } else {
                console.log("run here 123");
                uint256 _fee = (($.config.profitUnderExpectValue * pnl) /
                    (pnl - pnlGap)) /
                    100 +
                    ($.config.profitOverExpectValue * pnl) /
                    100;
                console.log("_fee: ", _fee);
                return _fee;
            }
        } else {
            if (closePrice > expectPrice) {
                console.log("run here 234");
                return ($.config.profitUnderExpectValue * pnl) / 100;
            } else {
                uint256 _fee = (($.config.profitUnderExpectValue * pnl) /
                    (pnl - pnlGap)) /
                    100 +
                    ($.config.profitOverExpectValue * pnl) /
                    100;
                console.log("_fee: ", _fee);
                return _fee;
            }
        }
    }

    function getPnl(
        uint256 posId,
        uint256 price
    ) external view returns (uint256 pnl) {
        X1000V2Storage storage $ = _getOwnStorage();
        Position storage pos = $.positions[posId];
        uint256 _size = (pos.amount * pos.leverage) / WEI6;
        //calculate position pnl
        uint256 _pnl = pos.ptype == POSITION_TYPE_LONG
            ? price > pos.openPrice
                ? (_size * price - _size * pos.openPrice) / pos.openPrice
                : 0
            : price < pos.openPrice
            ? (_size * pos.openPrice - _size * price) / pos.openPrice
            : 0;
        uint256 _pnlGap = pos.ptype == POSITION_TYPE_LONG
            ? pos.expectPrice - pos.openPrice
            : pos.openPrice - pos.expectPrice;
        if (_pnl > 0) {
            uint256 _profitFee = _getProfitFee(
                price,
                pos.expectPrice,
                _pnl,
                _pnlGap,
                pos.ptype
            );
            pnl = _pnl - _profitFee;
        } else {
            pnl = (pos.ptype == POSITION_TYPE_LONG)
                ? ((pos.openPrice - price) * pos.size) / pos.openPrice
                : ((price - pos.openPrice) * pos.size) / pos.openPrice;
        }
    }

    function getPoolData(bytes32 poolId) external view returns (Pool memory) {
        X1000V2Storage storage $ = _getOwnStorage();
        return $.pools[poolId];
    }
}
