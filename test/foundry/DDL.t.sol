// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { MockERC721 } from "solmate/test/utils/mocks/MockERC721.sol";

import { DDL } from "../../contracts/DDL.sol";

/**
 * Testing Notes
 *
 * FIXED:
 *
 * 1. extra _afterProposalExecution(proposal) in _executeOrgProposal (last two)
 * 2. _updateQuorum -> was off by 1
 * 3. verifySignature -> updated to use proper contract
 * 4. _createMessageHash -> public for testing, uses _hashTypedData directly
 *
 * TEST SPEC:
 *
 * Testing Meta Strategy
 * - use multisig org first time through, approve each function call from 2nd member
 * - repeat all proposal creation functions with single signer org to test immediate execution
 *
 * Unit Testing Workflow:
 * 1. double check test spec covers all requires & state changes for the function
 * 2. copy test spec above new test function at bottom
 * 3. implement happy case test (assume multisig first, so propose & approve)
 * 4. implement all require failures (check for require reason)
 * 5. implement any edge case tests
 *
 * PUBLIC FUNCTIONS (anyone can call)
 *
 * receive
 * - NOTE
 *     - receive fails when called with send/transfer bc storage operation requires more than 2300 gas
 *     - only works with .call()... is this a problem? are wallets smart enough? this could result in lots of failed calls?
 * - happy case
 *     - lineReceivedDonationsPerAsset
 *     - organizationTotalDonationsPerAsset
 * - require: not paused
 *
 * registerAnOrg
 * - happy case
 *     - increment orgId++
 *     - store all organization details
 *     - store all organization members
 *     - set latest org signer id
 *     - store all external donation addresses
 *     - set latest external donation address
 * - happy case (multisig)
 *     - store organization as multisig = true
 * - require: quorum larger than member count
 * - require: quorum must not be 0
 * - require: all members must sign join message
 * - require: not paused
 *
 * ADMIN FUNCTIONS (irandao mods only)
 *
 * verifyOrg
 * - require: only IranDAOMods can call
 * - set isVerified = true
 *
 * givePrivacyProviderRoleToAnOrgLine
 * - require: only IranDAOMods can call
 * - require: org not active
 * - require: line is not active
 * - set privacy provider line
 *
 * removePrivacyProviderRoleFromAnOrgLine
 *
 * ORG FUNCTIONS (call as org member)
 *
 * IMMEDIATE ORG ACTIONS:
 *
 * createLine
 * - require: sender must be member
 * - require: org is active
 * - happy case
 *     - set title/isActive
 *     - increment latestOrganizationLineId
 *
 * ORG CREATE PROPOSAL:
 *
 * addOrgSignerReq
 * - require: sender must be member
 * - require: signer is already member
 * - require: quorum can't be 0
 * - require: quorum can't be greater than # of members
 * - require: org is active
 * - require: not paused
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 * - happy case (quorum reached)
 *     - proposal executed
 *     - signer ID incremented
 *     - proposed signer added to members
 *     - quorum updated
 *
 * removeOrgSignerReq
 * - require: sender must be member
 * - require: signer isn't member
 * - require: quorum can't be 0
 * - require: quorum can't be greater than # of members
 * - require: org is active
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 *     - save signer details
 * - happy case (quorum reached)
 *     - proposal executed
 *     - signer ID decremented
 *     - proposed signer removed
 *     - quorum updated
 *
 * updateOrgOrgQuorumReq
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 * - happy case (quorum reached)
 *     - proposal executed
 *     - quorum updated
 * - require: sender must be member
 * - require: quorum can't be 0
 * - require: quorum can't be greater than # of members
 * - require: org is active
 *
 * deactivateOrgReq
 * deactivateLineReq
 * withdrawDonationFromLinesRequest TODO
 *
 * addExternalDonationAddressToOrgReq TODO
 * - require: sender must be member
 * - require: org is active
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 * - happy case (quorum reached)
 *     - proposal executed
 *     - external donation address added
 *
 * updateExternalDonationAddressOfOrgReq TODO
 * - require: sender must be member
 * - require: org is active
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 * - happy case (quorum reached)
 *     - proposal executed
 *     - external donation address updated
 *
 * updateOrgSecureMessagingPubKeyReq TODO
 * - require: sender must be member
 * - require: org is active
 * - happy case (no quorum yet)
 *     - save proposal details
 *     - increment proposal counter
 * - happy case (quorum reached)
 *     - proposal executed
 *     - pubkeys updated
 *
 * updateOrgURI
 * - require: sender must be member
 * - require: org is active
 * - require: not paused
 * - happy case
 *     - orgURI updated
 *
 * ORG PROPOSAL FUNCTIONS:
 *
 * approveOrgProposal
 * - happy case
 *     - store signing member address
 *     - increment signed count
 *     - execute if at or above quorum
 * - require: sender is not a member
 * - require: already signed
 * - require: already executed
 * - require: tx expired
 *
 * revokeOrgProposal TODO
 * - happy case
 *     - delete signing member address
 *     - decrement signed count
 * - require: sender is not a member
 * - require: already signed
 * - require: already executed
 * - require: tx expired
 *
 * DONATION FUNCTIONS:
 *
 * donateToLineWithMainToken TODO
 * - require: org is active
 * - require: not privacy provider line
 * - require: line is active
 * - happy case
 *     - save amount sent
 *     - increment donors (actually records # of donations)
 *
 * donateToLineWithToken TODO
 *
 * ENDGAME FUNCTIONS:
 *
 * updateEndgameData
 * - updates struct
 * - require: mods only
 * - require: not paused
 *
 * transferModerationToCommunityRequest
 * - updates newModeratorCandidate
 * - require: migration is completed
 * - require: only mods
 * - require: not paused
 *
 * revokeTransferModerationToCommunityRequest
 * - updates newModeratorCandidate
 * - require: migration is completed
 * - require: only mods
 * - require: not paused
 *
 * acceptModeration
 * - updates moderators & newMods candidate
 * - require: not paused
 * - require: msg.sender is endgame contract
 * - require: msg.sender is newMod candidate
 *
 * startMigrationProcess
 * - updates: migration deadline & pauses
 * - require: only mods
 * - require: not paused

 * cancelMigrationProcess
 * - updates: migration deadline & unpauses
 * - require: only mods
 * - require: not paused
 *
 * migrateRemainingAssetToEndGameTreasury
 * - updates: tokens, NFTs, raw ETH
 * - require: migration deadline passed
 * - require: assets & amounts length
 * - require: assets & types length
 *
 * GETTER FUNCTIONS:
 *
 * hasPrivacyProviderRole
 */

