pragma solidity ^0.6.6;

import "./DiasporeFlat.sol";
import "../interfaces/rcn/Cosigner.sol";


contract TestCosigner is Cosigner {
    bytes32 public customId;
    uint256 public customCost;

    function setCustomData(bytes32 _customId, uint256 _customCost) external {
        customId = _customId;
        customCost = _customCost;
    }

    function cost(
        address,
        uint256,
        bytes memory,
        bytes memory
    ) public override view returns (uint256) {
        return customCost;
    }

    function requestCosign(
        address _loanManager,
        uint256 _id,
        bytes memory,
        bytes memory
    ) public override returns (bool) {
        require(LoanManager(_loanManager).cosign(_id, customCost), "requestCosign: loanManager cosign error");

        return true;
    }

    function url() public view override returns (string memory) {
        return "";
    }

    function claim(address, uint256, bytes memory) public override returns (bool) {
        return false;
    }
}
