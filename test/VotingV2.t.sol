// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {ContractCollection} from "../script/ContractCollection.sol";

import {Finder} from "../src/data-verification-mechanism/implementation/Finder.sol";
import {Store} from "../src/data-verification-mechanism/implementation/Store.sol";
import {AddressWhitelist} from "../src/common/implementation/AddressWhitelist.sol";
import {IdentifierWhitelist} from "../src/data-verification-mechanism/implementation/IdentifierWhitelist.sol";
import {Registry} from "../src/data-verification-mechanism/implementation/Registry.sol";
import {VotingToken} from "../src/data-verification-mechanism/implementation/VotingToken.sol";
import {FixedSlashSlashingLibrary} from "../src/data-verification-mechanism/implementation/FixedSlashSlashingLibrary.sol";
import {VotingV2} from "../src/data-verification-mechanism/implementation/VotingV2.sol";
import {VotingV2Interface} from "../src/data-verification-mechanism/interfaces/VotingV2Interface.sol";
import {TestnetERC20} from "../src/common/implementation/TestnetERC20.sol";
import {OptimisticOracleV2} from "../src/optimistic-oracle-v2/implementation/OptimisticOracleV2.sol";
import {OptimisticOracleV2Interface} from "../src/optimistic-oracle-v2/interfaces/OptimisticOracleV2Interface.sol";
import {OracleInterfaces} from "../src/data-verification-mechanism/implementation/Constants.sol";
import {FixedPoint} from "../src/common/implementation/FixedPoint.sol";

