// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract UserRegistry {
    struct UserInfo {
        string name;
        string dob;
        string email;
    }

    mapping(address => UserInfo) private registeredUsers;

    event UserRegistered(address indexed user, string name, string dob, string email);
    event UserInfoUpdated(address indexed user, string name, string dob, string email);
    event UserDeleted(address indexed user);

    modifier onlyRegisteredUser(address userAddress) {
        require(bytes(registeredUsers[userAddress].dob).length > 0, "User not registered");
        _;
    }

    function register(address userAddress, string memory name, string memory dob, string memory email) external {
        require(bytes(name).length > 0, "Name is required");
        require(bytes(dob).length > 0, "DOB is required");
        require(bytes(email).length > 0, "Email is required");
        require(bytes(registeredUsers[userAddress].dob).length == 0, "User already registered");

        registeredUsers[userAddress] = UserInfo(name, dob, email);
        emit UserRegistered(userAddress, name, dob, email);
    }

    function isRegistered(address userAddress) external view returns (bool) {
        return bytes(registeredUsers[userAddress].dob).length > 0;
    }

    function getUserInfo(address userAddress) external view returns (string memory name, string memory dob, string memory email) {
        UserInfo storage userInfo = registeredUsers[userAddress];
        return (userInfo.name, userInfo.dob, userInfo.email);
    }

    function updateUserInfo(string memory newName, string memory newDob, string memory newEmail) external onlyRegisteredUser(msg.sender) {
        require(bytes(newName).length > 0, "Name is required");
        require(bytes(newDob).length > 0, "DOB is required");
        require(bytes(newEmail).length > 0, "Email is required");

        UserInfo storage userInfo = registeredUsers[msg.sender];
        userInfo.name = newName;
        userInfo.dob = newDob;
        userInfo.email = newEmail;

        emit UserInfoUpdated(msg.sender, newName, newDob, newEmail);
    }

    function deleteUser() external onlyRegisteredUser(msg.sender) {
        delete registeredUsers[msg.sender];
        emit UserDeleted(msg.sender);
    }
}

