// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseDeployScript} from "./BaseDeployScript.sol";

import "../src/data-verification-mechanism/implementation/Finder.sol";
import "../src/data-verification-mechanism/implementation/Store.sol";
import "../src/common/implementation/AddressWhitelist.sol";
import "../src/data-verification-mechanism/implementation/IdentifierWhitelist.sol";
import "../src/data-verification-mechanism/test/MockOracleAncillary.sol";
import "../src/common/implementation/TestnetERC20.sol";
import "../src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol";

import "../src/data-verification-mechanism/implementation/Registry.sol";
import "../src/data-verification-mechanism/implementation/VotingToken.sol";
import "../src/data-verification-mechanism/implementation/FixedSlashSlashingLibrary.sol";
import "../src/data-verification-mechanism/implementation/VotingV2.sol";
import "../src/data-verification-mechanism/implementation/DesignatedVotingV2Factory.sol";
import "../src/data-verification-mechanism/implementation/GovernorV2.sol";

contract ContractCollection is BaseDeployScript {

    function deployFinder() public returns (Finder finder) {
        finder = new Finder();
        saveContract("finder", address(finder));
    }

    function deployStore(
        uint256 oracleReward,
        uint256 finalFee,
        address timerAddress
    ) public returns (Store store) {
        store = new Store(
            FixedPoint.fromUnscaledUint(oracleReward),
            FixedPoint.fromUnscaledUint(finalFee),
            timerAddress
        );
        saveContract("store", address(store));
    }

    function deployAddressWhitelist()
        public
        returns (AddressWhitelist addressWhitelist)
    {
        addressWhitelist = new AddressWhitelist();
        saveContract("addressWhitelist", address(addressWhitelist));
    }

    function deployIdentifierWhitelist()
        public
        returns (IdentifierWhitelist identifierWhitelist)
    {
        identifierWhitelist = new IdentifierWhitelist();
        saveContract("identifierWhitelist", address(identifierWhitelist));
    }

    function deployTestnetERC20() public returns (TestnetERC20 usdc) {
        usdc = new TestnetERC20("Circle", "USDC", 6);
        saveContract("usdc", address(usdc));
    }

    function deployOptimisticOracleV2(
        uint64 defaultLiveness,
        address finderAddress,
        address timerAddress
    ) public returns (OptimisticOracleV2 optimisticOracleV2) {
        optimisticOracleV2 = new OptimisticOracleV2(
            defaultLiveness,
            finderAddress,
            timerAddress
        );
        saveContract("optimisticOracleV2", address(optimisticOracleV2));
    }

    function deployRegistry() public returns (Registry registry) {
        registry = new Registry();
        saveContract("registry", address(registry));
    }

    function deployVotingToken() public returns (VotingToken votingToken) {
        votingToken = new VotingToken();
        saveContract("votingToken", address(votingToken));
    }

    function deploySlashingLibrary(
        uint256 baseSlashAmount,
        uint256 governanceSlashAmount
    ) public returns (FixedSlashSlashingLibrary slashingLibrary) {
        slashingLibrary = new FixedSlashSlashingLibrary(
            baseSlashAmount,
            governanceSlashAmount
        );
        saveContract("slashingLibrary", address(slashingLibrary));
    }

    function deployVotingV2(
        uint128 emissionRate,
        uint64 unstakeCoolDown,
        uint64 phaseLength,
        uint32 maxRolls,
        uint32 maxRequestsPerRound,
        uint128 gat,
        uint64 spat,
        address votingTokenAddress,
        address finderAddress,
        address slashingLibraryAddress,
        address previousVotingContract
    ) public returns (VotingV2 voting) {
        voting = new VotingV2(
            emissionRate,
            unstakeCoolDown,
            phaseLength,
            maxRolls,
            maxRequestsPerRound,
            gat,
            spat,
            votingTokenAddress,
            finderAddress,
            slashingLibraryAddress,
            previousVotingContract
        );
        saveContract("votingV2", address(voting));
    }

    function deployDesignatedVotingFactory(
        address finderAddress
    ) public returns (DesignatedVotingV2Factory designatedVotingFactory) {
        designatedVotingFactory = new DesignatedVotingV2Factory(finderAddress);
        saveContract(
            "designatedVotingFactory",
            address(designatedVotingFactory)
        );
    }

    function deployGovernorV2(
        address finderAddress,
        uint256 startingId
    ) public returns (GovernorV2 governor) {
        governor = new GovernorV2(finderAddress, startingId);
        saveContract("governorV2", address(governor));
    }
}