contract ContractTest is Test {
    // params
    DDL ddl;
    address irandaoModMultisig = address(0x11);
    address endgame = address(0x22);
    string firstOrgTitle = "irandao";
    string firstOrgURI = "irandao.com";
    uint256 alicePrivKey = 3;
    uint256 bobPrivKey = 4;
    uint256 charliePrivKey = 5;
    address alice = vm.addr(alicePrivKey);
    address bob = vm.addr(bobPrivKey);
    address charlie = vm.addr(charliePrivKey);
    address[] daoMembers;
    string pubkey1 = "0xabc";
    string networkName1 = "0x111";
    string networkName2 = "0x222";
    string externalDonationAddress1 = "0x112";
    string externalDonationAddress2 = "0x223";
    DDL.OrgExternalDonationAddress orgDonationAddress1 =
        DDL.OrgExternalDonationAddress(networkName1, externalDonationAddress1);
    DDL.OrgExternalDonationAddress orgDonationAddress2 =
        DDL.OrgExternalDonationAddress(networkName2, externalDonationAddress2);
    DDL.OrgExternalDonationAddress[] orgDonationAddresses;
    uint256 spamFee = 1;

    // Org #2 Params
    string secondOrgTitle = "daodao";
    string secondOrgURI = "daodao.com";
    string pubkey2 = "0xdead";

    // for testing URI updates
    DDL.NewURI newURI = DDL.NewURI("update.com", true);
    DDL.NewURI keepURI = DDL.NewURI("", false);

    MockERC20 dai = new MockERC20("DAI", "DAI", 18);
    MockERC20 mkr = new MockERC20("MKR", "MKR", 18);
    MockERC721 nft = new MockERC721("APE", "APE");

    // set up (called before every test)
    function setUp() public {
        // send 100 eth to alice/bob/charlie
        vm.deal(alice, 100);
        vm.deal(bob, 100);
        vm.deal(charlie, 100);

        // mint 200 dai for alice
        dai.mint(alice, 200);

        // mint 1 ERC721 for alice with ID=1
        nft.mint(alice, 1);

        daoMembers.push(alice);
        daoMembers.push(bob);
        orgDonationAddresses.push(orgDonationAddress1);
        orgDonationAddresses.push(orgDonationAddress2);
        ddl = new DDL(
            irandaoModMultisig,
            endgame,
            firstOrgTitle,
            firstOrgURI,
            daoMembers,
            2, // quorum
            pubkey1,
            orgDonationAddresses,
            spamFee
        );
    }

    function test_setUp() public {
        assertEq(ddl.moderators(), irandaoModMultisig);
        assertEq(ddl.orgRegistrationSpamProtectionFee(), 1);

        (, address endgameTreasury, ) = ddl.endgamePlatform();
        assertEq(endgameTreasury, endgame);

        (
            string memory title,
            string memory orgURI,
            bool isActive,
            bool isVerified,
            bool hasMultisig,
            uint8 quorum,
            string memory secureMessagingPubKey
        ) = ddl.organizations(0);
        assertEq(title, "irandao");
        assertEq(orgURI, "irandao.com");
        assertEq(isActive, true);
        assertEq(isVerified, false); // false until mods verify
        assertEq(hasMultisig, true);
        assertEq(quorum, 2);
        assertEq(secureMessagingPubKey, pubkey1);

        (
            uint8 lineId,
            uint8 externalDonationAddressId,
            uint8 signerId,
            uint48 proposalId
        ) = ddl.organizationIdRelatedData(0);
        assertEq(lineId, 0);
        assertEq(externalDonationAddressId, 1);
        assertEq(signerId, 1);
        assertEq(proposalId, 0);

        for (uint8 i = 0; i < daoMembers.length; i++) {
            address member = ddl.orgMembers(0, i);
            assertEq(member, daoMembers[i]);
            assertTrue(ddl.isOrgMember(daoMembers[i], 0));
        }

        for (uint8 j = 0; j < orgDonationAddresses.length; j++) {
            (string memory networkName, string memory donationAddress) = ddl
                .organizationExternalDonationAddresses(0, j);
            assertEq(networkName, orgDonationAddresses[j].networkName);
            assertEq(
                donationAddress,
                orgDonationAddresses[j].externalDonationAddress
            );
        }

        (
            string memory lineTitle,
            bool lineIsActive,
            bool isPrivacyProviderLine
        ) = ddl.orgsLines(0, 0);
        assertEq(lineTitle, "");
        assertTrue(lineIsActive);
        assertFalse(isPrivacyProviderLine);
    }

    function test_setup_no_signers() public {
        daoMembers.pop(); // pop first signer
        daoMembers.pop(); // pop second signer
        vm.expectRevert("signers cannot be empty");
        ddl = new DDL(
            irandaoModMultisig,
            endgame,
            firstOrgTitle,
            firstOrgURI,
            daoMembers,
            2, // quorum
            pubkey1,
            orgDonationAddresses,
            spamFee
        );
    }

    function test_setup_zero_quorum() public {
        vm.expectRevert("quorum cannot be 0");
        ddl = new DDL(
            irandaoModMultisig,
            endgame,
            firstOrgTitle,
            firstOrgURI,
            daoMembers,
            0, // quorum
            pubkey1,
            orgDonationAddresses,
            spamFee
        );
    }

    function test_setup_quorum_too_big() public {
        vm.expectRevert("quorum cannot be greater than signers length");
        ddl = new DDL(
            irandaoModMultisig,
            endgame,
            firstOrgTitle,
            firstOrgURI,
            daoMembers,
            3, // quorum
            pubkey1,
            orgDonationAddresses,
            spamFee
        );
    }

    /*
    receive
    - happy case
        - lineReceivedDonationsPerAsset
        - organizationTotalDonationsPerAsset
    - require: not paused
    */

    function test_receive() public {
        vm.startPrank(alice);
        SafeTransferLib.safeTransferETH(address(ddl), 1);
        assertEq(ddl.lineReceivedDonationsPerAsset(0, 0, address(0)), 1);
        assertEq(ddl.organizationTotalDonationsPerAsset(0, address(0)), 1);
    }

    function test_receive_paused() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        SafeTransferLib.safeTransferETH(address(ddl), 1);
        vm.stopPrank();
        assertEq(ddl.lineReceivedDonationsPerAsset(0, 0, address(0)), 0);
        assertEq(ddl.organizationTotalDonationsPerAsset(0, address(0)), 0);
    }

    /*
    registerAnOrg
    - happy case
        - increment orgId++
        - store all organization details
        - store all oranization members
        - set latest org signer id
        - store all external donation addresses
        - set latest external donation address
    - happy case (multisig)
        - store organization as multisig = true
    - require: quorum larger than member count
    - require: quorum must not be 0
    - require: all members must sign join message
    - require: not paused
    */

    function test_registerAnOrg() public {
        // note, switched order of bob, alice for this test
        vm.startPrank(bob);

        // signers
        address[] memory signers = new address[](2);
        signers[0] = bob;
        signers[1] = alice;

        // _memberApproveJoinSignature
        uint256 sigTimestamp = block.timestamp;
        // timestamps
        uint256[] memory timestamps = new uint256[](2);
        timestamps[0] = sigTimestamp;

        bytes[] memory joinSignatures = new bytes[](2);

        (uint8 v_1, bytes32 r_1, bytes32 s_1) = vm.sign(
            bobPrivKey,
            ddl.createMessageHash(secondOrgURI, bob, bob, sigTimestamp)
        );
        joinSignatures[0] = abi.encodePacked(r_1, s_1, v_1);

        vm.expectRevert("invalid signature");
        ddl.registerAnOrg{ value: spamFee }(
            secondOrgTitle,
            secondOrgURI,
            signers,
            joinSignatures,
            timestamps,
            2,
            pubkey2,
            orgDonationAddresses
        );

        uint256 expiredTimestamp = sigTimestamp -
            ddl.PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL();

        (uint8 v_2, bytes32 r_2, bytes32 s_2) = vm.sign(
            alicePrivKey,
            ddl.createMessageHash(secondOrgURI, alice, bob, expiredTimestamp)
        );
        timestamps[1] = expiredTimestamp;
        joinSignatures[1] = abi.encodePacked(r_2, s_2, v_2);

        vm.expectRevert("approve join message is expired");
        ddl.registerAnOrg{ value: spamFee }(
            secondOrgTitle,
            secondOrgURI,
            signers,
            joinSignatures,
            timestamps,
            2,
            pubkey2,
            orgDonationAddresses
        );

        (v_2, r_2, s_2) = vm.sign(
            alicePrivKey,
            ddl.createMessageHash(secondOrgURI, alice, bob, sigTimestamp)
        );
        timestamps[1] = sigTimestamp;
        joinSignatures[1] = abi.encodePacked(r_2, s_2, v_2);

        vm.expectRevert("quorum cannot be 0");
        ddl.registerAnOrg{ value: spamFee }(
            secondOrgTitle,
            secondOrgURI,
            signers,
            joinSignatures,
            timestamps,
            0,
            pubkey2,
            orgDonationAddresses
        );

        vm.expectRevert("quorum cannot be greater than signers length");
        ddl.registerAnOrg{ value: spamFee }(
            secondOrgTitle,
            secondOrgURI,
            signers,
            joinSignatures,
            timestamps,
            3,
            pubkey2,
            orgDonationAddresses
        );

        // This should work
        uint16 orgId = ddl.registerAnOrg{ value: spamFee }(
            secondOrgTitle,
            secondOrgURI,
            signers,
            joinSignatures,
            timestamps,
            2,
            pubkey2,
            orgDonationAddresses
        );

        (
            string memory setOrgTitle,
            string memory setOrgURI,
            bool setIsActive,
            bool setIsVerified,
            bool setHasMultisig,
            uint8 setQuorum,
            string memory setSecureMessagingPubKey
        ) = ddl.organizations(orgId);

        assertEq(secondOrgTitle, setOrgTitle);
        assertEq(secondOrgURI, setOrgURI);
        assertTrue(setIsActive);
        assertFalse(setIsVerified);
        assertTrue(setHasMultisig);
        assertEq(2, setQuorum);
        assertEq(pubkey2, setSecureMessagingPubKey);

        (
            string memory donationAddress1Network,
            string memory donationAddress1
        ) = ddl.organizationExternalDonationAddresses(orgId, 0);
        (
            string memory donationAddress2Network,
            string memory donationAddress2
        ) = ddl.organizationExternalDonationAddresses(orgId, 1);
        assertEq(networkName1, donationAddress1Network);
        assertEq(externalDonationAddress1, donationAddress1);
        assertEq(networkName2, donationAddress2Network);
        assertEq(externalDonationAddress2, donationAddress2);

        assertEq(ddl.orgMembers(orgId, 0), bob);
        assertEq(ddl.orgMembers(orgId, 1), alice);
    }

    function test_verifyOrg() public {
        vm.expectRevert("only moderators can call this function");
        ddl.verifyOrg(0);

        vm.prank(irandaoModMultisig);
        ddl.verifyOrg(0);

        (, , , bool isVerified, , , ) = ddl.organizations(0);
        assertTrue(isVerified);
    }

    function test_givePrivacyProviderRoleToAnOrgLine() public {
        vm.expectRevert("only moderators can call this function");
        ddl.givePrivacyProviderRoleToAnOrgLine(0, 0);

        vm.prank(irandaoModMultisig);
        ddl.givePrivacyProviderRoleToAnOrgLine(0, 0);

        (, bool isActive, bool isPrivacyProviderLine) = ddl.orgsLines(0, 0);
        assertTrue(isActive);
        assertTrue(isPrivacyProviderLine);
        assertTrue(ddl.hasPrivacyProviderRole(0, 0));
    }

    function test_removePrivacyProviderRoleFromAnOrgLine() public {
        vm.startPrank(irandaoModMultisig);
        ddl.givePrivacyProviderRoleToAnOrgLine(0, 0);
        ddl.removePrivacyProviderRoleFromAnOrgLine(0, 0, keepURI);

        (, , bool isPrivacyProviderLine) = ddl.orgsLines(0, 0);
        assertFalse(isPrivacyProviderLine);

        ddl.givePrivacyProviderRoleToAnOrgLine(0, 0);
        vm.stopPrank();

        vm.prank(alice);
        ddl.removePrivacyProviderRoleFromAnOrgLine(0, 0, keepURI);

        (, , isPrivacyProviderLine) = ddl.orgsLines(0, 0);
        assertFalse(isPrivacyProviderLine);
    }

    /*
     * createLine
     * - require: sender must be member
     * - require: org is active
     * - happy case
     *     - set title/isActive
     *     - increment latestOrganizationLineId
     */
    function test_createLine() public {
        vm.expectRevert("only organization members can call this function");
        vm.prank(charlie);
        ddl.createLine(0, "not-a-member");

        string memory name = "ddl-line";
        vm.prank(alice);
        uint8 lineId = ddl.createLine(0, name);

        (
            string memory storedName,
            bool isActive,
            bool isPrivacyProviderLine
        ) = ddl.orgsLines(0, lineId);
        assertEq(storedName, name);
        assertTrue(isActive);
        assertFalse(isPrivacyProviderLine);
    }

    /*
    addOrgSignerReq
    - happy case (no quorum yet)
        - save proposal details
        - increment proposal counter
    - happy case (quorum reached)
        - proposal executed
        - signer ID incremented
        - proposed signer added to members
        - quorum updated
    - require: sender must be member
    - require: signer is already member
    - require: quorum can't be 0
    - require: quorum can't be greater than # of members
    - require: org is active (TODO)
    - require: not paused
    */

    function test_addOrgSignerReq() public {
        vm.startPrank(alice);
        ddl.addOrgSignerReq(0, charlie, 3, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        ddl.approveOrgProposal(0, 0);
        address newMember = ddl.orgMembers(0, 2);

        assertEq(ddl.didSignOrgTransaction(alice, 0, 0), true);
        assertEq(ddl.didSignOrgTransaction(bob, 0, 0), true);

        assertEq(newMember, charlie);
        assertTrue(ddl.isOrgMember(charlie, 0));

        (, string memory orgURI, , , , uint8 quorum, ) = ddl.organizations(0);
        assertEq(orgURI, "update.com");
        assertEq(quorum, 3);

        (, , uint8 signerId, uint48 proposalId) = ddl.organizationIdRelatedData(
            0
        );
        assertEq(signerId, 2);
        assertEq(proposalId, 1);

        (
            address proposer,
            DDL.OrganizationProposalType transactionType,
            uint64 validUntil,
            bytes memory data,
            bool isExecuted,
            uint8 signedCount
        ) = ddl.orgProposals(0, 0);

        assertEq(proposer, alice);
        assertEq(
            uint256(transactionType),
            uint256(DDL.OrganizationProposalType.ADD_SIGNER)
        );
        assertEq(
            validUntil,
            block.timestamp + ddl.PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL()
        );
        assertEq(data, abi.encode(charlie, 3));
        assertEq(isExecuted, true);
        assertEq(signedCount, 2);
    }

    function test_addOrgSignerRequest_notMember() public {
        vm.startPrank(charlie);
        vm.expectRevert("only organization members can call this function");
        ddl.addOrgSignerReq(0, charlie, 3, newURI);
    }

    function test_addOrgSignerRequest_alreadyMember() public {
        vm.startPrank(alice);
        ddl.addOrgSignerReq(0, alice, 3, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("signer already exists");
        ddl.approveOrgProposal(0, 0);
    }

    function test_addOrgSignerRequest_zeroQuorum() public {
        vm.startPrank(alice);
        ddl.addOrgSignerReq(0, charlie, 0, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("quorum cannot be 0");
        ddl.approveOrgProposal(0, 0);
    }

    function test_addOrgSignerRequest_quorumTooHigh() public {
        vm.startPrank(alice);
        ddl.addOrgSignerReq(0, charlie, 4, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("quorum can't be greater than number of members");
        ddl.approveOrgProposal(0, 0);
    }

    function test_addOrgSignerRequest_signer_is_empty() public {
        vm.startPrank(alice);
        ddl.addOrgSignerReq(0, address(0), 4, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("signer cannot be 0x0");
        ddl.approveOrgProposal(0, 0);
    }

    function test_addOrgSignerRequest_signer_is_paused() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        ddl.addOrgSignerReq(0, charlie, 3, newURI);
    }

    function test_addOrgSignerRequest_org_deactivated() public {
        address[] memory assetList;
        vm.startPrank(irandaoModMultisig);
        ddl.deactivateOrgReq(
            0,
            assetList,
            DDL.OrgDeactivators.MODERATORS,
            newURI
        );
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("organization is not active");
        ddl.addOrgSignerReq(0, charlie, 3, newURI);
    }

    /*
    removeOrgSignerReq
    - happy case (no quorum yet)
        - save proposal details
        - increment proposal counter
        - save signer details
    - happy case (quorum reached)
        - proposal executed
        - signer ID decremented
        - proposed signer removed
        - quorum updated
    - require: sender must be member
    - require: quorum can't be 0
    - require: quorum can't be greater than # of members
    - require: org is active (TODO)
    - require: not paused
    - edge case: signerId too high (nothing happens)
    */

    function test_removeOrgSignerReq() public {
        vm.startPrank(alice);
        ddl.removeOrgSignerReq(0, 0, 1, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        ddl.approveOrgProposal(0, 0);

        assertEq(ddl.didSignOrgTransaction(alice, 0, 0), true);
        assertEq(ddl.didSignOrgTransaction(bob, 0, 0), true);

        assertEq(ddl.isOrgMember(alice, 0), false);
        assertEq(ddl.isOrgMember(bob, 0), true);

        (, string memory orgURI, , , bool hasMultisig, uint8 quorum, ) = ddl
            .organizations(0);
        assertEq(orgURI, "update.com");
        assertEq(hasMultisig, false);
        assertEq(quorum, 1);

        (, , uint8 signerId, uint48 proposalId) = ddl.organizationIdRelatedData(
            0
        );
        assertEq(signerId, 0);
        assertEq(proposalId, 1);

        (
            address proposer,
            DDL.OrganizationProposalType transactionType,
            uint64 validUntil,
            bytes memory data,
            bool isExecuted,
            uint8 signedCount
        ) = ddl.orgProposals(0, 0);

        assertEq(proposer, alice);
        assertEq(
            uint256(transactionType),
            uint256(DDL.OrganizationProposalType.REMOVE_SIGNER)
        );
        assertEq(
            validUntil,
            block.timestamp + ddl.PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL()
        );
        assertEq(data, abi.encode(0, 1));
        assertEq(isExecuted, true);
        assertEq(signedCount, 2);
    }

    function test_removeOrgSignerRequest_notMember() public {
        vm.startPrank(charlie);
        vm.expectRevert("only organization members can call this function");
        ddl.removeOrgSignerReq(0, 0, 1, newURI);
    }

    function test_removeOrgSignerRequest_zeroQuorum() public {
        vm.startPrank(alice);
        ddl.removeOrgSignerReq(0, 0, 0, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("quorum cannot be 0");
        ddl.approveOrgProposal(0, 0);
    }

    function test_removeOrgSignerRequest_quorumTooHigh() public {
        vm.startPrank(alice);
        ddl.removeOrgSignerReq(0, 0, 2, newURI);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("quorum can't be greater than number of members");
        ddl.approveOrgProposal(0, 0);
    }

    function test_removeOrgSignerRequest_signer_is_paused() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        ddl.removeOrgSignerReq(0, 0, 1, newURI);
    }

    /*
    updateOrgOrgQuorumReq
    - happy case (no quorum yet)
        - save proposal details
        - increment proposal counter
    - happy case (quorum reached)
        - proposal executed
        - quorum updated
    - require: sender must be member
    - require: quorum can't be 0
    - require: quorum can't be greater than # of members
    - require: org is active
    */

    function test_deactivatedOrg_updateOrgOrgQuorumReq() public {
        // Deactivate the org
        address[] memory assetList;
        vm.prank(irandaoModMultisig);
        ddl.deactivateOrgReq(
            0,
            assetList,
            DDL.OrgDeactivators.MODERATORS,
            newURI
        );

        // Cannot update a deactivated organization
        vm.expectRevert("organization is not active");
        vm.prank(alice);
        ddl.updateOrgOrgQuorumReq(0, 1, keepURI);
    }

    function test_updateOrgOrgQuorumReq() public {
        // =================================
        // Test Requirements
        vm.expectRevert("only organization members can call this function");
        ddl.updateOrgOrgQuorumReq(0, 0, keepURI);

        // =================================
        // Happy case, save proposal details
        vm.startPrank(alice);
        ddl.updateOrgOrgQuorumReq(0, 1, keepURI);
        vm.stopPrank();

        assertEq(ddl.didSignOrgTransaction(alice, 0, 0), true);
        assertEq(ddl.didSignOrgTransaction(bob, 0, 0), false);

        (
            address proposer,
            DDL.OrganizationProposalType transactionType,
            ,
            bytes memory data,
            bool isExecuted,
            uint8 signedCount
        ) = ddl.orgProposals(0, 0);
        assertEq(proposer, alice);
        assertEq(
            uint256(transactionType),
            uint256(DDL.OrganizationProposalType.UPDATE_QUORUM)
        );
        assertEq(data, abi.encode(1));
        assertFalse(isExecuted);
        assertEq(signedCount, 1);

        // =================================
        vm.startPrank(bob);
        ddl.approveOrgProposal(0, 0);
        // // Quorum cannot be 0
        // vm.expectRevert("quorum cannot be 0");
        // ddl.updateOrgOrgQuorumReq(0, 0, keepURI);
        // // Quorum can't be greater than # of members
        // vm.expectRevert("quorum can't be greater than number of members");
        // ddl.updateOrgOrgQuorumReq(0, 3, keepURI);
        // // Happy case, execute proposal
        // ddl.updateOrgOrgQuorumReq(0, 1, keepURI);
        vm.stopPrank();

        assertEq(ddl.didSignOrgTransaction(bob, 0, 0), true);

        (, , , , isExecuted, signedCount) = ddl.orgProposals(0, 0);
        assertTrue(isExecuted);
        assertEq(signedCount, 2);

        (, , , , bool hasMultisig, uint8 quorum, ) = ddl.organizations(0);
        assertFalse(hasMultisig);
        assertEq(quorum, 1);
    }

    /*
     * deactivateOrgReq
     */
    function test_deactivateOrgReq_mod() public {
        address[] memory tokens;
        vm.startPrank(irandaoModMultisig);
        ddl.deactivateOrgReq(
            0,
            tokens,
            DDL.OrgDeactivators.MODERATORS,
            keepURI
        );

        vm.expectRevert("organization is already deactivated");
        ddl.deactivateOrgReq(
            0,
            tokens,
            DDL.OrgDeactivators.MODERATORS,
            keepURI
        );
    }

    function test_deactivateOrgReq() public {
        address[] memory tokens;

        vm.prank(alice);
        assertTrue(
            ddl.deactivateOrgReq(
                0,
                tokens,
                DDL.OrgDeactivators.ORG_OWNERS,
                keepURI
            )
        );

        (, , bool isActive, , , , ) = ddl.organizations(0);
        assertTrue(isActive);

        vm.prank(bob);
        ddl.approveOrgProposal(0, 0);

        (, , isActive, , , , ) = ddl.organizations(0);
        assertFalse(isActive);
    }

    /*
     * updateOrgURI
     * - require: sender must be member
     * - require: org is active
     * - require: not paused
     * - happy case
     *     - orgURI updated
     */
    function test_updateOrgURI() public {
        vm.expectRevert("only organization members can call this function");
        vm.prank(charlie);
        ddl.updateOrgURI(0, "hack.com");

        vm.prank(alice);
        ddl.updateOrgURI(0, "hackhack.com");

        (, string memory uri, , , , , ) = ddl.organizations(0);
        assertEq(uri, "hackhack.com");

        address[] memory tokens;
        vm.prank(irandaoModMultisig);
        ddl.deactivateOrgReq(0, tokens, DDL.OrgDeactivators.MODERATORS, newURI);

        bool isActive;
        (, uri, isActive, , , , ) = ddl.organizations(0);
        assertEq(uri, newURI.uri);
        assertFalse(isActive);

        vm.expectRevert("organization is deactivated");
        vm.prank(alice);
        ddl.updateOrgURI(0, "hackhack.com");
    }

    /*
     * deactivateLineReq
     */
    function test_deactivateLineReq() public {
        vm.expectRevert("only organization members can call this function");
        vm.prank(irandaoModMultisig);
        ddl.deactivateLineReq(0, 0, keepURI);

        vm.prank(alice);
        ddl.deactivateLineReq(0, 0, keepURI);

        (, bool isActive, ) = ddl.orgsLines(0, 0);
        assertTrue(isActive);

        vm.prank(bob);
        ddl.approveOrgProposal(0, 0);

        (, isActive, ) = ddl.orgsLines(0, 0);
        assertFalse(isActive);
    }

    /*
     * updateEndgameData
     * - updates struct
     * - require: mods only
     * - require: not paused
     */
    function test_updateEndgameData() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.prank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        (bool isComplete, address endgameTreasury, address endgameGov) = ddl
            .endgamePlatform();
        assertEq(isComplete, true);
        assertEq(endgameTreasury, alice);
        assertEq(endgameGov, bob);
    }

    function test_updateEndgameData_only_mods() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.prank(alice);
        vm.expectRevert("only moderators can call this function");
        ddl.updateEndgameData(endgame_1);
    }

    function test_updateEndgameData_not_paused() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();

        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.expectRevert("Pausable: paused");
        ddl.updateEndgameData(endgame_1);
    }

    /*
     * transferModerationToCommunityRequest
     * - updates newModeratorCandidate
     * - require: migration is completed
     * - require: only mods
     * - require: not paused
     */
    function test_transferModerationToCommunityRequest() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        assertEq(ddl.newModeratorsCandidate(), bob);
    }

    function test_transferModerationToCommunityRequest_migration_incomplete()
        public
    {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            false,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        vm.expectRevert("endgame platform is not completed");
        ddl.transferModerationToCommunityRequest();
    }

    function test_transferModerationToCommunityRequest_only_mods() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            false,
            alice,
            bob
        );
        vm.prank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        vm.expectRevert("only moderators can call this function");
        ddl.transferModerationToCommunityRequest();
    }

    function test_transferModerationToCommunityRequest_not_paused() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.startMigrationProcess();
        vm.expectRevert("Pausable: paused");
        ddl.transferModerationToCommunityRequest();
    }

    /*
     * revokeTransferModerationToCommunityRequest
     * - updates newModeratorCandidate
     * - require: migration is completed
     * - require: only mods
     * - require: not paused
     */
    function test_revokeTransferModerationToCommunityRequest() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        assertEq(ddl.newModeratorsCandidate(), bob);
        ddl.revokeTransferModerationToCommunityRequest();
        assertEq(ddl.newModeratorsCandidate(), address(0));
    }

    function test_revokeModerationToCommunityRequest_no_new_mod() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            address(0)
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();

        DDL.EndgamePlatform memory endgame_2 = DDL.EndgamePlatform(
            false,
            alice,
            bob
        );
        ddl.updateEndgameData(endgame_2);
        vm.expectRevert("no new moderators candidate");
        ddl.revokeTransferModerationToCommunityRequest();
    }

    function test_revokeModerationToCommunityRequest_only_mods() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("only moderators can call this function");
        ddl.revokeTransferModerationToCommunityRequest();
    }

    function test_revokeModerationToCommunityRequest_not_paused() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        ddl.startMigrationProcess();
        vm.expectRevert("Pausable: paused");
        ddl.revokeTransferModerationToCommunityRequest();
    }

    /*
     * acceptModeration
     * - updates moderators & newMods candidate
     * - require: not paused
     * - require: msg.sender is endgame contract
     * - require: msg.sender is newMod candidate
     */
    function test_acceptModeration() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        vm.stopPrank();
        vm.startPrank(bob);
        ddl.acceptModeration();
        assertEq(ddl.moderators(), bob);
        assertEq(ddl.newModeratorsCandidate(), address(0));
    }

    function test_acceptModeration_not_paused() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        ddl.startMigrationProcess();
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert("Pausable: paused");
        ddl.acceptModeration();
    }

    function test_acceptModeration_is_endgame() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(
            "only endgame governance contract can accept moderation"
        );
        ddl.acceptModeration();
    }

    function test_acceptModeration_is_mod_candidate() public {
        DDL.EndgamePlatform memory endgame_1 = DDL.EndgamePlatform(
            true,
            alice,
            bob
        );
        vm.startPrank(irandaoModMultisig);
        ddl.updateEndgameData(endgame_1);
        ddl.transferModerationToCommunityRequest();
        // update endgame governance again
        DDL.EndgamePlatform memory endgame_2 = DDL.EndgamePlatform(
            true,
            charlie,
            alice
        );
        ddl.updateEndgameData(endgame_2);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("only new moderators candidate can accept moderation");
        ddl.acceptModeration();
    }

    /*
     * startMigrationProcess
     * - updates: migration deadline & pauses
     * - require: only mods
     * - require: not paused
     */

    function test_startMigrationProcess() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        assertEq(ddl.paused(), true);
    }

    function test_startMigrationProcess_only_mods() public {
        vm.startPrank(alice);
        vm.expectRevert("only moderators can call this function");
        ddl.startMigrationProcess();
    }

    function test_startMigrationProcess_not_paused() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        vm.expectRevert("Pausable: paused");
        ddl.startMigrationProcess();
    }

    /*
     * cancelMigrationProcess
     * - updates: migration deadline & unpauses
     * - require: only mods
     * - require: not paused
     */
    function test_cancelMigrationProcess() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        ddl.cancelMigrationProcess();
        assertEq(ddl.paused(), false);
        assertEq(ddl.migrateDeadline(), 0);
    }

    function test_cancelMigrationProcess_paused_only() public {
        vm.startPrank(irandaoModMultisig);
        vm.expectRevert("Pausable: not paused");
        ddl.cancelMigrationProcess();
    }

    function test_cancelMigrationProcess_mods_only() public {
        vm.startPrank(irandaoModMultisig);
        ddl.startMigrationProcess();
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert("only moderators can call this function");
        ddl.cancelMigrationProcess();
    }

    /*
     * migrateRemainingAssetToEndGameTreasury
     * - updates: tokens, NFTs, raw ETH
     * - require: migration deadline passed
     * - require: assets & amounts length
     * - require: assets & types length
     * - require: not paused
     * - require: mods only
     */
    function test_migrateRemainingAssetToEndGameTreasury() public {
        // Donate as Alice
        vm.startPrank(alice);
        SafeTransferLib.safeTransferETH(address(ddl), 10);
        dai.approve(address(ddl), 20);
        ddl.donateToLineWithToken(0, 0, address(dai), 20); // donate 20dai
        nft.safeTransferFrom(alice, address(ddl), 1);
        vm.stopPrank();

        assertEq(address(ddl).balance, 10);
        assertEq(dai.balanceOf(address(ddl)), 20);

        // Start the migration process
        vm.prank(irandaoModMultisig);
        ddl.startMigrationProcess();

        address[] memory assets_ = new address[](3);
        uint256[] memory amounts_ = new uint256[](3);
        DDL.MigrationTransferAssetType[]
            memory types_ = new DDL.MigrationTransferAssetType[](3);
        // ETH
        assets_[0] = address(0);
        amounts_[0] = 10;
        types_[0] = DDL.MigrationTransferAssetType.ETH;
        // ERC20
        assets_[1] = address(dai);
        amounts_[1] = 20;
        types_[1] = DDL.MigrationTransferAssetType.ERC20;
        // ERC721
        assets_[2] = address(nft);
        amounts_[2] = 1;
        types_[2] = DDL.MigrationTransferAssetType.ERC721;

        vm.startPrank(alice);
        vm.expectRevert("only moderators can call this function");
        ddl.migrateRemainingAssetToEndGameTreasury(assets_, amounts_, types_);
        vm.stopPrank();

        vm.startPrank(irandaoModMultisig);
        // Skip to the boundary condition
        vm.warp(block.timestamp + 15 days);
        vm.expectRevert("migration deadline is not reached yet");
        ddl.migrateRemainingAssetToEndGameTreasury(assets_, amounts_, types_);

        // Now it should work
        vm.warp(block.timestamp + 2 minutes);
        ddl.migrateRemainingAssetToEndGameTreasury(assets_, amounts_, types_);

        // ETH
        assertEq(endgame.balance, 10);
        assertEq(address(ddl).balance, 0);
        // ERC20
        assertEq(dai.balanceOf(endgame), 20);
        assertEq(dai.balanceOf(address(ddl)), 0);
        // ERC721
        assertEq(nft.ownerOf(1), endgame);
    }
}