contract VotingV2FlowTest is Test, ContractCollection {
    bytes32 internal constant YES_OR_NO_IDENTIFIER = "YES_OR_NO_QUERY";

    uint256 internal constant DEFAULT_FINAL_FEE = 50e6;
    uint64 internal constant DEFAULT_LIVENESS = 7200;
    uint64 internal constant PHASE_LENGTH = 86400;
    uint256 internal constant ROUND_LENGTH = PHASE_LENGTH * uint256(VotingV2Interface.Phase.NUM_PHASES);

    int256 internal constant WRONG_PROPOSED_PRICE = 0;
    int256 internal constant CORRECT_PRICE = 1e18;
    int256 internal constant SALT = 987654321;

    address internal constant REQUESTER = address(0xA11CE);
    address internal constant PROPOSER = address(0xB0B);
    address internal constant DISPUTER = address(0xCAFE);

    Finder internal finder;
    Store internal store;
    AddressWhitelist internal addressWhitelist;
    IdentifierWhitelist internal identifierWhitelist;
    TestnetERC20 internal usdc;
    OptimisticOracleV2 internal optimisticOracle;
    Registry internal registry;
    VotingToken internal votingToken;
    FixedSlashSlashingLibrary internal slashingLibrary;
    VotingV2 internal voting;

    function _skip(uint256 timeDelta) internal {
        vm.warp(block.timestamp + timeDelta);
        vm.roll(block.number + timeDelta);
    }

    function setUp() public {
        vm.createSelectFork("basetest", 39_018_990);

        finder = deployFinder();
        store = deployStore(0, 0, address(0));
        addressWhitelist = deployAddressWhitelist();
        identifierWhitelist = deployIdentifierWhitelist();
        usdc = deployTestnetERC20();
        optimisticOracle = deployOptimisticOracleV2(DEFAULT_LIVENESS, address(finder), address(0));
        registry = deployRegistry();

        store.setFinalFee(address(usdc), FixedPoint.Unsigned(DEFAULT_FINAL_FEE));
        addressWhitelist.addToWhitelist(address(usdc));
        identifierWhitelist.addSupportedIdentifier(YES_OR_NO_IDENTIFIER);

        finder.changeImplementationAddress(OracleInterfaces.Store, address(store));
        finder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(addressWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(identifierWhitelist));
        finder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV2, address(optimisticOracle));
        finder.changeImplementationAddress(OracleInterfaces.Registry, address(registry));

        votingToken = deployVotingToken();
        votingToken.addMinter(address(this));
        votingToken.mint(address(this), 100_000_000e18);

        slashingLibrary = deploySlashingLibrary(0.001e18, 0);
        voting = deployVotingV2(
            0,
            7 days,
            PHASE_LENGTH,
            4,
            1000,
            5_000_000e18,
            0.5e18,
            address(votingToken),
            address(finder),
            address(slashingLibrary),
            address(0)
        );

        finder.changeImplementationAddress(OracleInterfaces.Oracle, address(voting));

        votingToken.approve(address(voting), type(uint256).max);
        voting.stake(10_000_000e18);

        registry.addMember(uint256(Registry.Roles.ContractCreator), address(this));
        registry.registerContract(new address[](0), address(optimisticOracle));
        registry.registerContract(new address[](0), REQUESTER);
        registry.registerContract(new address[](0), address(this));

        usdc.allocateTo(REQUESTER, 1_000_000e6);
        usdc.allocateTo(PROPOSER, 1_000_000e6);
        usdc.allocateTo(DISPUTER, 1_000_000e6);

        vm.prank(REQUESTER);
        usdc.approve(address(optimisticOracle), type(uint256).max);

        vm.prank(PROPOSER);
        usdc.approve(address(optimisticOracle), type(uint256).max);

        vm.prank(DISPUTER);
        usdc.approve(address(optimisticOracle), type(uint256).max);
    }

    function testRequestProposeDisputeThenDvmVotesAndSettles() public {
        // 构造一个简单的 YES/NO 问题，后续会通过 Optimistic Oracle 发起请求，
        // 并在出现争议后由 DVM（VotingV2）投票给出最终裁决。
        bytes memory ancillaryData = bytes("q:Was the proposal executed?");
        // 这里直接使用当前区块时间作为 requestTime。
        // 这样可以保证请求时间与当前测试链状态一致，不需要额外做绝对时间跳转。
        uint256 requestTime = block.timestamp;

        // 1. 请求方在 Optimistic Oracle 上发起价格请求。
        // 对 YES/NO 问题来说，最终答案会以 int256 价格形式表示。
        vm.prank(REQUESTER);
        optimisticOracle.requestPrice(YES_OR_NO_IDENTIFIER, requestTime, ancillaryData, usdc, 0);

        // 2. 提案方先提交一个错误价格。
        // 这里故意给出错误答案，是为了让争议方后续发起 dispute，
        // 从而把请求送入 DVM 投票流程。
        vm.prank(PROPOSER);
        optimisticOracle.proposePrice(REQUESTER, YES_OR_NO_IDENTIFIER, requestTime, ancillaryData, WRONG_PROPOSED_PRICE);

        // 3. 争议方对错误提案提出争议。
        // 一旦 dispute 成功，这个请求就不会按 OO 的乐观路径直接结算，
        // 而是进入 DVM 的投票与解析流程。
        vm.prank(DISPUTER);
        optimisticOracle.disputePrice(REQUESTER, YES_OR_NO_IDENTIFIER, requestTime, ancillaryData);

        // 校验请求在 Optimistic Oracle 中的状态已经变成 Disputed。
        assertEq(
            uint256(optimisticOracle.getState(REQUESTER, YES_OR_NO_IDENTIFIER, requestTime, ancillaryData)),
            uint256(OptimisticOracleV2Interface.State.Disputed)
        );

        // OO 转发给 DVM 时会对 ancillaryData 进行 stamping，
        // 把 requester 等上下文信息编码进去。
        // 所以后续在 VotingV2 侧查询和投票时，必须使用 stamped 后的数据。
        bytes memory stampedAncillaryData = optimisticOracle.stampAncillaryData(ancillaryData, REQUESTER);

        // 构造一个只包含当前争议请求的数组，用于查询该请求在 DVM 中的状态。
        VotingV2Interface.PendingRequestAncillary[] memory requests =
            new VotingV2Interface.PendingRequestAncillary[](1);
        requests[0] = VotingV2Interface.PendingRequestAncillary({
            identifier: YES_OR_NO_IDENTIFIER,
            time: requestTime,
            ancillaryData: stampedAncillaryData
        });

        // 在当前时刻，这个请求虽然已经被 dispute，
        // 但还没有进入当前可投票轮次，因此状态应为 Future。
        VotingV2.RequestState[] memory statuses = voting.getPriceRequestStatuses(requests);
        assertEq(uint256(statuses[0].status), uint256(VotingV2.RequestStatus.Future));

        // 推进一个完整投票 round，让该请求进入 DVM 的 pending request 队列。
        _skip(ROUND_LENGTH);

        // 读取当前待处理的 DVM 请求，理论上应该正好看到这一笔争议请求。
        VotingV2Interface.PendingRequestAncillaryAugmented[] memory pending = voting.getPendingRequests();
        assertEq(pending.length, 1, "No pending DVM request");

        // 取出这笔 pending request 的核心字段。
        // 对于 Optimistic Oracle dispute 进入 DVM 的请求，time 应与原始 requestTime 一致；
        // 因为 OO 在 hasPrice / getPrice / settle 时都会使用原始 requestTime 去查询 DVM。
        bytes32 reqIdentifier = pending[0].identifier;
        uint256 reqTime = pending[0].time;
        bytes memory reqAncillary = pending[0].ancillaryData;
        // 当前 roundId 会进入 commit hash，防止跨轮次重放。
        uint32 commitRoundId = voting.getCurrentRoundId();

        // 再做一层一致性校验，确保 DVM 中登记的请求身份和附加数据与预期一致。
        assertEq(reqIdentifier, YES_OR_NO_IDENTIFIER, "Unexpected request identifier");
        assertEq(reqAncillary, stampedAncillaryData, "Unexpected ancillary data");

        // 根据 VotingV2 的 commit-reveal 规则构造承诺哈希。
        // 这里把真实价格、盐、投票者地址、请求元数据和当前 roundId 一起编码，
        // 后续 reveal 时合约会重新计算并校验该哈希是否匹配。
        bytes32 commitHash =
            keccak256(
                abi.encodePacked(
                    CORRECT_PRICE, SALT, address(this), reqTime, reqAncillary, uint256(commitRoundId), reqIdentifier
                )
            );

        // 在 commit 阶段提交加密承诺。
        // 这里的 “ciphertext:mock-polymarket” 只是占位字符串，用来模拟加密投票负载。
        voting.commitAndEmitEncryptedVote(
            reqIdentifier, reqTime, reqAncillary, commitHash, bytes("ciphertext:mock-polymarket")
        );

        // 推进一个 phase，使流程从 commit 阶段进入 reveal 阶段。
        _skip(PHASE_LENGTH);

        // reveal 真实投票值与盐，完成揭示。
        // 如果 reveal 参数和之前 commit 的哈希不一致，这一步会失败。
        voting.revealVote(reqIdentifier, reqTime, CORRECT_PRICE, reqAncillary, SALT);

        // 再推进一个 phase，让本轮投票结果进入可处理状态。
        _skip(PHASE_LENGTH);

        // 处理所有已经可解析的请求，把投票结果正式写入 DVM 的价格存储。
        voting.processResolvablePriceRequests();

        // 校验 DVM 已经产出最终价格，且结果等于我们投出的正确价格。
        assertTrue(voting.hasPrice(reqIdentifier, reqTime, reqAncillary), "DVM has no resolved price");
        assertEq(voting.getPrice(reqIdentifier, reqTime, reqAncillary), CORRECT_PRICE, "Resolved price mismatch");
    }
}
