// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "./ContractCollection.sol";

contract UmaScript is ContractCollection {

    bytes32 private constant YES_OR_NO_IDENTIFIER = "YES_OR_NO_QUERY";
    uint256 defaultCurrencyFinalFee = 50e6; // Half of expected minimum bond.
    uint64 defaultLiveness = 7200; // 2 hours

    uint256 privatekey = vm.envUint("PRIVATEKEY");

    function run() public {
        
        vm.startBroadcast(privatekey);

        Finder finder = deployFinder();
        Store store = deployStore(0, 0, address(0));
        AddressWhitelist addressWhitelist = deployAddressWhitelist();
        IdentifierWhitelist identifierWhitelist = deployIdentifierWhitelist();
        TestnetERC20 usdc = deployTestnetERC20();
        OptimisticOracleV2 optimisticOracleV2 = deployOptimisticOracleV2(defaultLiveness, address(finder), address(0));
        Registry registry = deployRegistry();

        store.setFinalFee(address(usdc), FixedPoint.Unsigned(defaultCurrencyFinalFee));
        addressWhitelist.addToWhitelist(address(usdc));
        identifierWhitelist.addSupportedIdentifier(YES_OR_NO_IDENTIFIER);

        finder.changeImplementationAddress(OracleInterfaces.Store, address(store));
        finder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(addressWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(identifierWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV2, address(optimisticOracleV2));
        finder.changeImplementationAddress(OracleInterfaces.Registry, address(registry));

        registry.addMember(uint256(Registry.Roles.ContractCreator), vm.addr(privatekey));
        registry.registerContract(new address[](0), address(optimisticOracleV2));
        registry.removeMember(uint256(Registry.Roles.ContractCreator), vm.addr(privatekey));
        registry.addMember(uint256(Registry.Roles.ContractCreator), vm.addr(privatekey));
        registry.registerContract(new address[](0), vm.addr(privatekey));

        VotingToken votingToken = deployVotingToken();
        votingToken.addMinter(vm.addr(privatekey));
        votingToken.mint(vm.addr(privatekey), 100000000e18);
        
        FixedSlashSlashingLibrary slashingLibrary = deploySlashingLibrary(0.001e18, 0);

        uint128 emissionRate = 0;
        uint64 unstakeCoolDown = 604800; // 7 days
        uint64 phaseLength = 86400; // 1 day
        uint32 maxRolls = 4;
        uint32 maxRequestsPerRound = 1000;
        uint128 gat = 5000000000000000000000000; // 5000000e18 GAT
        uint64 spat = 500000000000000000; // 0.5e18 SPAT
        address previousVotingContract = address(0);
        VotingV2 voting = deployVotingV2(emissionRate, unstakeCoolDown, phaseLength, maxRolls, maxRequestsPerRound, gat, spat, address(votingToken), address(finder), address(slashingLibrary), previousVotingContract);

        finder.changeImplementationAddress(OracleInterfaces.Oracle, address(voting));

        votingToken.approve(address(voting), type(uint256).max);
        voting.stake(100000000e18 / 10); // Stake 10% of tokens


        deployDesignatedVotingFactory(address(finder));

        deployGovernorV2(address(finder), 1);
        
            
        vm.stopBroadcast();
    }
}