contract Chama {
    struct Member {
        uint256 memberId;
        address memberAddress;
        uint256 contribution;
        uint256 shares;
        bool active;
    }

     struct ChamaData {
        address chamaOwner;
        string chamaName;
        string chamaDescription;
        uint256 minContributionAmount;
        uint256 maxContributionAmount;
        uint256 contributionCycleDuration;
        uint256 lastContributionCycleStart;
        uint256 totalContributions;
        uint256 totalShares;
        uint256 nextMemberId;
        mapping(uint256 => Member) members;
        mapping(address => bool) isMember;
        mapping(uint256 => mapping(uint256 => bool)) votes;
    }

    address public treasurer;
    AggregatorV3Interface internal priceFeed;
    mapping(uint256 => ChamaData) public chamas;
    uint256 public nextChamaId;
    UserRegistry private userRegistry;

    event ChamaCreated(
        uint256 indexed chamaId,
        address indexed chamaOwner,
        string chamaName,
        string chamaDescription,
        uint256 minContributionAmount,
        uint256 maxContributionAmount,
        uint256 contributionCycleDuration
    );

    event MemberAdded(
        uint256 indexed chamaId,
        uint256 indexed memberId,
        address indexed memberAddress,
        uint256 contribution,
        uint256 shares
    );

    event ContributionMade(uint256 indexed chamaId, address indexed memberAddress, uint256 contribution);
    event ShareDistribution(uint256 indexed chamaId, uint256 indexed memberId, uint256 shares);
    event VoteCasted(uint256 indexed chamaId, uint256 indexed memberId, uint256 proposalId);
    event ChamaUpdated(
        uint256 indexed chamaId,
        uint256 minContributionAmount,
        uint256 maxContributionAmount,
        uint256 contributionCycleDuration
    );

    modifier onlyTreasurer() {
        require(msg.sender == treasurer, "Only the treasurer can perform this action");
        _;
    }

    modifier onlyChamaOwner(uint256 _chamaId) {
        require(chamas[_chamaId].chamaOwner == msg.sender, "Only the chama owner can perform this action");
        _;
    }

    modifier onlyMember(uint256 _chamaId, uint256 _memberId) {
        require(
            chamas[_chamaId].members[_memberId].memberAddress == msg.sender ||
            chamas[_chamaId].chamaOwner == msg.sender,
            "Only the member or chama owner can perform this action"
        );
        _;
    }

    constructor(address _treasurer, address _priceFeed, address _userRegistry) {
        treasurer = _treasurer;
        priceFeed = AggregatorV3Interface(_priceFeed);
        userRegistry = UserRegistry(_userRegistry);
        nextChamaId = 1;
    }

    function initializeChamaData(
        uint256 _chamaId,
        address _chamaOwner,
        string memory _chamaName,
        string memory _chamaDescription,
        uint256 _minContributionAmount,
        uint256 _maxContributionAmount,
        uint256 _contributionCycleDuration
    ) private {
        ChamaData storage chama = chamas[_chamaId];
        chama.chamaOwner = _chamaOwner;
        chama.chamaName = _chamaName;
        chama.chamaDescription = _chamaDescription;
        chama.minContributionAmount = _minContributionAmount;
        chama.maxContributionAmount = _maxContributionAmount;
        chama.contributionCycleDuration = _contributionCycleDuration;
        chama.lastContributionCycleStart = block.timestamp;
    }

    function createChama(
        uint256 _minContributionAmount,
        uint256 _maxContributionAmount,
        uint256 _contributionCycleDuration,
        address _chamaOwner,
        string memory _chamaName,
        string memory _chamaDescription
    ) external {
        require(_minContributionAmount > 0, "Minimum contribution amount must be greater than zero");
        require(_maxContributionAmount >= _minContributionAmount, "Maximum contribution amount must be greater than or equal to minimum contribution amount");
        require(_contributionCycleDuration > 0, "Contribution cycle duration must be greater than zero");
        require(userRegistry.isRegistered(_chamaOwner), "Chama owner is not registered");
        require(_chamaOwner != address(0), "Chama owner address is required");
        require(bytes(_chamaName).length > 0, "Chama name is required");
        require(bytes(_chamaDescription).length > 0, "Chama description is required");

        uint256 chamaId = nextChamaId;
        initializeChamaData(chamaId, _chamaOwner, _chamaName, _chamaDescription, _minContributionAmount, _maxContributionAmount, _contributionCycleDuration);

        emit ChamaCreated(chamaId, _chamaOwner, _chamaName, _chamaDescription, _minContributionAmount, _maxContributionAmount, _contributionCycleDuration);
        nextChamaId++;
    }

    function joinChama(uint256 _chamaId) external payable {
        require(_chamaId < nextChamaId, "Invalid chama ID");
        require(chamas[_chamaId].chamaOwner != address(0), "Chama does not exist");
        require(!chamas[_chamaId].isMember[msg.sender], "Already a member");
        require(userRegistry.isRegistered(msg.sender), "User is not registered");

        ChamaData storage chama = chamas[_chamaId];
        require(msg.sender != chama.chamaOwner, "Chama owner cannot join as a member");

        // Calculate shares based on user's contribution compared to total contribution/chama worth
        uint256 userContribution = msg.value;
        uint256 totalContribution = chama.totalContributions + userContribution;
        uint256 totalShares = chama.totalShares;
        uint256 userShares = totalContribution > 0 ? (userContribution * totalShares) / totalContribution : 0;

        chama.members[chama.nextMemberId] = Member(chama.nextMemberId, msg.sender, userContribution, userShares, true);
        chama.isMember[msg.sender] = true;
        chama.totalContributions += userContribution;
        chama.totalShares += userShares;

        emit MemberAdded(_chamaId, chama.nextMemberId, msg.sender, userContribution, userShares);

        chama.nextMemberId++;
    }

    function makeContribution(uint256 _chamaId) external payable {
        require(_chamaId < nextChamaId, "Invalid chama ID");
        require(chamas[_chamaId].isMember[msg.sender], "Not a member");
        require(msg.value >= chamas[_chamaId].minContributionAmount, "Contribution amount too low");
        require(msg.value <= chamas[_chamaId].maxContributionAmount, "Contribution amount too high");
        require(isContributionCycleActive(_chamaId), "Contribution cycle is not active");

        ChamaData storage chama = chamas[_chamaId];
        Member storage member = chama.members[getMemberId(_chamaId, msg.sender)];

        member.contribution += msg.value;
        chama.totalContributions += msg.value;

        emit ContributionMade(_chamaId, msg.sender, msg.value);
    }

    function distributeShares(uint256 _chamaId, uint256 _memberId, uint256 _shares) external onlyTreasurer {
        require(_chamaId < nextChamaId, "Invalid chama ID");
        require(chamas[_chamaId].members[_memberId].active, "Member not found");

        ChamaData storage chama = chamas[_chamaId];
        Member storage member = chama.members[_memberId];

        member.shares += _shares;
        chama.totalShares += _shares;

        emit ShareDistribution(_chamaId, _memberId, _shares);
    }

    function proposeVote(uint256 _chamaId, uint256 _memberId, uint256 _proposalId) external onlyTreasurer {
        require(_chamaId < nextChamaId, "Invalid chama ID");
        require(chamas[_chamaId].members[_memberId].active, "Member not found");

        ChamaData storage chama = chamas[_chamaId];
        chama.votes[_memberId][_proposalId] = true;

        emit VoteCasted(_chamaId, _memberId, _proposalId);
    }

    function updateChama(
        uint256 _chamaId,
        uint256 _minContributionAmount,
        uint256 _maxContributionAmount,
        uint256 _contributionCycleDuration
    ) external onlyChamaOwner(_chamaId) {
        require(_chamaId < nextChamaId, "Invalid chama ID");
        require(_minContributionAmount > 0, "Minimum contribution amount must be greater than zero");
        require(_maxContributionAmount >= _minContributionAmount, "Maximum contribution amount must be greater than or equal to minimum contribution amount");
        require(_contributionCycleDuration > 0, "Contribution cycle duration must be greater than zero");

        ChamaData storage chama = chamas[_chamaId];
        chama.minContributionAmount = _minContributionAmount;
        chama.maxContributionAmount = _maxContributionAmount;
        chama.contributionCycleDuration = _contributionCycleDuration;

        emit ChamaUpdated(_chamaId, _minContributionAmount, _maxContributionAmount, _contributionCycleDuration);
    }

    function deleteChama(uint256 _chamaId) external onlyChamaOwner(_chamaId) {
        require(_chamaId < nextChamaId, "Invalid chama ID");

        // Perform any necessary cleanup or transfer remaining funds before deleting the chama

        delete chamas[_chamaId];
    }

    function getMemberId(uint256 _chamaId, address _memberAddress) public view returns (uint256) {
        ChamaData storage chama = chamas[_chamaId];
    
        if (_memberAddress == chama.chamaOwner) {
            return chama.nextMemberId;  // Return chama owner ID
        }
    
        for (uint256 i = 1; i < chama.nextMemberId; i++) {
            if (chama.members[i].memberAddress == _memberAddress) {
                return i;
            }
        }
    
        revert("Member not found");
    }

    function isContributionCycleActive(uint256 _chamaId) public view returns (bool) {
        ChamaData storage chama = chamas[_chamaId];
        return block.timestamp >= chama.lastContributionCycleStart && block.timestamp < chama.lastContributionCycleStart + chama.contributionCycleDuration;
    }

    function startNextContributionCycle(uint256 _chamaId) external onlyChamaOwner(_chamaId) {
        require(_chamaId < nextChamaId, "Invalid chama ID");

        ChamaData storage chama = chamas[_chamaId];
        require(!isContributionCycleActive(_chamaId), "Contribution cycle is already active");

        chama.lastContributionCycleStart = block.timestamp;
    }

    function getChamaDetails(uint256 _chamaId)
        public
        view
        returns (
            uint256 chamaId,
            address chamaOwner,
            string memory chamaName,
            string memory chamaDescription,
            uint256 minContributionAmount,
            uint256 maxContributionAmount,
            uint256 contributionCycleDuration
        )
    {
        require(_chamaId < nextChamaId, "Invalid chama ID");

        ChamaData storage chama = chamas[_chamaId];

        return (
            _chamaId,
            chama.chamaOwner,
            chama.chamaName,
            chama.chamaDescription,
            chama.minContributionAmount,
            chama.maxContributionAmount,
            chama.contributionCycleDuration
        );
    }

    function getMemberDetails(uint256 _chamaId, uint256 _memberId)
        public
        view
        returns (
            uint256 memberId,
            address memberAddress,
            uint256 contribution,
            uint256 shares,
            bool active
        )
    {
        require(_chamaId < nextChamaId, "Invalid chama ID");

        ChamaData storage chama = chamas[_chamaId];
        Member storage member;

        if (_memberId == 0) {
            // Return chama owner as member
            require(msg.sender == chama.chamaOwner, "Only the chama owner can retrieve their details");
            member = chama.members[chama.nextMemberId];
        } else {
            // Return regular member
            member = chama.members[_memberId];
            require(member.memberAddress == msg.sender, "Only the member can retrieve their details");
        }

        (string memory name, string memory dob, string memory email) = userRegistry.getUserInfo(member.memberAddress);

        return (member.memberId, member.memberAddress, member.contribution, member.shares, member.active);
    }

    function getAllChamas() external view returns (uint256[] memory) {
        uint256[] memory chamaIds = new uint256[](nextChamaId - 1);
        for (uint256 i = 1; i < nextChamaId; i++) {
            chamaIds[i - 1] = i;
        }
        return chamaIds;
    }

    function getOwnedChamas(address _user) public view returns (uint256[] memory) {
        uint256[] memory ownedChamaIds = new uint256[](nextChamaId - 1);
        uint256 count = 0;

        for (uint256 i = 1; i < nextChamaId; i++) {
            if (chamas[i].chamaOwner == _user) {
                ownedChamaIds[count] = i;
                count++;
            }
        }

        // Resize the array to remove unused slots
        assembly {
            mstore(ownedChamaIds, count)
        }

        return ownedChamaIds;
    }

    function getJoinedChamas(address _user) public view returns (uint256[] memory) {
        uint256[] memory joinedChamaIds = new uint256[](nextChamaId - 1);
        uint256 count = 0;

        for (uint256 i = 1; i < nextChamaId; i++) {
            if (chamas[i].isMember[_user]) {
                joinedChamaIds[count] = i;
                count++;
            }
        }

        // Resize the array to remove unused slots
        assembly {
            mstore(joinedChamaIds, count)
        }

        return joinedChamaIds;
    }

}
