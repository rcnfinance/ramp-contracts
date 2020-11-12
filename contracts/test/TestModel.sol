pragma solidity ^0.6.6;

import "./DiasporeFlat.sol";


contract TestModel is BytesUtils, Ownable {
    event Created(bytes32 indexed _id);
    event ChangedObligation(bytes32 indexed _id, uint256 _timestamp, uint256 _debt);
    event ChangedFrequency(bytes32 indexed _id, uint256 _timestamp, uint256 _frequency);
    event ChangedDueTime(bytes32 indexed _id, uint256 _timestamp, uint256 _status);
    event ChangedFinalTime(bytes32 indexed _id, uint256 _timestamp, uint64 _dueTime);
    event AddedDebt(bytes32 indexed _id, uint256 _amount);
    event AddedPaid(bytes32 indexed _id, uint256 _paid);

    uint256 public constant L_DATA = 16 + 8 + 16 + 8;

    uint256 private constant U_128_OVERFLOW = 2 ** 128;
    uint256 private constant U_64_OVERFLOW = 2 ** 64;

    event SetEngine(address _engine);
    event SetInterestAmount(uint256 _interestAmount);

    function encodeData(
        uint128 _total,
        uint64 _dueTime,
        uint128 _interestAmount,
        uint64 _interestTime
    ) external pure returns (bytes memory) {
        return abi.encodePacked(_total, _dueTime, _interestAmount, _interestTime);
    }

    mapping(bytes32 => Entry) public registry;

    address public engine;

    struct Entry {
        uint64 dueTime;
        uint128 total;
        uint64 interestTime;
        uint128 interestAmount;
        uint128 paid;
    }

    modifier onlyEngine() {
        require(msg.sender == engine, "Sender is not engine");
        _;
    }

    function setEngine(address _engine) external onlyOwner {
        engine = _engine;
        emit SetEngine(_engine);
    }

    function isOperator(address _operator) external view returns (bool) {
        return _operator == _owner;
    }

    function validate(bytes calldata _data) external view returns (bool) {
        require(_data.length == L_DATA, "Invalid data length");

        (bytes32 btotal, bytes32 bdue, , bytes32 binterestTime) = decode(_data, 16, 8, 16, 8);
        uint64 dueTime = uint64(uint256(bdue));
        uint64 interestTime = uint64(uint256(binterestTime));

        if (btotal == bytes32(uint256(0))) return false;

        _validate(dueTime, interestTime);
        return true;
    }

    /*function getStatus(bytes32 _id) external returns (uint256) {
        Entry storage entry = registry[_id];

        uint256 total = now >= entry.interestTime ? entry.total + entry.interestAmount : entry.total;
        return entry.paid < total ? Status.ONGOING : Status.PAID;
    }*/

    function getPaid(bytes32 _id) external view returns (uint256) {
        return registry[_id].paid;
    }

    function getObligation(bytes32 _id, uint64 _time) external view returns (uint256 obligation, bool) {
        return _getObligation(_id, _time);
    }

    function _getObligation(bytes32 _id, uint64 _time) internal view returns (uint256 obligation, bool) {
        Entry storage entry = registry[_id];

        obligation = _time >= entry.interestTime
            ? entry.total + entry.interestAmount - entry.paid
            : _time >= entry.dueTime
                ? entry.total - entry.paid
                :0;

        return (obligation, true);
    }

    function getClosingObligation(bytes32 _id) external view returns (uint256) {
        return _getClosingObligation(_id);
    }

    function _getClosingObligation(bytes32 _id) internal view returns (uint256 obligation) {
        Entry storage entry = registry[_id];
        if (now >= entry.dueTime) {
            (obligation, ) = _getObligation(_id, uint64(now));
        } else {
            (obligation, ) = _getObligation(_id, entry.dueTime);
        }
    }

    function getDueTime(bytes32 _id) external view returns (uint256) {
        return registry[_id].dueTime;
    }

    function getFinalTime(bytes32 _id) external view returns (uint256) {
        return registry[_id].dueTime;
    }

    function getFrequency(bytes32) external pure returns (uint256) {
        return 0;
    }

    function getInstallments(bytes32) external pure returns (uint256) {
        return 1;
    }

    function getEstimateObligation(bytes32 _id) external view returns (uint256) {
        return _getClosingObligation(_id);
    }

    function create(bytes32 _id, bytes calldata _data) external onlyEngine returns (bool) {
        require(_data.length == L_DATA, "Invalid data length");

        (bytes32 btotal, bytes32 bdue, bytes32 binterestAmount, bytes32 binterestTime) = decode(_data, 16, 8, 16, 8);
        uint128 total = uint128(uint256(btotal));
        uint64 dueTime = uint64(uint256(bdue));
        uint64 interestTime = uint64(uint256(binterestTime));
        uint128 interestAmount = uint128(uint256(binterestAmount));

        _validate(dueTime, interestTime);

        emit Created(_id);

        registry[_id] = Entry({
            dueTime: dueTime,
            total: total,
            interestTime: interestTime,
            interestAmount: interestAmount,
            paid: 0
        });

        emit ChangedDueTime(_id, now, dueTime);
        emit ChangedFinalTime(_id, now, dueTime);

        return true;
    }

    function addPaid(bytes32 _id, uint256 _amount) external onlyEngine returns (uint256 real) {
        Entry storage entry = registry[_id];

        uint256 total = entry.total + (now >= entry.interestTime ? entry.interestAmount : 0);
        uint256 paid = entry.paid;

        uint256 pending = total - paid;
        real = pending <= _amount ? pending : _amount;

        paid += real;
        require(paid < U_128_OVERFLOW, "Paid overflow");
        entry.paid = uint128(paid);

        emit AddedPaid(_id, real);
    }

    function addDebt(bytes32 _id, uint256 _amount) external returns (bool) {
        Entry storage entry = registry[_id];

        uint256 total = entry.total;
        uint256 paid = entry.paid;

        if (total > paid) {
            total += _amount;
            require(total < U_128_OVERFLOW, "Total overflow");
            entry.total = uint128(total);

            emit AddedDebt(_id, _amount);
            if (now >= entry.dueTime) {
                emit ChangedObligation(_id, now, total - paid);
            }

            return true;
        }
    }

    function setDueTime(bytes32 _id, uint64 _time) external {
        registry[_id].dueTime = _time;
    }

    function setRelativeDueTime(bytes32 _id, bool _before, uint256 _delta) external {
        if (_before) {
            registry[_id].dueTime = uint64(now - _delta);
        } else {
            registry[_id].dueTime = uint64(now + _delta);
        }
    }

    function _validate(uint256 _due, uint256 _interestTime) internal view {
        require(_due > now, "TestModel._validate: Due time already past");
        require(_interestTime >= _due, "TestModel._validate: Interest time should be more or equal than due time");
    }

    // ** Test and debug methods ** //

    function setDebt(bytes32 _id, uint128 _val) external {
        registry[_id].total = _val;
    }
}