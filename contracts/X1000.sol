// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Credit.sol";
import "./libs/Base.sol";

import "hardhat/console.sol";

struct Config {
    uint256 gap;
    mapping(uint8 => uint64) poolLevels; // pool level => size, maximum WEI6 => full size
    uint256 leverage;
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

contract X1000 is OwnableUpgradeable, Base {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BATCHING = keccak256("BATCHING");
    uint64 public constant WEI6 = 10 ** 6; // base for calculation
    uint64 public constant PRICE_WEI = 10 ** 8; // base for calculation
    // Position types
    uint8 public constant POSITION_TYPE_LONG = 1;
    uint8 public constant POSITION_TYPE_SHORT = 2;
    // Position status
    uint8 public constant POSITION_STATUS_OPEN = 1;
    uint8 public constant POSITION_STATUS_CLOSED = 2;
    uint8 public constant POSITION_STATUS_BURNT = 3;

    event OpenPosition(
        uint256 pid,
        uint256 value,
        uint256 leverage,
        uint256 inPrice,
        uint88 openPrice,
        uint256 burnPrice,
        uint64 position,
        uint256 openFee,
        uint64 lpos,
        uint64 spos,
        uint256 lvalue,
        uint256 svalue
    );

    event ClosePosition(
        uint256 pid,
        uint256 returnAmount,
        uint256 feeAmount,
        uint256 closePrice,
        uint64 lpos,
        uint64 spos,
        uint256 lvalue,
        uint256 svalue
    );

    event BurnPosition(
        uint256[] positionIds,
        uint64[] lpos,
        uint64[] spos,
        uint256[] lvalue,
        uint256[] svalue
    );

    struct X1000Storage {
        Config config;
        Credit credit;
        mapping(uint256 => Position) positions;
        uint256 lastPosId;
        // pool
        mapping(bytes32 => Pool) pools;
    }

    // keccak256(abi.encode(uint256(keccak256("goal3.storage.X1000")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant X1000StorageLocation =
        0x61ac7db12115f048078a0d98a419d1b6e0364eec44a215b3bd04f8734bdacc00;

    function _getOwnStorage() private pure returns (X1000Storage storage $) {
        assembly {
            $.slot := X1000StorageLocation
        }
    }

    function initialize(
        address bookieAddress,
        address creditContractAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __Base_init(bookieAddress);

        X1000Storage storage $ = _getOwnStorage();
        for (uint8 i = 1; i < 10; i++) $.config.poolLevels[i] = WEI6 / i;
        // init default ETH, BTC pool
        $.pools[bytes32("BTC")].level = 1;
        $.pools[bytes32("ETH")].level = 1;
        // system leverage
        $.config.leverage = 100;
        $.credit = Credit(creditContractAddress);
    }

    //////////////////
    ///// SYSTEM /////
    //////////////////
    function burnPosition(uint256 posId) external onlyRole(OPERATOR_ROLE) {}

    // force close a position by system
    function forceClosePosition(
        uint256 posId,
        uint256 price
    ) external onlyRole(OPERATOR_ROLE) {
        // verify call from system

        _closePosition(posId, price);
    }

    // function openPositions(
    //     OpenPositionParams[] memory positions
    // ) external onlyRole(OPERATOR_ROLE) {
    //     PositionExecutionResult[]
    //         memory executionResults = new PositionExecutionResult[](
    //             positions.length
    //         );
    //     for (uint i = 0; i < positions.length; i++) {
    //         if (positions[i].isLong) {
    //             // tryOpenLongPosition(
    //             //     positions[i].account,
    //             //     positions[i].poolId,
    //             //     positions[i].value,
    //             //     positions[i].leverage,
    //             //     positions[i].price,
    //             //     executionResults
    //             // );
    //             PositionExecutionResult memory result;
    //             try
    //                 _openLongPosition(
    //                     positions[i].account,
    //                     positions[i].poolId,
    //                     positions[i].value,
    //                     positions[i].leverage,
    //                     positions[i].price
    //                 )
    //             {
    //                 // Thành công, không làm gì cả
    //                 result.success = true;
    //             } catch Error(string memory errorMessage) {
    //                 // Xử lý lỗi nếu cần thiết
    //                 result.success = false;
    //                 result.errorMessage = errorMessage;
    //             } catch (bytes memory) {
    //                 // Xử lý lỗi nếu cần thiết
    //                 result.success = false;
    //                 result.errorMessage = "Unknown error";
    //             }
    //             executionResults.push(result);
    //         } else {
    //             // tryOpenShortPosition(
    //             //     positions[i].account,
    //             //     positions[i].poolId,
    //             //     positions[i].value,
    //             //     positions[i].leverage,
    //             //     positions[i].price,
    //             //     executionResults
    //             // );
    //             PositionExecutionResult memory result;
    //             try
    //                 _openShortPosition(
    //                     positions[i].account,
    //                     positions[i].poolId,
    //                     positions[i].value,
    //                     positions[i].leverage,
    //                     positions[i].price
    //                 )
    //             {
    //                 // Thành công, không làm gì cả
    //                 result.success = true;
    //             } catch Error(string memory errorMessage) {
    //                 // Xử lý lỗi nếu cần thiết
    //                 result.success = false;
    //                 result.errorMessage = errorMessage;
    //             } catch (bytes memory) {
    //                 // Xử lý lỗi nếu cần thiết
    //                 result.success = false;
    //                 result.errorMessage = "Unknown error";
    //             }
    //             executionResults.push(result);
    //         }
    //     }
    //     for (uint i = 0; i < executionResults.length; i++) {
    //         if (!executionResults[i].success) {
    //             emit OpenPositionFailed(positions[i].plId);
    //         }
    //     }
    // }

    // function tryOpenLongPosition(
    //     address account,
    //     bytes32 poolId,
    //     uint256 value,
    //     uint256 leverage,
    //     uint256 price,
    //     PositionExecutionResult[] memory results
    // ) internal {
    //     PositionExecutionResult memory result;
    //     try _openLongPosition(account, poolId, value, leverage, price) {
    //         // Thành công, không làm gì cả
    //         result.success = true;
    //     } catch Error(string memory errorMessage) {
    //         // Xử lý lỗi nếu cần thiết
    //         result.success = false;
    //         result.errorMessage = errorMessage;
    //     } catch (bytes memory) {
    //         // Xử lý lỗi nếu cần thiết
    //         result.success = false;
    //         result.errorMessage = "Unknown error";
    //     }
    // }

    // function tryOpenShortPosition(
    //     address account,
    //     bytes32 poolId,
    //     uint256 value,
    //     uint256 leverage,
    //     uint256 price,
    //     PositionExecutionResult[] memory results
    // ) internal {
    //     PositionExecutionResult memory result;
    //     try _openShortPosition(account, poolId, value, leverage, price) {
    //         // Thành công, không làm gì cả
    //         result.success = true;
    //     } catch Error(string memory errorMessage) {
    //         // Xử lý lỗi nếu cần thiết
    //         result.success = false;
    //         result.errorMessage = errorMessage;
    //     } catch (bytes memory) {
    //         // Xử lý lỗi nếu cần thiết
    //         result.success = false;
    //         result.errorMessage = "Unknown error";
    //     }
    // }

    ///////////////////////
    ///// USER ACTION /////
    ///////////////////////
    function openLongPosition(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) public onlyFrom(BATCHING) {
        // verify input
        _openLongPosition(account, poolId, value, leverage, price);
    }

    function openShortPosition(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) public onlyFrom(BATCHING) {
        // verify input
        _openShortPosition(account, poolId, value, leverage, price);
    }

    function closePosition(uint256 posId, uint256 price) external {
        X1000Storage storage $ = _getOwnStorage();
        Position storage pos = $.positions[posId];
        require(pos.user == msg.sender, "Owner Call Only");

        _closePosition(posId, price);
    }

    /*
    // Close using short/long price
    function _closePosition2(uint256 posId) internal {
        X1000Storage storage $ = _getOwnStorage();
        Position storage pos = $.positions[posId];
        Pool storage pool = $.pools[pos.poolId];
        require(pos.status == POSITION_STATUS_OPEN, "Invalid Position Status");

        uint256 _size = pos.size;
        bytes32 _poolId = pos.poolId;
        uint256 _amount = pos.amount;
        uint256 _leverage = pos.leverage;
        uint256 _value = (_amount * _leverage) / WEI6;
        uint256 _returnValue;
        uint88 _closePrice;
        uint88 _atPrice;
        if (pos.ptype == POSITION_TYPE_LONG) {
            // sell current open position to pool
            uint256 _amountMargin = _value - _amount;
            (_returnValue, _closePrice, _atPrice) = getShortValue(
                _poolId,
                _size
            );
            if (_atPrice <= pos.liqPrice || _returnValue <= _amountMargin) {
                // burn
                pos.status = POSITION_STATUS_BURNT;
                pos.closePrice = _atPrice;
            } else {
                _returnValue -= _amountMargin;
            }
            // update pool data
            pool.lpos -= pos.size;
            pool.lvalue =
                pool.lvalue +
                _amount -
                (pos.size * pos.atPrice) /
                WEI6;
        } else {
            uint256 _amountMargin = _value + _amount;
            (_returnValue, _closePrice, _atPrice) = getLongValue(
                _poolId,
                _size
            );
            if (_atPrice >= pos.liqPrice || _returnValue >= _amountMargin) {
                // burn
                pos.status = POSITION_STATUS_BURNT;
                pos.closePrice = _atPrice;
            } else {
                _returnValue = _amountMargin - _returnValue;
            }
            // update pool data
            pool.spos -= pos.size;
            pool.svalue =
                pool.svalue +
                (pos.size * pos.atPrice) /
                WEI6 -
                _amount;
        }
        // not burnt
        if (pos.status == POSITION_STATUS_OPEN) {
            // calculate return credit
            (uint256 _returnAmount, uint256 _feeAmount) = liquidFee(
                _amount,
                _leverage,
                _returnValue
            );
            // transfer credit
            $.credit.balances[pos.user] += _returnAmount;
            $.credit.fee += _feeAmount;
            $.credit.platform -= (_returnAmount + _feeAmount);

            // update status
            pos.status = POSITION_STATUS_CLOSED;
            pos.closePrice = _closePrice;
        }
    }
*/
    // Close using current price index
    function _openLongPosition(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) private {
        require(
            leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
            "Invalid leverage"
        );
        require(value > 0, "Invalid Value");
        X1000Storage storage $ = _getOwnStorage();
        Pool storage pool = $.pools[poolId];
        require($.credit.getCredit(account) >= value, "Not Enough Credit");
        require(pool.level > 0, "Invalid Pool");

        uint256 _value = (value * leverage) / WEI6;
        uint256 _fee = platformFee(_value);
        require(_fee < value, "Too high fee");
        (uint64 _pos, uint88 _atPrice) = getLongPosition(
            poolId,
            _value - _fee,
            leverage,
            price
        );
        uint88 _openPrice = uint88((_value * WEI6) / _pos);
        // calculate liquid price
        uint256 _liqPrice = (_openPrice * (leverage - WEI6)) / leverage;
        console.log("Price:", _atPrice, _openPrice, _liqPrice);
        console.log(
            "Price:",
            _value,
            _value - _fee,
            ((_value - _fee) * WEI6) / _pos
        );
        require(_liqPrice < _atPrice, "Error");

        // new position
        Position memory newPos = Position(
            poolId,
            POSITION_TYPE_LONG,
            POSITION_STATUS_OPEN,
            uint64(value),
            uint32(leverage),
            _pos,
            _openPrice,
            _atPrice,
            uint88(_liqPrice),
            0,
            account
        );

        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;

        // update pool data
        pool.lpos += _pos;
        pool.lvalue += (_pos * _atPrice) / WEI6 - value;

        // transfer credit
        $.credit.setCredit(account, $.credit.getCredit(account) - value);
        $.credit.setFee($.credit.getFee() + _fee);
        $.credit.setPlatform($.credit.platformCredit() + (value - _fee));
        emit OpenPosition(
            $.lastPosId,
            value,
            leverage,
            price,
            _openPrice,
            _liqPrice,
            _pos,
            _fee,
            pool.lpos,
            pool.spos,
            pool.lvalue,
            pool.svalue
        );
    }

    function _openShortPosition(
        address account,
        bytes32 poolId,
        uint256 value,
        uint256 leverage,
        uint256 price
    ) private {
        require(
            leverage >= 2 * WEI6 && leverage <= 1000 * WEI6,
            "Invalid leverage"
        );
        require(value > 0, "Invalid Value");
        X1000Storage storage $ = _getOwnStorage();
        Pool storage pool = $.pools[poolId];
        require($.credit.getCredit(account) >= value, "Not Enough Credit");
        require(pool.level > 0, "Invalid Pool");

        uint256 _value = (value * leverage) / WEI6;
        uint256 _fee = platformFee(_value);
        require(_fee < value, "Too high fee");
        (uint64 _pos, uint88 _atPrice) = getShortPosition(
            poolId,
            _value + _fee,
            leverage,
            price
        );
        uint88 _openPrice = uint88((_value * WEI6) / _pos);

        // calculate liquid price
        // uint256 _liqPrice = (_openPrice * (10_003 * leverage + 10_000 * WEI6)) /
        //     10_000 /
        //     leverage;
        uint256 _liqPrice = (_openPrice * (leverage + WEI6)) / leverage;
        require(_liqPrice > _atPrice, "Error");

        // new position
        Position memory newPos = Position(
            poolId,
            POSITION_TYPE_SHORT,
            POSITION_STATUS_OPEN,
            uint64(value),
            uint32(leverage),
            _pos,
            _openPrice,
            _atPrice,
            uint88(_liqPrice),
            0,
            account
        );

        $.lastPosId++;
        $.positions[$.lastPosId] = newPos;

        // update pool data
        pool.spos += _pos;
        pool.svalue += (_pos * _atPrice) / WEI6 + value;

        // transfer credit
        $.credit.setCredit(account, $.credit.getCredit(account) - value);
        $.credit.setFee($.credit.getFee() + _fee);
        $.credit.setPlatform($.credit.platformCredit() + value - _fee);
        emit OpenPosition(
            $.lastPosId,
            value,
            leverage,
            price,
            _openPrice,
            _liqPrice,
            _pos,
            _fee,
            pool.lpos,
            pool.spos,
            pool.lvalue,
            pool.svalue
        );
    }

    function _closePosition(uint256 posId, uint256 price) internal {
        X1000Storage storage $ = _getOwnStorage();
        Position storage pos = $.positions[posId];
        Pool storage pool = $.pools[pos.poolId];
        require(pos.status == POSITION_STATUS_OPEN, "Invalid Position Status");

        uint256 _value = (pos.amount * pos.leverage) / WEI6;
        uint256 _returnValue;
        (uint256 _closeValue, uint88 _atPrice) = getCloseValue(pos.size, price);
        if (pos.ptype == POSITION_TYPE_LONG) {
            // sell current open position to pool
            uint256 _amountMargin = _value - pos.amount;
            if (_atPrice <= pos.liqPrice || _closeValue <= _amountMargin) {
                // burn
                pos.status = POSITION_STATUS_BURNT;
                pos.closePrice = _atPrice;
            } else {
                _returnValue = _closeValue - _amountMargin;
            }
            // update pool data
            pool.lpos -= pos.size;
            pool.lvalue =
                pool.lvalue +
                pos.amount -
                (pos.size * pos.atPrice) /
                WEI6;
        } else {
            uint256 _amountMargin = _value + pos.amount;
            if (_atPrice >= pos.liqPrice || _closeValue >= _amountMargin) {
                // burn
                pos.status = POSITION_STATUS_BURNT;
                pos.closePrice = _atPrice;
            } else {
                _returnValue = _amountMargin - _closeValue;
            }
            // update pool data
            pool.spos -= pos.size;
            pool.svalue =
                pool.svalue -
                (pos.size * pos.atPrice) /
                WEI6 -
                pos.amount;
        }
        // not burnt
        if (pos.status == POSITION_STATUS_OPEN) {
            // calculate return credit
            (uint256 _returnAmount, uint256 _feeAmount) = liquidFee(
                pos.amount,
                pos.leverage,
                _returnValue
            );
            // transfer credit
            $.credit.setCredit(
                pos.user,
                $.credit.getCredit(pos.user) + _returnAmount
            );
            $.credit.setFee($.credit.getFee() + _feeAmount);
            $.credit.setPlatform(
                $.credit.platformCredit() - (_returnAmount + _feeAmount)
            );

            // update status
            pos.status = POSITION_STATUS_CLOSED;
            pos.closePrice = _atPrice;
        }
    }

    ///// SETTER /////
    function setPoolLevel(bytes32 poolId, uint8 level) external {
        X1000Storage storage $ = _getOwnStorage();
        $.pools[poolId].level = level;
    }

    //////////////////
    ///// GETTER /////
    //////////////////
    /**
     * Returns the latest price of ETH
     */
    // function getLatestEthPrice() public view returns (uint256) {
    //     bytes32 dataFeedId = bytes32("ETH");
    //     return getOracleNumericValueFromTxMsg(dataFeedId);
    // }

    // function getPrice(bytes32 poolId) public view returns (uint256 price) {
    //     price = (getOracleNumericValueFromTxMsg(poolId) * WEI6) / PRICE_WEI;
    // }

    // function getLongValue(
    //     bytes32 poolId,
    //     uint256 amountIn,
    //     uint256 leverage
    // ) public view returns (uint256 valueOut, uint88 longPrice, uint88 atPrice) {
    //     atPrice = uint88(getPrice(poolId));
    //     // pool value by credit and level
    //     (uint256 _poolValue, uint256 _poolAmount) = _lpair(poolId, leverage);
    //     // calculate long price
    //     valueOut =
    //         ((_poolValue * _poolValue) * WEI6) /
    //         atPrice /
    //         (_poolAmount - amountIn) -
    //         _poolValue;
    //     longPrice = uint88((valueOut * WEI6) / amountIn);
    // }

    function getPool(bytes32 poolId) internal view returns (Pool memory) {
        X1000Storage storage $ = _getOwnStorage();
        return $.pools[poolId];
    }

    function getLongPosition(
        bytes32 poolId,
        uint256 valueIn,
        uint256 leverage,
        uint256 price
    ) public view returns (uint64 pos, uint88 atPrice) {
        atPrice = uint88(price);
        // pool value by credit and level
        (uint256 _poolValue, ) = _lpair(poolId, leverage, price);
        /*
        // calculate long position
        pos = uint64(
            _poolAmount -
                ((_poolValue * _poolValue) * WEI6) /
                atPrice /
                (_poolValue + valueIn)
        );
        */
        pos = uint64(
            (_poolValue * valueIn * WEI6) / atPrice / (_poolValue + valueIn)
        );
    }

    function getShortValue(
        bytes32 poolId,
        uint256 amountIn,
        uint256 leverage,
        uint256 price
    )
        public
        view
        returns (uint256 valueOut, uint88 shortPrice, uint88 atPrice)
    {
        atPrice = uint88(price);
        // pool value by credit and level
        (uint256 _poolValue, uint256 _poolAmount) = _spair(
            poolId,
            leverage,
            price
        );
        // calculate long price
        valueOut =
            _poolValue -
            (_poolValue * _poolValue * WEI6) /
            atPrice /
            (_poolAmount + amountIn);
        shortPrice = uint88((valueOut * WEI6) / amountIn);
    }

    function getShortPosition(
        bytes32 poolId,
        uint256 valueIn,
        uint256 leverage,
        uint256 price
    ) public view returns (uint64 pos, uint88 atPrice) {
        atPrice = uint88(price);
        // pool value by credit and level
        (uint256 _poolValue, ) = _spair(poolId, leverage, price);
        // calculate long price
        /*
        pos = uint64(
            ((_poolValue * _poolValue) * WEI6) /
                atPrice /
                (_poolValue - valueIn) -
                _poolAmount
        );
        */

        pos = uint64(
            (_poolValue * valueIn * WEI6) / atPrice / (_poolValue + valueIn)
        );
    }

    function getCloseValue(
        uint256 amountIn,
        uint256 price
    ) public view returns (uint256 valueOut, uint88 atPrice) {
        atPrice = uint88(price);
        valueOut = (atPrice * amountIn) / WEI6;
    }

    function lastPositionId() external view returns (uint256) {
        X1000Storage storage $ = _getOwnStorage();
        return $.lastPosId;
    }

    function platformFee(
        uint256 value
    ) public pure returns (uint256 feeAmount) {
        return (value * 4) / 10_000; // 0.04%
    }

    function liquidFee(
        uint256 amount,
        uint256 leverage,
        uint256 value
    ) public pure returns (uint256 returnAmount, uint256 feeAmount) {
        uint256 _amountIn = amount;
        if (_amountIn < value) {
            uint256 _profit = value - _amountIn;
            feeAmount = _profit / 10; // 10%
            // and liquid fee leverage
            feeAmount += (_profit * leverage * 2) / (WEI6 * 10_000);
        }
        returnAmount = value - feeAmount;
    }

    function position(uint256 posId) external view returns (Position memory) {
        X1000Storage storage $ = _getOwnStorage();
        return $.positions[posId];
    }

    ////////////////////
    ///// INTERNAL /////
    ////////////////////
    function _lpair(
        bytes32 poolId,
        uint256 leverage,
        uint256 price
    ) internal view returns (uint256 value, uint256 amount) {
        X1000Storage storage $ = _getOwnStorage();
        // bytes32 ethId = bytes32("ETH");
        Pool storage pool = $.pools[poolId];
        // pool value by credit and level
        uint256 _value = ($.credit.platformCredit() *
            $.config.poolLevels[pool.level]) / WEI6;
        // adjust with current open position & value
        _value = _value + pool.lvalue - (pool.lpos * price) / WEI6; // if may cause error _value < 0
        // and apply platform leverage
        _value *= _sqrt(($.config.leverage * leverage) / WEI6);
        amount = (_value * WEI6) / price;
        value = _value;
        /*
        // pool value by credit and level
        value = (($.credit.platform *
            $.config.poolLevels[pool.level] *
            $.config.leverage) / WEI6);
        // adjust with current open position & value
        uint256 _adjPoolValue = value +
            pool.lvalue -
            (pool.lpos * _price) /
            WEI6;
        amount = (_adjPoolValue * WEI6) / _price;
        value = _adjPoolValue;
        */
    }

    function _spair(
        bytes32 poolId,
        uint256 leverage,
        uint256 price
    ) internal view returns (uint256 value, uint256 amount) {
        X1000Storage storage $ = _getOwnStorage();
        // bytes32 ethId = bytes32("ETH");
        Pool storage pool = $.pools[poolId];
        // pool value by credit and level
        uint256 _value = ($.credit.platformCredit() *
            $.config.poolLevels[pool.level]) / WEI6;
        // adjust with current open position & value
        _value = _value + (pool.spos * price) / WEI6 - pool.svalue; // if may cause error _value < 0
        // and apply platform leverage
        _value *= _sqrt(($.config.leverage * leverage) / WEI6);

        amount = (_value * WEI6) / price;
        value = _value;
        /*        
        // pool value by credit and level
        value = (($.credit.platform *
            $.config.poolLevels[pool.level] *
            $.config.leverage) / WEI6);
        // adjust with current open position & value
        uint256 _adjPoolValue = value +
            (pool.spos * _price) /
            WEI6 -
            pool.svalue;
        amount = (_adjPoolValue * WEI6) / _price;
        value = _adjPoolValue;
        */
    }

    function _sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
