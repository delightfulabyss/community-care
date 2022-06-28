// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ERC20.sol";

contract CommunityCare {

    using EnumerableSet for EnumerableSet.AddressSet;
    
    // The request period duration.
    uint256 public requestPhaseDuration;

    // The funding period duration.
    uint256 public fundingPhaseDuration;

    //The allocation period duration.
    uint256 public allocationPhaseDuration;

    // The settlement period duration.
    uint256 public settlementPhaseDuration;

    //Common funding pool
    uint256 internal commonPoolBalanceInWei;

    enum Phases {
        Request,
        Funding,
        Allocation,
        Settlement,
        Finished
    }

    struct Round {
        uint startTime;
        uint totalRequests;
        Phases currentPhase;
        uint totalFundsRequested;
        uint totalDonationsToCommonPool;
        uint totalDonationsToRequests;
        uint totalFundsInWei;
        uint totalSettlementsInWei;

    }

    struct Request {
        string requestId;
        address requester;
        uint requestTime;
        string title;
        string description;
        uint requestAmountInWei;
        string supportingDocumentation;
        uint numberOfDonations;
        uint amountFundedInWei;
        bool hasBeenSettled;
    }

    struct Donation {
        address donator;
        uint donationTime;
        uint donationAmountInWei;
        string requestId;
    }
    //Long integers to allow for ratios below 1
    struct RTDRatio {
        uint numberRequests;
        uint numberDonations;
    }

    mapping (address => mapping (uint => Request[])) requests;
    EnumerableSet.AddressSet private requestors;
    mapping (address => mapping (uint => Donation[])) donations;
    EnumerableSet.AddressSet private donators;
    mapping (address => RTDRatio) public requestToDonationRatios;
    mapping (address => uint) public rewardBalances;
    Round[] public rounds;
    CareToken internal rewardsToken;
    

    /***************************************************************************
     ************************** Events *****************************************
     ***************************************************************************/
    event PhaseStarted(uint indexed roundNumber, Phases indexed phase);
    event RequestCreated(address indexed requester, uint indexed requestAmountInWei);
    event DonationToCommonPoolCreated(address indexed donator, uint indexed donationAmountInWei);
    event DonationToRequestCreated(address indexed donator, uint indexed donationAmountInWei, string indexed requestTitle);
    event TokenRewardsGenerated(address indexed requester, uint indexed rewardAmountInWei);
    event TokenRewardsWithdrawn(address indexed requester, uint indexed rewardAmountInWei);
    event FundingAllocated(address[] indexed requesters, uint currentRoundNumber);
    event RequestSettled(address indexed requester, uint indexed requestAmountInWei);

    constructor(uint _requestPhaseDuration, uint _fundingPhaseDuration, uint _allocationPhaseDuration, uint _settlementPhaseDuration, address _rewardsToken){
        requestPhaseDuration = _requestPhaseDuration;
        fundingPhaseDuration = _fundingPhaseDuration;
        allocationPhaseDuration = _allocationPhaseDuration;
        settlementPhaseDuration = _settlementPhaseDuration;
        rewardsToken = CareToken(_rewardsToken);
    }

    /***************************************************************************
     ************************** State Machine Modifiers ************************
     ***************************************************************************/

    modifier onlyPhase(Phases phase) {
        require(phase == rounds[rounds.length - 1].currentPhase, "Operation not allowed during this phase");
        _;
    }

    modifier checkTime(){
        Round memory currentRound = rounds[rounds.length - 1];
        if(currentRound.currentPhase == Phases.Request && block.timestamp >= currentRound.startTime + requestPhaseDuration) {
            _nextPhase();
        }else if (currentRound.currentPhase == Phases.Funding && block.timestamp >= currentRound.startTime + requestPhaseDuration + fundingPhaseDuration) {
            _nextPhase();
        }else if (currentRound.currentPhase == Phases.Allocation && block.timestamp >= currentRound.startTime + requestPhaseDuration + fundingPhaseDuration + allocationPhaseDuration) {
            _nextPhase();
        }else if (currentRound.currentPhase == Phases.Settlement && block.timestamp >= currentRound.startTime + requestPhaseDuration + fundingPhaseDuration + allocationPhaseDuration + settlementPhaseDuration) {
            _nextPhase();
        }
        _;
    }


    // Start new round
    function startNewRound() public {

        Round memory newRound = Round(
            block.timestamp,
            0,
            Phases.Request,
            0,
            0,
            0,
            0,
            0
        );
        rounds.push(newRound);
    }

    // Submit an aid request
    function createRequest(string memory title, string memory description, uint requestAmountInWei, string memory supportingDocumentation) public checkTime onlyPhase(Phases.Request){
        require(requestAmountInWei > 0, "Request amount must be greater than zero");

        uint currentRoundNumber = rounds.length - 1;
        Request memory newRequest = Request(
            string.concat(Strings.toHexString(uint160(msg.sender)), "-", Strings.toString(block.timestamp)),
            msg.sender,
            block.timestamp,
            title,
            description,
            requestAmountInWei,
            supportingDocumentation,
            0,
            0,
            false
        );

        requests[msg.sender][currentRoundNumber].push(newRequest);
        rounds[currentRoundNumber].totalRequests++;
        rounds[currentRoundNumber].totalFundsRequested += requestAmountInWei;
        requestToDonationRatios[msg.sender].numberRequests += 1e18; 
        EnumerableSet.contains(requestors, msg.sender) ? false : donators.add(msg.sender);
        emit RequestCreated(msg.sender, requestAmountInWei);
    }

    function donate(string memory _requestId) public payable checkTime onlyPhase(Phases.Funding) {
        require(msg.value > 0, "Donation amount must be greater than zero");
        _donate(msg.sender, msg.value, _requestId);
        emit DonationToRequestCreated(msg.sender, msg.value, _requestId);
    }

    function donate() public payable checkTime onlyPhase(Phases.Funding){
        require(msg.value > 0, "Donation amount must be greater than zero");
        _donate(msg.sender, msg.value, "");
        emit DonationToCommonPoolCreated(msg.sender, msg.value);
    }

    function allocateFundingPool() public checkTime onlyPhase(Phases.Allocation) {
        address[] memory requestorsArray = EnumerableSet.values(requestors);
        uint currentRoundNumber = rounds.length - 1;
        _allocateFunding(requestorsArray, currentRoundNumber);
        emit FundingAllocated(requestorsArray, currentRoundNumber);
    }

    function settleRequests() public checkTime onlyPhase(Phases.Settlement){
        require(requests[msg.sender][rounds.length - 1].length > 0, "No requests to settle");

        uint currentRoundNumber = rounds.length - 1;
        uint totalSettlementAmount;

        for (uint i = 0; i < requests[msg.sender][currentRoundNumber].length; i++) {
            Request memory request = requests[msg.sender][currentRoundNumber][i];
            if (request.amountFundedInWei >= 0 && !request.hasBeenSettled) {
                requests[msg.sender][currentRoundNumber][i].hasBeenSettled = true;
                totalSettlementAmount += request.amountFundedInWei;
                emit RequestSettled(msg.sender, request.amountFundedInWei);
            }
        payable(address(this)).transfer(totalSettlementAmount);
        }
    }

    function withdrawTokenRewards () public {
        require(rewardBalances[msg.sender] > 0, "No token rewards to claim");

        uint tokenRewards = rewardBalances[msg.sender];
        rewardsToken.mint(msg.sender, tokenRewards);
        rewardBalances[msg.sender] = 0;

        emit TokenRewardsWithdrawn(msg.sender, tokenRewards);
    }


    /***************************************************************************
     **************************  Getter Functions ******************************
     ***************************************************************************/

    function getCurrentRoundNumber() public view returns (uint) {
        return rounds.length - 1;
    }

    function getCurrentRoundData() public view returns (Round memory) {
        return rounds[rounds.length - 1];
    }

    function getCurrentRoundStartTime() public view returns (uint) {
        return rounds[rounds.length - 1].startTime;
    }

    function getCurrentRoundTotalRequests() public view returns (uint) {
        return rounds[rounds.length - 1].totalRequests;
    }

    function getCurrentRoundTotalFundsInWei() public view returns (uint) {
        return rounds[rounds.length - 1].totalFundsInWei;
    }

    function getCurrentRoundTotalSettlementsInWei() public view returns (uint) {
        return rounds[rounds.length - 1].totalSettlementsInWei;
    }

    function getRequest(address requester, uint requestNumber) public view returns (Request memory) {
        return requests[requester][rounds.length - 1][requestNumber];
    }

    function getDonation(address requester, uint donationNumber) public view returns (Donation memory) {
        return donations[requester][rounds.length - 1][donationNumber];
    }

    function getRequestToDonationRatio(address requester) public view returns (uint numberRequests, uint numberDonations) {
        return (requestToDonationRatios[requester].numberRequests, requestToDonationRatios[requester].numberDonations);
    }

    function getRewardsBalance (address requester) public view returns (uint) {
        return rewardBalances[requester];
    }

    function getCommonPoolBalance () public view returns (uint) {
        return commonPoolBalanceInWei;
    }

    /***************************************************************************
     **************************  Internal Functions ****************************
     ***************************************************************************/

    //Simple algorithm for funding for now but can be replaced in the future
    function _allocateFunding(address[] memory _requestorsArray, uint _currentRoundNumber) internal {
        require(_requestorsArray.length > 0, "No requests to allocate funding to");
        require(rounds[rounds.length - 1].totalDonationsToCommonPool > 0, "No funding to allocate");
        for (uint i = 0; i < _requestorsArray.length; i++) {
            address requester = _requestorsArray[i];
            Round memory round = rounds[_currentRoundNumber];
            for(uint j = 0; j < requests[requester][_currentRoundNumber].length; j++) {
                Request storage request = requests[requester][_currentRoundNumber][j];
                uint256 commonPoolBalanceCopy = commonPoolBalanceInWei;
                uint256 totalDonationsToRequest = request.numberOfDonations;
                uint256 totalDonationsInRound = round.totalDonationsToRequests + round.totalDonationsToCommonPool;
                uint256 allocation = commonPoolBalanceCopy / (totalDonationsToRequest / totalDonationsInRound);
                request.amountFundedInWei += allocation;
            }
        }

    }

    function _donate(address _donator, uint _donationAmount, string memory _requestId) internal {
        uint currentRoundNumber = rounds.length - 1;
        uint donationTime = block.timestamp;

        Donation memory newDonation = Donation(
            _donator,
            donationTime,
            _donationAmount,
            _requestId
        );

        donations[_donator][currentRoundNumber].push(newDonation);

        //Check if donation is for a request or common pool
        if (bytes(_requestId).length > 0) {
            for (uint i = 0; i < requests[_donator][currentRoundNumber].length; i++) {
                string memory requestId = requests[_donator][currentRoundNumber][i].requestId;
                if (keccak256(abi.encodePacked(requestId)) == keccak256(abi.encodePacked(_requestId))) {
                    requests[_donator][currentRoundNumber][i].amountFundedInWei += _donationAmount;
                    requests[_donator][currentRoundNumber][i].numberOfDonations++;
                    rounds[currentRoundNumber].totalDonationsToRequests++;
                }
            }
        } else {
            rounds[currentRoundNumber].totalDonationsToCommonPool++;
            commonPoolBalanceInWei += _donationAmount;
        }

        requestToDonationRatios[_donator].numberDonations += 1e18;
        EnumerableSet.contains(donators, _donator) ? false : donators.add(_donator);
        rounds[currentRoundNumber].totalFundsInWei += _donationAmount;

        //Calculate rewards and add to reward balance
        uint tokenRewards = _calculateTokenRewards(_donator, _donationAmount);
        if (tokenRewards > 0) {
            rewardBalances[_donator] += tokenRewards;
            emit TokenRewardsGenerated(_donator, tokenRewards);
        }

    }

    //Simple algorithm for token rewards for now but can be replaced in the future
    function _calculateTokenRewards(address donator, uint donationAmount) internal view returns (uint tokenRewards) {
        uint totalRewards;
        RTDRatio memory rtdRatio = requestToDonationRatios[donator];

        //Catch divide by zero error
        if (rtdRatio.numberDonations == 0) {
            return 0;
        }

        uint ratioUint = rtdRatio.numberRequests / rtdRatio.numberDonations;
        ratioUint > 1e18 ? donationAmount * ratioUint * 50e18 : 0;
        return totalRewards;
    }

    function _nextPhase() internal {
        Round memory currentRound = rounds[rounds.length - 1];
        currentRound.currentPhase = Phases(uint(currentRound.currentPhase) + 1);
        emit PhaseStarted(rounds.length - 1, currentRound.currentPhase);
    }
}
