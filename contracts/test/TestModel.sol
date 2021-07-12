pragma solidity ^0.8.0;


interface IERC173 {
    event OwnershipTransferred(address indexed _previousOwner, address indexed _newOwner);

    function transferOwnership(address _newOwner) external;
}


contract Ownable is IERC173 {
    address internal _owner;

    modifier onlyOwner() {
        require(msg.sender == _owner, "The owner should be the sender");
        _;
    }

    constructor() public {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0x0), msg.sender);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    /**
        @dev Transfers the ownership of the contract.

        @param _newOwner Address of the new owner
    */
    function transferOwnership(address _newOwner) external override onlyOwner {
        require(_newOwner != address(0), "0x0 Is not a valid owner");
        emit OwnershipTransferred(_owner, _newOwner);
        _owner = _newOwner;
    }
}


contract BytesUtils {
    function readBytes32(bytes memory data, uint256 index) internal pure returns (bytes32 o) {
        require(data.length / 32 > index, "Reading bytes out of bounds");
        assembly {
            o := mload(add(data, add(32, mul(32, index))))
        }
    }

    function read(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes32 o) {
        require(data.length >= offset + length, "Reading bytes out of bounds");
        assembly {
            o := mload(add(data, add(32, offset)))
            let lb := sub(32, length)
            if lb { o := div(o, exp(2, mul(lb, 8))) }
        }
    }

    function decode(
        bytes memory _data,
        uint256 _la
    ) internal pure returns (bytes32 _a) {
        require(_data.length >= _la, "Reading bytes out of bounds");
        assembly {
            _a := mload(add(_data, 32))
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
        }
    }

    function decode(
        bytes memory _data,
        uint256 _la,
        uint256 _lb
    ) internal pure returns (bytes32 _a, bytes32 _b) {
        uint256 o;
        assembly {
            let s := add(_data, 32)
            _a := mload(s)
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
            o := add(s, _la)
            _b := mload(o)
            l := sub(32, _lb)
            if l { _b := div(_b, exp(2, mul(l, 8))) }
            o := sub(o, s)
        }
        require(_data.length >= o, "Reading bytes out of bounds");
    }

    function decode(
        bytes memory _data,
        uint256 _la,
        uint256 _lb,
        uint256 _lc
    ) internal pure returns (bytes32 _a, bytes32 _b, bytes32 _c) {
        uint256 o;
        assembly {
            let s := add(_data, 32)
            _a := mload(s)
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
            o := add(s, _la)
            _b := mload(o)
            l := sub(32, _lb)
            if l { _b := div(_b, exp(2, mul(l, 8))) }
            o := add(o, _lb)
            _c := mload(o)
            l := sub(32, _lc)
            if l { _c := div(_c, exp(2, mul(l, 8))) }
            o := sub(o, s)
        }
        require(_data.length >= o, "Reading bytes out of bounds");
    }

    function decode(
        bytes memory _data,
        uint256 _la,
        uint256 _lb,
        uint256 _lc,
        uint256 _ld
    ) internal pure returns (bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d) {
        uint256 o;
        assembly {
            let s := add(_data, 32)
            _a := mload(s)
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
            o := add(s, _la)
            _b := mload(o)
            l := sub(32, _lb)
            if l { _b := div(_b, exp(2, mul(l, 8))) }
            o := add(o, _lb)
            _c := mload(o)
            l := sub(32, _lc)
            if l { _c := div(_c, exp(2, mul(l, 8))) }
            o := add(o, _lc)
            _d := mload(o)
            l := sub(32, _ld)
            if l { _d := div(_d, exp(2, mul(l, 8))) }
            o := sub(o, s)
        }
        require(_data.length >= o, "Reading bytes out of bounds");
    }

    function decode(
        bytes memory _data,
        uint256 _la,
        uint256 _lb,
        uint256 _lc,
        uint256 _ld,
        uint256 _le
    ) internal pure returns (bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d, bytes32 _e) {
        uint256 o;
        assembly {
            let s := add(_data, 32)
            _a := mload(s)
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
            o := add(s, _la)
            _b := mload(o)
            l := sub(32, _lb)
            if l { _b := div(_b, exp(2, mul(l, 8))) }
            o := add(o, _lb)
            _c := mload(o)
            l := sub(32, _lc)
            if l { _c := div(_c, exp(2, mul(l, 8))) }
            o := add(o, _lc)
            _d := mload(o)
            l := sub(32, _ld)
            if l { _d := div(_d, exp(2, mul(l, 8))) }
            o := add(o, _ld)
            _e := mload(o)
            l := sub(32, _le)
            if l { _e := div(_e, exp(2, mul(l, 8))) }
            o := sub(o, s)
        }
        require(_data.length >= o, "Reading bytes out of bounds");
    }

    function decode(
        bytes memory _data,
        uint256 _la,
        uint256 _lb,
        uint256 _lc,
        uint256 _ld,
        uint256 _le,
        uint256 _lf
    ) internal pure returns (
        bytes32 _a,
        bytes32 _b,
        bytes32 _c,
        bytes32 _d,
        bytes32 _e,
        bytes32 _f
    ) {
        uint256 o;
        assembly {
            let s := add(_data, 32)
            _a := mload(s)
            let l := sub(32, _la)
            if l { _a := div(_a, exp(2, mul(l, 8))) }
            o := add(s, _la)
            _b := mload(o)
            l := sub(32, _lb)
            if l { _b := div(_b, exp(2, mul(l, 8))) }
            o := add(o, _lb)
            _c := mload(o)
            l := sub(32, _lc)
            if l { _c := div(_c, exp(2, mul(l, 8))) }
            o := add(o, _lc)
            _d := mload(o)
            l := sub(32, _ld)
            if l { _d := div(_d, exp(2, mul(l, 8))) }
            o := add(o, _ld)
            _e := mload(o)
            l := sub(32, _le)
            if l { _e := div(_e, exp(2, mul(l, 8))) }
            o := add(o, _le)
            _f := mload(o)
            l := sub(32, _lf)
            if l { _f := div(_f, exp(2, mul(l, 8))) }
            o := sub(o, s)
        }
        require(_data.length >= o, "Reading bytes out of bounds");
    }

}


