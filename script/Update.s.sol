// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "./ContractCollection.sol";

contract UpdateScript is ContractCollection {

    uint256 defaultCurrencyFinalFee = 50e6; // Half of expected minimum bond.

    uint256 privatekey = vm.envUint("PRIVATEKEY");

    function run() public {
        
        vm.startBroadcast(privatekey);

        address storeAddress = getContractAddress("store");
        Store store = Store(storeAddress);

        address usdcAddress = getContractAddress("usdc");

        store.setFinalFee(usdcAddress, FixedPoint.Unsigned(defaultCurrencyFinalFee));
        vm.stopBroadcast();
    }
}
