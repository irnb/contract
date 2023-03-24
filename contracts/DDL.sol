// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "solady/src/utils/SignatureCheckerLib.sol";
import "solady/src/utils/EIP712.sol";
import "solady/src/utils/SafeTransferLib.sol";

import "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/security/Pausable.sol";

//    .--..--..--..--..--..--..--..--..--..--..--..--..--..--..--..--.
//   / .. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \.. \
//   \ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/ /
//   \/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /
//   / /\/ /`' /`' /`' /`' /`' /`' /`' /`' /`' /`' /`' /`' /`' /\/ /\
//   / /\ \/`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'\ \/\ \
//   \ \/\ \                                                    /\ \/ /
//   \/ /\ \                                                    / /\/ /
//   / /\/ /           Direct Donation Line Contract            \ \/ /\
//   / /\ \/                                                    \ \/\ \
//   \ \/\ \           part of Endgame Platform                 /\ \/ /
//   \/ /\ \                                                    / /\/ /
//   / /\/ /           by IranDao                               \ \/ /\
//   / /\ \/                                                    \ \/\ \
//   \ \/\ \.--..--..--..--..--..--..--..--..--..--..--..--..--./\ \/ /
//   \/ /\/ ../ ../ ../ ../ ../ ../ ../ ../ ../ ../ ../ ../ ../ /\/ /
//   / /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\/ /\
//   / /\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \/\ \
//   \ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `'\ `' /
//   `--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'`--'s

// @todo write simple URI data structure and put the link in the comments

