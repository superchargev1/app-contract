// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
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

enum PositionType {
    LONG,
    SHORT
}

enum PositionStatus {
    OPEN,
    CLOSED,
    BURNT
}

struct Position {
    bytes32 poolId;
    PositionType ptype;
    PositionStatus status;
    uint256 amount;
    uint256 leverage;
    uint256 size;
    uint88 openPrice;
    uint88 initPrice;
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
    uint256 public constant WEI6 = 10 ** 6;
    bytes32 public constant BATCHING = keccak256("BATCHING");

    event OpenPosition(
        uint256 pid,
        uint256 value,
        uint256 leverage,
        uint256 inPrice,
        uint256 openPrice,
        uint256 burnPrice,
        uint256 expectPrice,
        uint256 plId
    );

    event ClosePosition(uint256 pid, uint256 closePrice);

    struct X1000V2Storage {
        Config config;
        Credit credit;
        mapping(uint256 => Position) positions;
        uint256 lastPosId;
        mapping(bytes32 => Pool) pools;
    }

    // keccak256(abi.encode(uint256(keccak256("goal3.storage.X1000V2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant X1000V2StorageLocation =
        0xe7b4aea9018d8efb6fc2599a57ab794229323046c2fee1f29dc7eeddeb660700;

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
        $.config.burst = 20 * WEI6;
        $.config.rake = 80;
        $.config.profitUnderExpectValue = 90;
        $.config.profitOverExpectValue = 10;
        $.credit = Credit(creditContractAddress);
    }

    function getPoolLiquidity(bytes32 poolId) internal returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        return
            ($.credit.platformCredit() / $.pools[poolId].level) *
            $.config.leverage;
    }

    function getPlatformFee(uint256 value) internal returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        return (value * $.config.platformFeePercent) / 10000;
    }

    // function openLongPosition(
    //     address account,
    //     bytes32 poolId,
    //     uint256 value,
    //     uint256 leverage,
    //     uint256 price,
    //     uint256 plId
    // ) external {
    //     require(
    //         leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
    //         "Invalid leverage"
    //     );
    //     require(value > 0, "Invalid Value");
    //     X1000V2Storage storage $ = _getOwnStorage();
    //     Pool storage pool = $.pools[poolId];
    //     require($.credit.getCredit(account) >= value, "Not Enough Credit");
    //     require(pool.level > 0, "Invalid Pool");

    //     uint256 _size = (value * leverage) / WEI6;
    //     console.log("_size: ", _size);
    //     uint256 _platformFee = getPlatformFee(_size);
    //     console.log("_platformFee: ", _platformFee);
    //     require(_platformFee < value, "Invalid Platform Fee");
    //     _size = ((value - _platformFee) * leverage) / WEI6;
    //     console.log("_size after inject fee: ", _size);
    //     uint256 _position = (_size * WEI6) / price;
    //     console.log("_position: ", _position);
    //     //calculate total long position
    //     uint256 _tempLongPosition = pool.longPosition + _position;
    //     console.log("_tempLongPosition: ", _tempLongPosition);
    //     uint256 _tmpLongSize = pool.longSize + _size;
    //     console.log("_tmpLongSize: ", _tmpLongSize);
    //     //calculate normalize long position
    //     uint256 _normPosition = (_tmpLongSize * WEI6) / price;
    //     console.log("_normPosition: ", _normPosition);
    //     //calculate delta pnl
    //     uint256 _deltaPNL = _tempLongPosition > _normPosition
    //         ? _tempLongPosition - _normPosition
    //         : 0;
    //     console.log("_deltaPNL: ", _deltaPNL);
    //     // if _deltaPNL  > 0 => system is coming to lost
    //     // inject _deltaPNL into formula
    //     uint256 _pLiquid = getPoolLiquidity(poolId);
    //     console.log("_pLiquid: ", _pLiquid);
    //     uint256 _openPrice;
    //     // uint256 _rateLong = _tmpLongSize / $.pools[poolId].shortSize;
    //     if ($.pools[poolId].shortSize > 0) {
    //         _openPrice =
    //             price +
    //             ((price * _size * _tmpLongSize * $.config.burst) / WEI6) /
    //             (_pLiquid + _tmpLongSize - _deltaPNL * price) /
    //             $.pools[poolId].shortSize;
    //     } else {
    //         _openPrice = (((_pLiquid +
    //             _tmpLongSize +
    //             (_size * $.config.burst) /
    //             WEI6 -
    //             _deltaPNL *
    //             price) * price) /
    //             (_pLiquid + _tmpLongSize - _deltaPNL * price));
    //     }
    //     console.log("_price: ", price);
    //     console.log("_openPrice: ", _openPrice);
    //     uint256 _deltaPrice = _openPrice - price;
    //     console.log("_deltaPrice: ", _deltaPrice);
    //     uint256 _openValue = ((_size * (price - _deltaPrice)) * WEI6) /
    //         price /
    //         leverage;
    //     console.log("_openValue: ", _openValue);
    //     uint256 _fee = value - _platformFee - _openValue;
    //     console.log("_fee: ", _fee);
    //     uint256 _openSize = _openValue * leverage;
    //     uint256 _liqPrice = (price *
    //         (leverage - (WEI6 * $.config.rake) / 100)) / leverage;
    //     console.log("_liqPrice: ", _liqPrice);
    //     Position memory newPos = Position(
    //         poolId,
    //         PositionType.LONG,
    //         PositionStatus.OPEN,
    //         _openValue,
    //         leverage,
    //         _openSize,
    //         uint88(price),
    //         uint88(price),
    //         uint88(_liqPrice),
    //         0,
    //         account
    //     );
    //     $.lastPosId++;
    //     $.positions[$.lastPosId] = newPos;
    //     pool.longSize = _tmpLongSize;
    //     pool.longPosition = _tempLongPosition;
    //     $.credit.transferFrom(account, value, _fee + _platformFee);
    // }

    // function openShortPosition(
    //     address account,
    //     bytes32 poolId,
    //     uint256 value,
    //     uint256 leverage,
    //     uint256 price,
    //     uint256 plId
    // ) external {
    //     require(
    //         leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
    //         "Invalid leverage"
    //     );
    //     require(value > 0, "Invalid Value");
    //     X1000V2Storage storage $ = _getOwnStorage();
    //     Pool storage pool = $.pools[poolId];
    //     require($.credit.getCredit(account) >= value, "Not Enough Credit");
    //     require(pool.level > 0, "Invalid Pool");
    //     uint256 _size = (value * leverage) / WEI6;
    //     uint256 _platformFee = getPlatformFee(_size);
    //     require(_platformFee < value, "Invalid Platform Fee");
    //     _size = ((value - _platformFee) * leverage) / WEI6;
    //     uint256 _position = (_size * WEI6) / price;
    //     //calculate total short position
    //     uint256 _tempShortPosition = pool.shortPosition + _position;
    //     uint256 _tmpShortSize = pool.shortSize + _size;
    //     //calculate normalize long position
    //     uint256 _normPosition = (_tmpShortSize * WEI6) / price;
    //     //calculate delta pnl
    //     uint256 _deltaPNL = _tempShortPosition < _normPosition
    //         ? _normPosition - _tempShortPosition
    //         : 0;
    //     uint256 _pLiquid = getPoolLiquidity(poolId);
    //     uint256 _openPrice;
    //     // uint256 _rateShort = _tmpShortSize / $.pools[poolId].longSize;
    //     if ($.pools[poolId].longSize > 0) {
    //         _openPrice =
    //             price -
    //             ((price * _size * _tmpShortSize * $.config.burst) / WEI6) /
    //             (_pLiquid + _tmpShortSize - _deltaPNL * price) /
    //             $.pools[poolId].longSize;
    //     } else {
    //         _openPrice = (((_pLiquid +
    //             _tmpShortSize -
    //             (_size * $.config.burst) /
    //             WEI6 -
    //             _deltaPNL *
    //             price) * price) /
    //             (_pLiquid + _tmpShortSize - _deltaPNL * price));
    //     }
    //     console.log("price: ", price);
    //     console.log("openPrice: ", _openPrice);
    //     uint256 _deltaPrice = price - _openPrice;
    //     console.log("_deltaPrice: ", _deltaPrice);
    //     require(price > _deltaPrice, "Invalid Delta Price");
    //     uint256 _openValue = (_size * (price - _deltaPrice) * WEI6) /
    //         price /
    //         leverage;
    //     console.log("_openValue: ", _openValue);
    //     uint256 _fee = value - _platformFee - _openValue;
    //     console.log("_fee: ", _fee);
    //     uint256 _openSize = _openValue * leverage;
    //     uint256 _liqPrice = (price *
    //         (leverage + (WEI6 * $.config.rake) / 100)) / leverage;
    //     console.log("_liqPrice: ", _liqPrice);
    //     Position memory newPos = Position(
    //         poolId,
    //         PositionType.SHORT,
    //         PositionStatus.OPEN,
    //         _openValue,
    //         leverage,
    //         _openSize,
    //         uint88(price),
    //         uint88(price),
    //         uint88(_liqPrice),
    //         0,
    //         account
    //     );
    //     $.lastPosId++;
    //     $.positions[$.lastPosId] = newPos;
    //     pool.shortSize = _tmpShortSize;
    //     pool.shortPosition = _tempShortPosition;
    //     $.credit.transferFrom(account, value, _fee + _platformFee);
    // }

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
        uint256 _openValue = value - _platformFee;
        uint256 _openSize = (_openValue * leverage) / WEI6;
        uint256 _expectPrice = _getLongExpectPrice(
            account,
            poolId,
            value,
            leverage,
            price
        );
        uint256 _liqPrice = (price *
            (leverage - (WEI6 * $.config.rake) / 100)) / leverage;
        Position memory newPos = Position(
            poolId,
            PositionType.LONG,
            PositionStatus.OPEN,
            _openValue,
            leverage,
            _openSize,
            uint88(price),
            uint88(price),
            uint88(_liqPrice),
            0,
            uint88(_expectPrice),
            account
        );
        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;
        pool.longSize += _openSize;
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
            account,
            poolId,
            value,
            leverage,
            price
        );
        uint256 _liqPrice = (price *
            (leverage + (WEI6 * $.config.rake) / 100)) / leverage;
        Position memory newPos = Position(
            poolId,
            PositionType.SHORT,
            PositionStatus.OPEN,
            _openValue,
            leverage,
            _openSize,
            uint88(price),
            uint88(price),
            uint88(_liqPrice),
            0,
            uint88(_expectPrice),
            account
        );
        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;
        pool.shortSize += _openSize;
        pool.shortPosition += (_openSize * WEI6) / price;
        $.credit.transferFrom(account, value, _platformFee);
        emit OpenPosition(
            $.lastPosId,
            value,
            leverage,
            price,
            price,
            _liqPrice,
            _expectPrice,
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
        require(pos.status == PositionStatus.OPEN, "Invalid Position Status");
        uint256 _size = (pos.amount * pos.leverage) / WEI6;
        //calculate position pnl
        uint256 _pnl = pos.ptype == PositionType.LONG
            ? price > pos.openPrice
                ? (_size * price - _size * pos.openPrice) / pos.openPrice
                : 0
            : price < pos.openPrice
            ? (_size * pos.openPrice - _size * price) / pos.openPrice
            : 0;
        uint256 _pnlGap = pos.ptype == PositionType.LONG
            ? pos.expectPrice - pos.openPrice
            : pos.openPrice - pos.expectPrice;
        if (_pnl > 0) {
            //calculate fee
            console.log("_pnl: ", _pnl);
            console.log("price: ", price);
            console.log("openPrice: ", pos.openPrice);
            console.log("expectPrice: ", pos.expectPrice);
            uint256 _profitFee = _getProfitFee(
                price,
                pos.expectPrice,
                _pnl,
                _pnlGap,
                pos.ptype
            );
            console.log("_profitFee: ", _profitFee);
            //caculate returnValue
            uint256 _returnValue = pos.amount + _pnl - _profitFee;
            console.log("_returnValue: ", _returnValue);
            //update position status
            pos.status = PositionStatus.CLOSED;
            pos.closePrice = uint88(price);
            if (pos.ptype == PositionType.LONG) {
                pool.longSize -= pos.size;
                pool.longPosition -= (pos.size * WEI6) / pos.openPrice;
            } else {
                pool.shortSize -= pos.size;
                pool.shortPosition -= (pos.size * WEI6) / pos.openPrice;
            }
            $.credit.transfer(pos.user, _returnValue, _profitFee);
        } else {
            uint256 _returnValue = pos.ptype == PositionType.LONG
                ? pos.amount -
                    ((pos.openPrice - price) * pos.size) /
                    pos.openPrice
                : pos.amount -
                    ((price - pos.openPrice) * pos.size) /
                    pos.openPrice;
            console.log("_returnValue: ", _returnValue);
            if (pos.ptype == PositionType.LONG) {
                pool.longSize -= pos.size;
                pool.longPosition -= (pos.size * WEI6) / pos.openPrice;
            } else {
                pool.shortSize -= pos.size;
                pool.shortPosition -= (pos.size * WEI6) / pos.openPrice;
            }
            $.credit.transfer(pos.user, _returnValue, 0);
        }
        emit ClosePosition(posId, price);
    }

    function burnPosition(
        uint256 posId
    ) public onlyFrom(BATCHING) returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        if (
            $.positions[posId].status != PositionStatus.CLOSED &&
            $.positions[posId].status != PositionStatus.BURNT
        ) {
            $.positions[posId].status = PositionStatus.BURNT;
            Position storage pos = $.positions[posId];
            if (pos.ptype == PositionType.LONG) {
                $.pools[pos.poolId].longSize -= pos.size;
                $.pools[pos.poolId].longPosition -=
                    (pos.size * WEI6) /
                    pos.openPrice;
            } else {
                $.pools[pos.poolId].shortSize -= pos.size;
                $.pools[pos.poolId].shortPosition -=
                    (pos.size * WEI6) /
                    pos.openPrice;
            }
            return (posId);
        }
    }

    //////////////////////////////////////////
    /////////////// GETTER //////////////////////
    ////////////////////////////////////////
    function getLongPosition(
        uint256 posId
    ) external view returns (Position memory) {
        X1000V2Storage storage $ = _getOwnStorage();
        return $.positions[posId];
    }

    //////////////////////////////////////////
    /////////////// PRIVATE //////////////////////
    ////////////////////////////////////////
    function _getLongExpectPrice(
        address account,
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
        //calculate total long position
        uint256 _tempLongPosition = pool.longPosition + _position;
        uint256 _tmpLongSize = pool.longSize + _size;
        //calculate normalize long position
        uint256 _normPosition = (_tmpLongSize * WEI6) / price;
        //calculate delta pnl
        uint256 _deltaPNL = _tempLongPosition > _normPosition
            ? _tempLongPosition - _normPosition
            : 0;
        // if _deltaPNL  > 0 => system is coming to lost
        // inject _deltaPNL into formula
        uint256 _pLiquid = getPoolLiquidity(poolId);
        uint256 _openPrice;
        // uint256 _rateLong = _tmpLongSize / $.pools[poolId].shortSize;
        if ($.pools[poolId].shortSize > 0) {
            _openPrice =
                price +
                ((price * _size * _tmpLongSize * $.config.burst) / WEI6) /
                (_pLiquid + _tmpLongSize - _deltaPNL * price) /
                $.pools[poolId].shortSize;
        } else {
            _openPrice = (((_pLiquid +
                _tmpLongSize +
                (_size * $.config.burst) /
                WEI6 -
                _deltaPNL *
                price) * price) /
                (_pLiquid + _tmpLongSize - _deltaPNL * price));
        }
        return _openPrice;
    }

    function _getShortExpectPrice(
        address account,
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
                (_pLiquid + _tmpShortSize - _deltaPNL * price) /
                $.pools[poolId].longSize;
        } else {
            _openPrice = (((_pLiquid +
                _tmpShortSize -
                (_size * $.config.burst) /
                WEI6 -
                _deltaPNL *
                price) * price) /
                (_pLiquid + _tmpShortSize - _deltaPNL * price));
        }
        return _openPrice;
    }

    function _getProfitFee(
        uint256 closePrice,
        uint256 expectPrice,
        uint256 pnl,
        uint256 pnlGap,
        PositionType ptype
    ) private returns (uint256) {
        X1000V2Storage storage $ = _getOwnStorage();
        if (ptype == PositionType.LONG) {
            if (closePrice < expectPrice) {
                return ($.config.profitUnderExpectValue * pnl) / 100;
            } else {
                console.log("run here 123");
                uint256 _fee = ($.config.profitUnderExpectValue * pnlGap) /
                    100 +
                    ($.config.profitOverExpectValue * (pnl - pnlGap)) /
                    100;
                console.log("_fee: ", _fee);
                return _fee;
            }
        } else {
            if (closePrice > expectPrice) {
                console.log("run here 234");
                return ($.config.profitUnderExpectValue * pnl) / 100;
            } else {
                uint256 _fee = ($.config.profitUnderExpectValue * pnlGap) /
                    100 +
                    ($.config.profitOverExpectValue * (pnl - pnlGap)) /
                    100;
                console.log("_fee: ", _fee);
                return _fee;
            }
        }
    }
}
