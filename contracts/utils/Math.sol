pragma solidity ^0.8.0;


library Math {
    function min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        if (_a < _b) {
            return _a;
        } else {
            return _b;
        }
    }

    function divCeil(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
        require(_b != 0, "div by zero");
        c = _a / _b;
        if (_a % _b != 0) {
            c = c + 1;
        }
    }
}