contract TestModel is BytesUtils, Ownable {
    uint256 public constant STATUS_ONGOING = 1;
    uint256 public constant STATUS_PAID = 2;
    uint256 public constant STATUS_ERROR = 4;
    event Created(bytes32 indexed _id);
    event ChangedStatus(bytes32 indexed _id, uint256 _timestamp, uint256 _status);
    event ChangedObligation(bytes32 indexed _id, uint256 _timestamp, uint256 _debt);
    event ChangedFrequency(bytes32 indexed _id, uint256 _timestamp, uint256 _frequency);
    event ChangedDueTime(bytes32 indexed _id, uint256 _timestamp, uint256 _status);
    event ChangedFinalTime(bytes32 indexed _id, uint256 _timestamp, uint64 _dueTime);
    event AddedDebt(bytes32 indexed _id, uint256 _amount);
    event AddedPaid(bytes32 indexed _id, uint256 _paid);


    uint256 public constant L_DATA = 16 + 8;

    uint256 private constant U_128_OVERFLOW = 2 ** 128;
    uint256 private constant U_64_OVERFLOW = 2 ** 64;

    uint256 public constant ERROR_PAY = 1;
    uint256 public constant ERROR_INFINITE_LOOP_PAY = 2;
    uint256 public constant ERROR_STATUS = 3;
    uint256 public constant ERROR_INFINITE_LOOP_STATUS = 4;
    uint256 public constant ERROR_WRITE_STORAGE_STATUS = 5;
    uint256 public constant ERROR_RUN = 6;
    uint256 public constant ERROR_INFINITE_LOOP_RUN = 7;
    uint256 public constant ERROR_CREATE = 8;
    uint256 public constant ERROR_PAY_EXTRA = 9;
    uint256 public constant ERROR_ALLOW_INFINITE_PAY = 10;

    event SetEngine(address _engine);
    event SetErrorFlag(bytes32 _id, uint256 _flag);
    event SetGlobalErrorFlag(uint256 _flag);

    function encodeData(
        uint128 _total,
        uint64 _dueTime
    ) external pure returns (bytes memory) {
        return abi.encodePacked(_total, _dueTime);
    }

    mapping(bytes32 => Entry) public registry;

    address public engine;
    uint256 public errorFlag;

    struct Entry {
        uint64 errorFlag;
        uint64 dueTime;
        uint64 lastPing;
        uint128 total;
        uint128 paid;
    }

    modifier onlyEngine() {
        require(msg.sender == engine, "Sender is not engine");
        _;
    }

    function setGlobalErrorFlag(uint256 _flag) external onlyOwner {
        errorFlag = _flag;
        emit SetGlobalErrorFlag(_flag);
    }

    function setErrorFlag(bytes32 _id, uint64 _flag) external onlyOwner {
        registry[_id].errorFlag = _flag;
        emit SetErrorFlag(_id, _flag);
    }

    function setEngine(address _engine) external onlyOwner {
        engine = _engine;
        emit SetEngine(_engine);
    }

    function modelId() external view returns (bytes32) {
        // TestModel 0.0.1
        return 0x546573744d6f64656c20302e302e310000000000000000000000000000000000;
    }

    function descriptor() external view returns (address) {
        return address(0);
    }

    function isOperator(address operator) external view returns (bool) {
        return operator == _owner;
    }

    function validate(bytes calldata data) external view returns (bool) {
        require(data.length == L_DATA, "Invalid data length");

        (bytes32 btotal, bytes32 bdue) = decode(data, 16, 8);
        uint64 dueTime = uint64(uint256(bdue));

        if (btotal == bytes32(uint256(0))) return false;

        _validate(dueTime);
        return true;
    }

    function getStatus(bytes32 id) external returns (uint256) {
        Entry storage entry = registry[id];

        if (entry.errorFlag == ERROR_STATUS) {
            return uint256(10) / uint256(0);
        } else if (entry.errorFlag == ERROR_INFINITE_LOOP_STATUS) {
            uint256 aux;
            while (aux / aux != 2) aux++;
            return aux;
        } else if (entry.errorFlag == ERROR_WRITE_STORAGE_STATUS) {
            entry.lastPing = uint64(block.timestamp);
            return uint64(block.timestamp);
        }

        return entry.paid < entry.total ? STATUS_ONGOING : STATUS_PAID;
    }

    function getPaid(bytes32 id) external view returns (uint256) {
        return registry[id].paid;
    }

    function getObligation(bytes32 id, uint64 time) external view returns (uint256,bool) {
        Entry storage entry = registry[id];
        if (time >= entry.dueTime) {
            return (entry.total - entry.paid, true);
        } else {
            return (0, true);
        }
    }

    function getClosingObligation(bytes32 id) external view returns (uint256) {
        Entry storage entry = registry[id];
        return entry.total - entry.paid;
    }

    function getDueTime(bytes32 id) external view returns (uint256) {
        return registry[id].dueTime;
    }

    function getFinalTime(bytes32 id) external view returns (uint256) {
        return registry[id].dueTime;
    }

    function getFrequency(bytes32) external view returns (uint256) {
        return 0;
    }

    function getInstallments(bytes32) external view returns (uint256) {
        return 1;
    }

    function getEstimateObligation(bytes32 id) external view returns (uint256) {
        Entry storage entry = registry[id];
        return entry.total - entry.paid;
    }

    function create(bytes32 id, bytes calldata data) external onlyEngine returns (bool) {
        require(data.length == L_DATA, "Invalid data length");

        if (errorFlag == ERROR_CREATE) return false;

        (bytes32 btotal, bytes32 bdue) = decode(data, 16, 8);
        uint128 total = uint128(uint256(btotal));
        uint64 dueTime = uint64(uint256(bdue));

        _validate(dueTime);

        emit Created(id);

        registry[id] = Entry({
            errorFlag: 0,
            dueTime: dueTime,
            lastPing: uint64(block.timestamp),
            total: total,
            paid: 0
        });

        emit ChangedStatus(id, block.timestamp, STATUS_ONGOING);
        emit ChangedDueTime(id, block.timestamp, dueTime);
        emit ChangedFinalTime(id, block.timestamp, dueTime);

        return true;
    }

    function addPaid(bytes32 id, uint256 amount) external onlyEngine returns (uint256 real) {
        _run(id);

        Entry storage entry = registry[id];

        if (entry.errorFlag == ERROR_PAY) {
            return uint256(10) / uint256(0);
        } else if (entry.errorFlag == ERROR_INFINITE_LOOP_PAY) {
            uint256 aux;
            while (aux / aux != 2) aux++;
            return aux;
        } else if (entry.errorFlag == ERROR_PAY_EXTRA) {
            return amount + 5;
        } else if (entry.errorFlag == ERROR_ALLOW_INFINITE_PAY) {
            entry.paid += uint128(amount);
            emit AddedPaid(id, amount);
            return amount;
        }

        uint256 total = entry.total;
        uint256 paid = entry.paid;

        uint256 pending = total - paid;
        real = pending <= amount ? pending : amount;

        paid += real;
        require(paid < U_128_OVERFLOW, "Paid overflow");
        entry.paid = uint128(paid);

        emit AddedPaid(id, real);
        if (paid == total) {
            emit ChangedStatus(id, block.timestamp, STATUS_PAID);
        }
    }

    function addDebt(bytes32 id, uint256 amount) external returns (bool) {
        _run(id);

        Entry storage entry = registry[id];

        uint256 total = entry.total;
        uint256 paid = entry.paid;

        if (total > paid) {
            total += amount;
            require(total < U_128_OVERFLOW, "Total overflow");
            entry.total = uint128(total);

            emit AddedDebt(id, amount);
            if (block.timestamp >= entry.dueTime) {
                emit ChangedObligation(id, block.timestamp, total - paid);
            }

            return true;
        }
    }

    function run(bytes32 id) external returns (bool) {
        return _run(id);
    }

    function _run(bytes32 id) internal returns (bool) {
        Entry storage entry = registry[id];
        uint256 prevPing = entry.lastPing;

        if (entry.errorFlag == ERROR_RUN) {
            return uint256(10) / uint256(0) == 9;
        } else if (entry.errorFlag == ERROR_INFINITE_LOOP_RUN) {
            uint256 aux;
            while (aux / aux != 2) aux++;
            return aux == 1;
        }

        if (block.timestamp != prevPing) {
            uint256 dueTime = entry.dueTime;

            if (block.timestamp >= dueTime && prevPing < dueTime) {
                emit ChangedObligation(id, dueTime, entry.total);
            }

            entry.lastPing = uint64(block.timestamp);
            return true;
        }
    }

    function _validate(uint256 due) internal view {
        require(due > block.timestamp, "Due time already past");
    }
}