contract DDL is Pausable, ReentrancyGuard, EIP712 {
    /**
     *
     * GLOBAL CONSTANTS
     *
     */
    address internal constant ETH_REPRESENTOR_ADDRESS = address(0);

    // @notice moderators is Gnosis Safe Multisig
    // @dev after calling transferModerationToCommunityRequest() a Candidate moderators will be set to endgameGovernanceContract
    // and after calling acceptModeration() by endgameGovernanceContract, moderators will be set to endgameGovernanceContract
    address public moderators;
    address public newModeratorsCandidate;

    /*
    @dev in the early stage of the platform, endgameTreasury will be Gnosis Safe Multisig
    and after completing the development of Endgame Platform, endgameTreasury will be set to endgameTreasury contract
    and aggregated donations will be transferred to endgameTreasury contract
    */
    EndgamePlatform public endgamePlatform;

    /*
    @dev if in the future we want to migrate the platform to another contract, we can set a deadline for migration
    and in MIGRATION_DURATION, no one can create new organization or line and user also can't donate to lines
    the organization can only withdraw their donations
    and after migrationDeadline, the moderators can drain the remaining donations to endgameTreasury
    */
    uint64 public migrateDeadline;
    uint64 public constant MIGRATION_DURATION = 15 days;

    uint64 public constant PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL = 5 days;

    uint256 public orgRegistrationSpamProtectionFee;
    /**
     *
     * STATE VARIABLES
     *
     */

    uint16 public orgId;
    // @dev organizationId => organization
    mapping(uint16 => Organization) public organizations;
    // @dev organizationId => (signerId => signer)
    mapping(uint16 => mapping(uint8 => address)) public orgMembers;
    // @dev address => (organizationId => bool)e
    mapping(address => mapping(uint16 => bool)) public isOrgMember;

    // @dev organizationId => (line id => Line)
    mapping(uint16 => mapping(uint8 => Line)) public orgsLines;

    // @dev organizationId => (transaction id => transaction)
    mapping(uint16 => mapping(uint48 => OrgMultiApproveTransaction))
        public orgProposals;

    mapping(uint16 => mapping(uint8 => OrgExternalDonationAddress))
        public organizationExternalDonationAddresses;

    mapping(uint16 => mapping(address => uint256))
        public organizationTotalDonationsPerAsset;

    mapping(uint16 => mapping(uint8 => mapping(address => uint256)))
        public lineReceivedDonationsPerAsset;

    // @dev for keeping code flow simple, the zero lineId is empty line
    // @dev for keeping code flow simple, the zero proposalId is empty proposal

    mapping(uint16 => OrganizationIdData) public organizationIdRelatedData;

    /**
     *
     * EVENTS
     *
     */

    event OrgCreated(
        uint16 indexed organizationId,
        string title,
        string uri,
        address[] signers,
        uint8 quorum
    );
    event LineCreated(
        uint16 indexed organizationId,
        uint8 lineId,
        string title
    );
    event DeactivatedLine(uint16 organizationId, uint8 line);
    event DeactivatedOrg(
        uint16 organizationId,
        OrgDeactivators orgDeactivators
    );
    event SignerAdded(uint16 organizationId, address newSigner);
    event SignerRemoved(uint16 organizationId, address newSigner);
    event UpdateSecureMessagingPubKey(uint16 organizationId, string _spkp);
    event UpdateOrgExternalDonationAddress(
        uint16 organizationId,
        uint8 externalDonationAddressId,
        string network,
        string addr
    );
    event OrgURIUpdated(uint16 organizationId, string uri);

    /**
     *
     * STRUCT & ENUMS
     *
     */

    enum OrganizationProposalType {
        ADD_SIGNER,
        REMOVE_SIGNER,
        UPDATE_QUORUM,
        ADD_ORG_EXTERNAL_DONATION_ADDRESS,
        UPDATE_ORG_EXTERNAL_DONATION_ADDRESS,
        UPDATE_ORG_SECURE_MESSAGING_PUB_KEY,
        DEACTIVATE_LINE,
        DEACTIVATE_ORG,
        WITHDRAW_FROM_LINES
    }

    enum OrgDeactivators {
        MODERATORS,
        ORG_OWNERS
    }

    // @notice this contract is not supporting ERC721 donation. but we are designing a flow for it
    // if someone accidentally sends ERC721 to this contract, we can transfer it to endgameTreasury contract
    // in the migration process.
    enum MigrationTransferAssetType {
        ETH,
        ERC20,
        ERC721
    }

    struct Organization {
        string title;
        string orgURI;
        bool isActive;
        bool isVerified;
        bool hasMultisig;
        uint8 quorum;
        string secureMessagingPubKey;
    }

    struct OrganizationIdData {
        uint8 lineId;
        uint8 externalDonationAddressId;
        uint8 signerId;
        uint48 proposalId;
    }

    struct Line {
        string title;
        bool isActive;
        bool isPrivacyProviderLine;
    }

    struct OrgExternalDonationAddress {
        string networkName;
        string externalDonationAddress;
    }

    struct OrgMultiApproveTransaction {
        address proposer;
        OrganizationProposalType transactionType;
        uint64 validUntil;
        bytes data;
        bool isExecuted;
        mapping(address => bool) isSigned;
        uint8 signedCount;
    }

    struct EndgamePlatform {
        bool isCompleted;
        address endgameTreasury;
        address endgameGovernanceContract;
    }

    struct NewURI {
        string uri;
        bool needToChange;
    }

    /**
     *
     * MODIFIER FUNCTIONS
     *
     */

    modifier onlyModerators() {
        require(
            msg.sender == moderators,
            "only moderators can call this function"
        );
        _;
    }

    modifier onlyOrgMembers(uint16 _organizationId) {
        require(
            isOrgMember[msg.sender][_organizationId],
            "only organization members can call this function"
        );
        _;
    }

    /**
     *
     * CONSTRUCTOR & RECEIVE
     *
     */
    constructor(
        address _daoMultiSigModerators,
        address _endgameTreasury,
        string memory _firstOrgTitle,
        string memory _firstOrgURI,
        address[] memory _firstOrgSigners,
        uint8 _firstOrgQuorum,
        string memory _firstOrgSecureMessagingPubKey,
        OrgExternalDonationAddress[] memory _firstOrgExternalDonationAddresses,
        uint256 _orgRegistrationSpamProtectionFee
    ) EIP712() ReentrancyGuard() Pausable() {
        moderators = _daoMultiSigModerators;
        endgamePlatform.endgameTreasury = _endgameTreasury;
        orgRegistrationSpamProtectionFee = _orgRegistrationSpamProtectionFee;

        _createOrg(
            _firstOrgTitle,
            _firstOrgURI,
            _firstOrgSigners,
            _firstOrgQuorum,
            _firstOrgSecureMessagingPubKey,
            _firstOrgExternalDonationAddresses
        );

        // create first line of organization
        // this line is used to receive donations that sends through receive() function
        Line storage line = orgsLines[0][0];
        line.isActive = true;
        emit LineCreated(0, 0, "");
    }

    receive() external payable whenNotPaused {
        lineReceivedDonationsPerAsset[0][0][ETH_REPRESENTOR_ADDRESS] += msg
            .value;
        organizationTotalDonationsPerAsset[0][ETH_REPRESENTOR_ADDRESS] += msg
            .value;
    }

    /**
     *
     * EXTERNAL FUNCTIONS
     *
     */

    /**
     *
     * ORGANIZATION AND LINES MANAGEMENT
     *
     */

    function registerAnOrg(
        string calldata _title,
        string calldata _orgURI,
        address[] calldata _signers,
        bytes[] calldata _memberApproveJoinSignature,
        uint256[] calldata _timestamps,
        uint8 _quorum,
        string calldata _secureMessagingPubKey,
        OrgExternalDonationAddress[] calldata _externalDonationAddresses
    ) external payable whenNotPaused returns (uint16 id) {
        require(
            msg.value >= orgRegistrationSpamProtectionFee,
            "not enough ETH to register an organization"
        );
        require(
            _signers.length == _memberApproveJoinSignature.length,
            "signers and approve join messages length must be equal"
        );
        require(
            _signers.length == _timestamps.length,
            "signers and timestamps length must be equal"
        );

        // check validity of signatures and expiration of approve join messages
        for (uint8 i = 0; i < _signers.length; ++i) {
            require(
                SignatureCheckerLib.isValidSignatureNow(
                    _signers[i],
                    createMessageHash(
                        _orgURI,
                        _signers[i],
                        msg.sender,
                        _timestamps[i]
                    ),
                    _memberApproveJoinSignature[i]
                ),
                "invalid signature"
            );
            require(
                block.timestamp <
                    _timestamps[i] + PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL,
                "approve join message is expired"
            );
        }

        id = _createOrg(
            _title,
            _orgURI,
            _signers,
            _quorum,
            _secureMessagingPubKey,
            _externalDonationAddresses
        );
    }

    function verifyOrg(
        uint16 _organizationId
    ) external onlyModerators whenNotPaused {
        organizations[_organizationId].isVerified = true;
    }

    function givePrivacyProviderRoleToAnOrgLine(
        uint16 _organizationId,
        uint8 _lineId
    ) external onlyModerators whenNotPaused {
        Line storage line = orgsLines[_organizationId][_lineId];
        require(line.isActive, "line is not active");
        line.isPrivacyProviderLine = true;
    }

    function removePrivacyProviderRoleFromAnOrgLine(
        uint16 _organizationId,
        uint8 _lineId,
        NewURI calldata _newURI
    ) external whenNotPaused {
        require(
            isOrgMember[msg.sender][_organizationId] ||
                msg.sender == moderators,
            "only organization members or moderators"
        );
        _updateOrgURI(_organizationId, _newURI);

        orgsLines[_organizationId][_lineId].isPrivacyProviderLine = false;
    }

    function deactivateOrgReq(
        uint16 _organizationId,
        address[] memory assetAddresses,
        OrgDeactivators _deactivator,
        NewURI calldata _newURI
    ) external whenNotPaused returns (bool) {
        require(
            organizations[_organizationId].isActive,
            "organization is already deactivated"
        );

        if (_deactivator == OrgDeactivators.ORG_OWNERS) {
            require(
                isOrgMember[msg.sender][_organizationId],
                "sender is not an org member"
            );

            bool shouldCreateProposal = _requestHandler(
                _organizationId,
                _newURI
            );

            if (shouldCreateProposal) {
                _createOrganizationProposal(
                    _organizationId,
                    OrganizationProposalType.DEACTIVATE_ORG,
                    abi.encode(assetAddresses, _deactivator)
                );
            } else {
                _executeDeactivatedOrganizationRequest(
                    _organizationId,
                    assetAddresses,
                    _deactivator
                );
            }

            return true;
        } else if (_deactivator == OrgDeactivators.MODERATORS) {
            require(msg.sender == moderators, "sender is not a moderator");

            _executeDeactivatedOrganizationRequest(
                _organizationId,
                assetAddresses,
                _deactivator
            );

            _updateOrgURI(_organizationId, _newURI);

            return true;
        }

        return false;
    }

    function createLine(
        uint16 _organizationId,
        string calldata _title
    )
        external
        onlyOrgMembers(_organizationId)
        whenNotPaused
        returns (uint8 _lineId)
    {
        require(
            organizations[_organizationId].isActive,
            "organization is deactivated"
        );

        _lineId = _incrementOrgLineId(_organizationId);
        Line storage line = orgsLines[_organizationId][_lineId];

        line.title = _title;
        line.isActive = true;

        emit LineCreated(_organizationId, _lineId, _title);
    }

    function deactivateLineReq(
        uint16 _organizationId,
        uint8 _lineId,
        NewURI calldata _newURI
    ) external onlyOrgMembers(_organizationId) whenNotPaused {
        require(
            orgsLines[_organizationId][_lineId].isActive,
            "line is not active"
        );

        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.DEACTIVATE_LINE,
                abi.encode(_lineId)
            );
        } else {
            _deactivateLine(_organizationId, _lineId);
        }
    }

    function withdrawDonationFromLinesRequest(
        uint16 _organizationId,
        uint8[] calldata _lineIds,
        address[] calldata _assetAddresses,
        uint256[] calldata _amounts,
        NewURI calldata _newURI
    ) external {
        require(
            _lineIds.length == _assetAddresses.length,
            "length should be equal"
        );
        require(_lineIds.length == _amounts.length, "length should be equal");

        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.WITHDRAW_FROM_LINES,
                abi.encode(_lineIds, _assetAddresses, _amounts)
            );
        } else {
            _executeWithdrawDonationFromLinesRequest(
                _organizationId,
                _lineIds,
                _assetAddresses,
                _amounts
            );
        }
    }

    /**
     *
     * SIGNER AND ORGANIZATION DATA MANAGEMENT
     *
     */

    function addExternalDonationAddressToOrgReq(
        uint16 _organizationId,
        OrgExternalDonationAddress calldata _externalDonationAddress,
        NewURI calldata _newURI
    ) external whenNotPaused {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.ADD_ORG_EXTERNAL_DONATION_ADDRESS,
                abi.encode(_externalDonationAddress)
            );
        } else {
            uint8 _externalDonationAddressId = _incrementOrgExternalDonationAddressId(
                    _organizationId
                );

            _updateOrgExternalDonationAddress(
                _organizationId,
                _externalDonationAddress,
                _externalDonationAddressId
            );
        }
    }

    function updateExternalDonationAddressOfOrgReq(
        uint16 _organizationId,
        uint8 _externalDonationAddressId,
        OrgExternalDonationAddress calldata _externalDonationAddress,
        NewURI calldata _newURI
    ) external whenNotPaused {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.UPDATE_ORG_EXTERNAL_DONATION_ADDRESS,
                abi.encode(_externalDonationAddressId, _externalDonationAddress)
            );
        } else {
            _updateOrgExternalDonationAddress(
                _organizationId,
                _externalDonationAddress,
                _externalDonationAddressId
            );
        }
    }

    function addOrgSignerReq(
        uint16 _organizationId,
        address _signer,
        uint8 _newQuorum,
        NewURI calldata _newURI
    ) external whenNotPaused {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.ADD_SIGNER,
                abi.encode(_signer, _newQuorum)
            );
        } else {
            _executeAddSignerRequest(
                organizations[_organizationId],
                _organizationId,
                _signer,
                _newQuorum
            );
        }
    }

    function removeOrgSignerReq(
        uint16 _organizationId,
        uint8 _signerId,
        uint8 _newQuorum,
        NewURI calldata _newURI
    ) external whenNotPaused {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.REMOVE_SIGNER,
                abi.encode(_signerId, _newQuorum)
            );
        } else {
            _executeRemoveSignerRequest(
                organizations[_organizationId],
                _organizationId,
                _signerId,
                _newQuorum
            );
        }
    }

    function updateOrgOrgQuorumReq(
        uint16 _organizationId,
        uint8 _quorum,
        NewURI calldata _newURI
    ) external whenNotPaused onlyOrgMembers(_organizationId) {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.UPDATE_QUORUM,
                abi.encode(_quorum)
            );
        } else {
            _updateQuorum(_organizationId, _quorum);
        }
    }

    function updateOrgSecureMessagingPubKeyReq(
        uint16 _organizationId,
        string calldata _secureMessagingPubKey,
        NewURI calldata _newURI
    ) external whenNotPaused {
        bool shouldCreateProposal = _requestHandler(_organizationId, _newURI);

        if (shouldCreateProposal) {
            _createOrganizationProposal(
                _organizationId,
                OrganizationProposalType.UPDATE_ORG_SECURE_MESSAGING_PUB_KEY,
                abi.encode(_secureMessagingPubKey)
            );
        } else {
            _updateSecureMessagingPubKey(
                _organizationId,
                _secureMessagingPubKey
            );
        }
    }

    function updateOrgURI(
        uint16 _organizationId,
        string calldata _orgURI
    ) external onlyOrgMembers(_organizationId) whenNotPaused {
        Organization storage organization = organizations[_organizationId];
        require(organization.isActive, "organization is deactivated");

        organization.orgURI = _orgURI;

        emit OrgURIUpdated(_organizationId, _orgURI);
    }

    /**
     *
     * APPROVE AND REVOKE PROPOSAL
     *
     */

    function approveOrgProposal(
        uint16 _organizationId,
        uint48 _proposalId
    ) external onlyOrgMembers(_organizationId) {
        OrgMultiApproveTransaction storage orgProposal = orgProposals[
            _organizationId
        ][_proposalId];
        require(!orgProposal.isExecuted, "proposal is already executed");
        require(
            orgProposal.validUntil > block.timestamp,
            "proposal is expired"
        );
        require(!orgProposal.isSigned[msg.sender], "already signed");

        orgProposal.isSigned[msg.sender] = true;
        orgProposal.signedCount++;

        if (orgProposal.signedCount >= organizations[_organizationId].quorum) {
            _executeOrgProposal(_organizationId, _proposalId);
        }
    }

    function revokeOrgProposal(
        uint16 _organizationId,
        uint48 _proposalId
    ) external onlyOrgMembers(_organizationId) {
        OrgMultiApproveTransaction storage orgProposal = orgProposals[
            _organizationId
        ][_proposalId];
        require(!orgProposal.isExecuted, "proposal is already executed");
        require(
            orgProposal.validUntil > block.timestamp,
            "proposal is expired"
        );
        require(orgProposal.isSigned[msg.sender], "not signed");

        orgProposal.isSigned[msg.sender] = false;
        orgProposal.signedCount--;
    }

    /**
     *
     * DONATION
     *
     */

    function donateToLineWithMainToken(
        uint16 _organizationId,
        uint8 _lineId
    ) external payable whenNotPaused {
        Organization storage organization = organizations[_organizationId];

        require(organization.isActive, "organization is not active");

        Line storage line = orgsLines[_organizationId][_lineId];

        require(line.isActive, "line is not active");

        if (line.isPrivacyProviderLine) {
            require(
                msg.sender == endgamePlatform.endgameTreasury,
                "only endgame treasury can donate to privacy line"
            );
        }

        uint256 amount = msg.value;

        lineReceivedDonationsPerAsset[_organizationId][_lineId][
            ETH_REPRESENTOR_ADDRESS
        ] += amount;

        organizationTotalDonationsPerAsset[_organizationId][
            ETH_REPRESENTOR_ADDRESS
        ] += amount;
    }

    function donateToLineWithToken(
        uint16 _organizationId,
        uint8 _lineId,
        address _tokenAddress,
        uint256 _amount
    ) external nonReentrant whenNotPaused {
        Organization storage organization = organizations[_organizationId];

        require(organization.isActive, "organization is not active");

        Line storage line = orgsLines[_organizationId][_lineId];

        require(line.isActive, "line is not active");

        if (line.isPrivacyProviderLine) {
            require(
                msg.sender == endgamePlatform.endgameTreasury,
                "only endgame treasury can donate to privacy line"
            );
        }

        SafeTransferLib.safeTransferFrom(
            _tokenAddress,
            msg.sender,
            address(this),
            _amount
        );

        lineReceivedDonationsPerAsset[_organizationId][_lineId][
            _tokenAddress
        ] += _amount;

        organizationTotalDonationsPerAsset[_organizationId][
            _tokenAddress
        ] += _amount;
    }

    /**
     *
     * TRANSFER CONTRACT MODERATION TO COMMUNITY
     *
     */

    function updateEndgameData(
        EndgamePlatform calldata _endgamePlatform
    ) external onlyModerators whenNotPaused {
        endgamePlatform = _endgamePlatform;
    }

    function transferModerationToCommunityRequest()
        external
        onlyModerators
        whenNotPaused
    {
        require(
            endgamePlatform.isCompleted,
            "endgame platform is not completed"
        );
        newModeratorsCandidate = endgamePlatform.endgameGovernanceContract;
    }

    function revokeTransferModerationToCommunityRequest()
        external
        onlyModerators
        whenNotPaused
    {
        require(
            newModeratorsCandidate != address(0),
            "no new moderators candidate"
        );
        newModeratorsCandidate = address(0);
    }

    function acceptModeration() external whenNotPaused {
        require(
            msg.sender == endgamePlatform.endgameGovernanceContract,
            "only endgame governance contract can accept moderation"
        );
        require(
            msg.sender == newModeratorsCandidate,
            "only new moderators candidate can accept moderation"
        );

        moderators = newModeratorsCandidate;
        newModeratorsCandidate = address(0);
    }

    /**
     *
     * MIGRATION TO NEW CONTRACT
     *
     */

    function startMigrationProcess() external onlyModerators whenNotPaused {
        migrateDeadline = uint64(block.timestamp) + MIGRATION_DURATION;

        _pause();
    }

    function cancelMigrationProcess() external onlyModerators whenPaused {
        migrateDeadline = 0;

        _unpause();
    }

    function migrateRemainingAssetToEndGameTreasury(
        address[] calldata assets,
        uint256[] calldata amounts,
        MigrationTransferAssetType[] calldata transferAssetTypes
    ) external onlyModerators whenPaused {
        require(
            migrateDeadline < block.timestamp,
            "migration deadline is not reached yet"
        );
        require(
            assets.length == amounts.length,
            "assets and amounts length should be equal"
        );
        require(
            assets.length == transferAssetTypes.length,
            "assets and transferAssetTypes length should be equal"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            if (transferAssetTypes[i] == MigrationTransferAssetType.ERC20) {
                _transferToken(
                    assets[i],
                    endgamePlatform.endgameTreasury,
                    amounts[i]
                );
            } else if (
                transferAssetTypes[i] == MigrationTransferAssetType.ERC721
            ) {
                _transferNFT(
                    assets[i],
                    endgamePlatform.endgameTreasury,
                    amounts[i]
                );
            } else if (
                transferAssetTypes[i] == MigrationTransferAssetType.ETH
            ) {
                _transferMainToken(
                    payable(endgamePlatform.endgameTreasury),
                    amounts[i]
                );
            }
        }
    }

    /**
     *
     * GETTER FUNCTIONS
     *
     */

    function didSignOrgTransaction(
        address signer,
        uint16 _orgId,
        uint48 _orgProposalId
    ) external view returns (bool) {
        OrgMultiApproveTransaction storage orgTx = orgProposals[_orgId][
            _orgProposalId
        ];
        return orgTx.isSigned[signer];
    }

    function hasPrivacyProviderRole(
        uint16 _organizationId,
        uint8 _lineId
    ) external view returns (bool) {
        return orgsLines[_organizationId][_lineId].isPrivacyProviderLine;
    }

    function orgURI(
        uint16 _organizationId
    ) external view returns (string memory) {
        return organizations[_organizationId].orgURI;
    }

    function getOrganizationRelatedId(
        uint16 _organizationId
    )
        external
        view
        returns (
            uint8 latestExternalDonationAddressId,
            uint8 latestSignerId,
            uint8 latestLineId,
            uint48 latestProposalId
        )
    {
        OrganizationIdData
            memory organizationIdData = organizationIdRelatedData[
                _organizationId
            ];
        latestExternalDonationAddressId = organizationIdData
            .externalDonationAddressId;
        latestSignerId = organizationIdData.signerId;
        latestLineId = organizationIdData.lineId;
        latestProposalId = organizationIdData.proposalId;
    }

    function createMessageHash(
        string calldata _orgURI,
        address signer,
        address inviter,
        uint256 timestamp
    ) public view returns (bytes32 dataHash) {
        dataHash = _hashTypedData(
            keccak256(abi.encodePacked(_orgURI, signer, inviter, timestamp))
        );
    }

    /**
     *
     * HELPER FUNCTIONS
     *
     */

    function _incrementOrgSignerId(
        uint16 _organizationId
    ) internal returns (uint8) {
        OrganizationIdData
            storage organizationIdData = organizationIdRelatedData[
                _organizationId
            ];

        return ++organizationIdData.signerId;
    }

    function _incrementOrgLineId(
        uint16 _organizationId
    ) internal returns (uint8) {
        OrganizationIdData
            storage organizationIdData = organizationIdRelatedData[
                _organizationId
            ];

        return ++organizationIdData.lineId;
    }

    function _incrementOrgProposalId(
        uint16 _organizationId
    ) internal returns (uint48) {
        OrganizationIdData
            storage organizationIdData = organizationIdRelatedData[
                _organizationId
            ];

        return organizationIdData.proposalId++;
    }

    function _incrementOrgExternalDonationAddressId(
        uint16 _organizationId
    ) internal returns (uint8) {
        OrganizationIdData
            storage organizationIdData = organizationIdRelatedData[
                _organizationId
            ];

        return ++organizationIdData.externalDonationAddressId;
    }

    function _requestHandler(
        uint16 _organizationId,
        NewURI calldata _newURI
    ) internal returns (bool shouldCreateProposal) {
        Organization storage organization = organizations[_organizationId];
        require(organization.isActive, "organization is not active");
        require(
            isOrgMember[msg.sender][_organizationId],
            "only organization members can call this function"
        );

        _updateOrgURI(_organizationId, _newURI);

        if (organization.hasMultisig && organization.quorum > 1) {
            shouldCreateProposal = true;
        }
    }

    function _createOrg(
        string memory _title,
        string memory _uri,
        address[] memory _signers,
        uint8 _quorum,
        string memory _secureMessagingPubKey,
        OrgExternalDonationAddress[] memory _externalDonationAddresses
    ) internal returns (uint16 _organizationId) {
        require(_signers.length != 0, "signers cannot be empty");
        require(_quorum != 0, "quorum cannot be 0");
        require(
            _quorum <= _signers.length,
            "quorum cannot be greater than signers length"
        );

        _organizationId = orgId++;
        Organization storage _organization = organizations[_organizationId];

        _organization.title = _title;
        _organization.orgURI = _uri;
        _organization.quorum = _quorum;
        _organization.secureMessagingPubKey = _secureMessagingPubKey;
        _organization.isActive = true;
        _organization.isVerified = false;

        if (_signers.length != 1) {
            _organization.hasMultisig = true;
        }

        uint8 signerId = 0;
        // set first signer
        _addSigner(_organizationId, _signers[0], signerId);

        // set other signers
        for (uint8 i = 1; i < _signers.length; i++) {
            signerId = _incrementOrgSignerId(_organizationId);
            _addSigner(_organizationId, _signers[i], signerId);
        }

        uint8 externalDonationAddressId = 0;
        // set first external donation address
        _updateOrgExternalDonationAddress(
            _organizationId,
            _externalDonationAddresses[0],
            externalDonationAddressId
        );

        // set other external donation addresses
        for (uint8 i = 1; i < _externalDonationAddresses.length; i++) {
            externalDonationAddressId = _incrementOrgExternalDonationAddressId(
                _organizationId
            );
            _updateOrgExternalDonationAddress(
                _organizationId,
                _externalDonationAddresses[i],
                externalDonationAddressId
            );
        }

        emit OrgCreated(
            _organizationId,
            _organization.title,
            _organization.orgURI,
            _signers,
            _organization.quorum
        );
    }

    function _createOrganizationProposal(
        uint16 _organizationId,
        OrganizationProposalType _proposalType,
        bytes memory _data
    ) internal {
        OrgMultiApproveTransaction
            storage organizationTransaction = orgProposals[_organizationId][
                _incrementOrgProposalId(_organizationId)
            ];

        organizationTransaction.transactionType = _proposalType;
        organizationTransaction.proposer = msg.sender;
        organizationTransaction.isSigned[msg.sender] = true;
        organizationTransaction.signedCount = 1;
        organizationTransaction.validUntil =
            uint64(block.timestamp) +
            PROPOSAL_AND_SIGNER_SIGNATURE_VALID_UNTIL;
        organizationTransaction.data = _data;
    }

    function _deactivateLine(uint16 _organizationId, uint8 _lineId) internal {
        Line storage line = orgsLines[_organizationId][_lineId];
        line.isActive = false;

        emit DeactivatedLine(_organizationId, _lineId);
    }

    function _addSigner(
        uint16 _organizationId,
        address _signer,
        uint8 _signerId
    ) internal {
        require(_signer != address(0), "signer cannot be 0x0");
        require(
            !isOrgMember[_signer][_organizationId],
            "signer already exists"
        );

        orgMembers[_organizationId][_signerId] = _signer;
        isOrgMember[_signer][_organizationId] = true;

        emit SignerAdded(_organizationId, _signer);
    }

    function _updateQuorum(uint16 _organizationId, uint8 _quorum) internal {
        require(_quorum != 0, "quorum cannot be 0");
        require(
            _quorum <= organizationIdRelatedData[_organizationId].signerId + 1,
            "quorum can't be greater than number of members"
        );

        if (_quorum == 1) {
            organizations[_organizationId].hasMultisig = false;
        }
        organizations[_organizationId].quorum = _quorum;
    }

    function _executeAddSignerRequest(
        Organization storage organization,
        uint16 _organizationId,
        address _signer,
        uint8 _quorum
    ) internal {
        require(organization.isActive, "organization is deactivated");
        if (!organization.hasMultisig) {
            organization.hasMultisig = true;
        }
        uint8 signerId = _incrementOrgSignerId(_organizationId);
        _addSigner(_organizationId, _signer, signerId);
        _updateQuorum(_organizationId, _quorum);
    }

    function _executeRemoveSignerRequest(
        Organization storage organization,
        uint16 _organizationId,
        uint8 _signerId,
        uint8 _quorum
    ) internal {
        require(organization.isActive, "organization is deactivated");
        address signer = orgMembers[_organizationId][_signerId];
        delete isOrgMember[signer][_organizationId];

        uint8 orgSignerId = organizationIdRelatedData[_organizationId].signerId;
        for (uint8 i = _signerId; i < orgSignerId; i++) {
            orgMembers[_organizationId][i] = orgMembers[_organizationId][i + 1];
        }

        delete orgMembers[_organizationId][orgSignerId];
        organizationIdRelatedData[_organizationId].signerId--;

        if (orgSignerId == 1) {
            organization.hasMultisig = false;
        }

        _updateQuorum(_organizationId, _quorum);

        emit SignerRemoved(_organizationId, signer);
    }

    function _updateSecureMessagingPubKey(
        uint16 _organizationId,
        string memory _secureMessagingPubKey
    ) internal {
        organizations[_organizationId]
            .secureMessagingPubKey = _secureMessagingPubKey;

        emit UpdateSecureMessagingPubKey(
            _organizationId,
            _secureMessagingPubKey
        );
    }

    function _executeWithdrawDonationFromLinesRequest(
        uint16 _organizationId,
        uint8[] memory _lineIds,
        address[] memory _assetAddresses,
        uint256[] memory _amounts
    ) internal {
        uint256 length = _lineIds.length;
        for (uint256 i = 0; i < length; i++) {
            require(_amounts[i] > 0, "amount must be greater than zero");
            require(
                _amounts[i] <=
                    lineReceivedDonationsPerAsset[_organizationId][_lineIds[i]][
                        _assetAddresses[i]
                    ],
                "amount must be less than or equal to received donations"
            );
            lineReceivedDonationsPerAsset[_organizationId][_lineIds[i]][
                _assetAddresses[i]
            ] -= _amounts[i];

            organizationTotalDonationsPerAsset[_organizationId][
                _assetAddresses[i]
            ] -= _amounts[i];

            if (_assetAddresses[i] == ETH_REPRESENTOR_ADDRESS) {
                _transferMainToken(payable(msg.sender), _amounts[i]);
            } else {
                _transferToken(_assetAddresses[i], msg.sender, _amounts[i]);
            }
        }
    }

    function _executeDeactivatedOrganizationRequest(
        uint16 _organizationId,
        address[] memory assets,
        OrgDeactivators _orgDeactivators
    ) internal {
        Organization storage organization = organizations[_organizationId];
        organization.isActive = false;

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == ETH_REPRESENTOR_ADDRESS) {
                _transferMainToken(
                    payable(endgamePlatform.endgameTreasury),
                    organizationTotalDonationsPerAsset[_organizationId][
                        assets[i]
                    ]
                );
            } else {
                _transferToken(
                    assets[i],
                    endgamePlatform.endgameTreasury,
                    organizationTotalDonationsPerAsset[_organizationId][
                        assets[i]
                    ]
                );
            }
        }

        emit DeactivatedOrg(_organizationId, _orgDeactivators);
    }

    function _updateOrgExternalDonationAddress(
        uint16 _organizationId,
        OrgExternalDonationAddress memory _externalDonationAddress,
        uint8 _externalDonationAddressId
    ) internal {
        organizationExternalDonationAddresses[_organizationId][
            _externalDonationAddressId
        ] = _externalDonationAddress;

        emit UpdateOrgExternalDonationAddress(
            _organizationId,
            _externalDonationAddressId,
            _externalDonationAddress.networkName,
            _externalDonationAddress.externalDonationAddress
        );
    }

    function _updateOrgURI(
        uint16 _organizationId,
        NewURI calldata _newURI
    ) internal {
        if (_newURI.needToChange) {
            organizations[_organizationId].orgURI = _newURI.uri;

            emit OrgURIUpdated(_organizationId, _newURI.uri);
        }
    }

    function _executeOrgProposal(
        uint16 _organizationId,
        uint48 _proposalId
    ) internal {
        OrgMultiApproveTransaction storage proposal = orgProposals[
            _organizationId
        ][_proposalId];

        if (
            proposal.transactionType ==
            OrganizationProposalType.WITHDRAW_FROM_LINES
        ) {
            (
                uint8[] memory lineIds,
                address[] memory assetAddresses,
                uint256[] memory amounts
            ) = abi.decode(proposal.data, (uint8[], address[], uint256[]));
            _executeWithdrawDonationFromLinesRequest(
                _organizationId,
                lineIds,
                assetAddresses,
                amounts
            );
        }

        if (
            proposal.transactionType ==
            OrganizationProposalType.ADD_ORG_EXTERNAL_DONATION_ADDRESS
        ) {
            OrgExternalDonationAddress memory externalDonationAddress = abi
                .decode(proposal.data, (OrgExternalDonationAddress));
            uint8 externalDonationAddressId = _incrementOrgExternalDonationAddressId(
                    _organizationId
                );

            _updateOrgExternalDonationAddress(
                _organizationId,
                externalDonationAddress,
                externalDonationAddressId
            );
        }

        if (
            proposal.transactionType ==
            OrganizationProposalType.UPDATE_ORG_EXTERNAL_DONATION_ADDRESS
        ) {
            (
                uint8 externalDonationAddressId,
                OrgExternalDonationAddress memory externalDonationAddress
            ) = abi.decode(proposal.data, (uint8, OrgExternalDonationAddress));
            _updateOrgExternalDonationAddress(
                _organizationId,
                externalDonationAddress,
                externalDonationAddressId
            );
        }

        if (proposal.transactionType == OrganizationProposalType.ADD_SIGNER) {
            (address newSigner, uint8 newQuorum) = abi.decode(
                proposal.data,
                (address, uint8)
            );

            Organization storage organization = organizations[_organizationId];

            _executeAddSignerRequest(
                organization,
                _organizationId,
                newSigner,
                newQuorum
            );
        }

        if (
            proposal.transactionType == OrganizationProposalType.REMOVE_SIGNER
        ) {
            (uint8 signerId, uint8 newQuorum) = abi.decode(
                proposal.data,
                (uint8, uint8)
            );

            Organization storage organization = organizations[_organizationId];

            _executeRemoveSignerRequest(
                organization,
                _organizationId,
                signerId,
                newQuorum
            );
        }

        if (
            proposal.transactionType == OrganizationProposalType.UPDATE_QUORUM
        ) {
            uint8 newQuorum = abi.decode(proposal.data, (uint8));
            _updateQuorum(_organizationId, newQuorum);
        }

        if (
            proposal.transactionType ==
            OrganizationProposalType.UPDATE_ORG_SECURE_MESSAGING_PUB_KEY
        ) {
            (uint16 organizationId, string memory secureMessagingPubKey) = abi
                .decode(proposal.data, (uint16, string));
            _updateSecureMessagingPubKey(organizationId, secureMessagingPubKey);
        }

        if (
            proposal.transactionType == OrganizationProposalType.DEACTIVATE_LINE
        ) {
            uint8 _lineId = abi.decode(proposal.data, (uint8));
            _deactivateLine(_organizationId, _lineId);
        }

        if (
            proposal.transactionType == OrganizationProposalType.DEACTIVATE_ORG
        ) {
            (address[] memory assetAddresses, OrgDeactivators deactivator) = abi
                .decode(proposal.data, (address[], OrgDeactivators));
            _executeDeactivatedOrganizationRequest(
                _organizationId,
                assetAddresses,
                deactivator
            );
        }

        _afterProposalExecution(proposal);
    }

    function _afterProposalExecution(
        OrgMultiApproveTransaction storage proposal
    ) internal {
        proposal.isExecuted = true;
    }

    function _transferMainToken(address payable _to, uint256 _amount) internal {
        if (_amount > 0) {
            _to.transfer(_amount);
        }
    }

    function _transferToken(
        address _assetAddress,
        address _to,
        uint256 _amount
    ) internal nonReentrant {
        if (_amount > 0) {
            SafeTransferLib.safeTransfer(_assetAddress, _to, _amount);
        }
    }

    function _transferNFT(
        address _assetAddress,
        address _to,
        uint256 _tokenId
    ) internal nonReentrant {
        (bool ok, ) = _assetAddress.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                address(this),
                _to,
                _tokenId
            )
        );
        require(ok, "transfer NFT failed");
    }

    // EIP712
    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "DDL";
        version = "1";
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
