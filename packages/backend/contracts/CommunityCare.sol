pragma solidity ^0.8.14;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
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
        uint totalDonations;
        uint totalFundsInWei;
        uint totalSettlementsInWei;

    }

    struct Request {
        address requester;
        uint requestTime;
        string title;
        string description;
        uint requestAmountInWei;
        string supportingDocumentation;
        uint amountFundedInWei;
        bool hasBeenSettled;
    }

    struct Donation {
        uint donationId;
        uint donationTime;
        uint donationAmountInWei;
    }

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
    
    event PhaseStarted(uint indexed roundNumber, Phases indexed phase);
    event RequestSubmitted(address indexed requester, uint indexed requestAmountInWei);
    event DonationSubmitted(address indexed donator, uint indexed donationAmountInWei);
    event TokenRewardsGenerated(address indexed requester, uint indexed rewardAmountInWei);
    event TokenRewardsWithdrawn(address indexed requester, uint indexed rewardAmountInWei);
    event FundingAllocated(address[] indexed requesters, uint currentRoundNumber);
    event RequestSettled(address indexed requester, uint indexed requestAmountInWei);

    constructor(uint _requestPhaseDuration, uint _fundingPhaseDuration, uint _allocationPhaseDuration, uint _settlementPhaseDuration, address _rewardsToken) public {
        requestPhaseDuration = _requestPhaseDuration;
        fundingPhaseDuration = _fundingPhaseDuration;
        allocationPhaseDuration = _allocationPhaseDuration;
        settlementPhaseDuration = _settlementPhaseDuration;
        rewardsToken = CareToken(_rewardsToken);
    }

    //State machine modifiers
    modifier onlyPhase(Phases phase) {
        require(phase == rounds[rounds.length - 1].currentPhase, "Operation not allowed at this phase");
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

    function _nextPhase() internal {
        Round memory currentRound = rounds[rounds.length - 1];
        currentRound.currentPhase = Phases(uint(currentRound.currentPhase) + 1);
        emit PhaseStarted(rounds.length - 1, currentRound.currentPhase);
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
            0
        );
        rounds.push(newRound);
    }

    // Submit an aid request
    function submitAidRequest(string memory title, string memory description, uint requestAmountInWei, string memory supportingDocumentation) public checkTime onlyPhase(Phases.Request){
        require(requestAmountInWei > 0, "Request amount must be greater than zero");

        uint currentRoundNumber = rounds.length - 1;
        Request memory newRequest = Request(
            msg.sender,
            block.timestamp,
            title,
            description,
            requestAmountInWei,
            supportingDocumentation,
            0,
            false
        );

        requests[msg.sender][currentRoundNumber].push(newRequest);
        rounds[currentRoundNumber].totalRequests++;
        rounds[currentRoundNumber].totalFundsRequested += requestAmountInWei;
        requestToDonationRatios[msg.sender].numberRequests += 1e18;
        EnumerableSet.contains(requestors, msg.sender) ? false : donators.add(msg.sender);
    }

    // Donate to funding pool
    function donateToFundingPool() public payable checkTime onlyPhase(Phases.Funding) {
        require(msg.value > 0, "Donation amount must be greater than zero");

        uint currentRoundNumber = rounds.length - 1;
        uint donationId = donations[msg.sender][currentRoundNumber].length + 1;
        uint donationTime = block.timestamp;

        Donation memory newDonation = Donation(
            donationId,
            donationTime,
            msg.value
        );

        donations[msg.sender][currentRoundNumber].push(newDonation);
        rounds[currentRoundNumber].totalDonations++;
        rounds[currentRoundNumber].totalFundsInWei += msg.value;
        requestToDonationRatios[msg.sender].numberDonations += 1e18;
        EnumerableSet.contains(donators, msg.sender) ? false : donators.add(msg.sender);

        //Calculate rewards and add to reward balance
        uint tokenRewards = _calculateTokenRewards(msg.sender, msg.value);
        if (tokenRewards > 0) {
            rewardBalances[msg.sender] += tokenRewards;
            emit TokenRewardsGenerated(msg.sender, tokenRewards);
        }
        emit DonationSubmitted(msg.sender, msg.value);
        
    }

    //Simple algorithm for token rewards for now but can be replaced in the future
    function _calculateTokenRewards(address donator, uint donationAmount) internal view returns (uint tokenRewards) {
        uint totalRewards;
        RTDRatio memory rtdRatio = requestToDonationRatios[donator];
        uint ratioUint = rtdRatio.numberRequests / rtdRatio.numberDonations;
        ratioUint > 1e18 ? totalRewards = (donationAmount * ratioUint) / 1000 : totalRewards = 0;
        return totalRewards;
    }

    function allocateFundingPool() public checkTime onlyPhase(Phases.Allocation) {
        require(rounds[rounds.length - 1].totalFundsInWei > 0, "No funding to allocate");

        address[] memory requestorsArray = EnumerableSet.values(requestors);
        uint currentRoundNumber = rounds.length - 1;
        _allocateFunding(requestorsArray, currentRoundNumber);
        
        emit FundingAllocated(requestorsArray, currentRoundNumber);
        }

    //Simple algorithm for funding for now but can be replaced in the future
    function _allocateFunding(address[] memory _requestorsArray, uint _currentRoundNumber) internal {
        for (uint i = 0; i < _requestorsArray.length; i++) {
            Request[] storage requestsArray = requests[_requestorsArray[i]][rounds.length - 1];
            for (uint j = 0; j < requestsArray.length; j++ ){
                if (rounds[_currentRoundNumber].totalFundsInWei >= rounds[_currentRoundNumber].totalFundsRequested) {
                    requestsArray[j].amountFundedInWei = requestsArray[j].requestAmountInWei;
                } else {
                    requestsArray[j].amountFundedInWei = rounds[_currentRoundNumber].totalFundsInWei / rounds[_currentRoundNumber].totalRequests;
                }
            }
        }
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


    // Getter functions
    function getCurrentRoundNumber() public view returns (uint) {
        return rounds.length - 1;
    }

    function getCurrentRound() public view returns (Round memory) {
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

    function getRequest(address requester, uint requestId) public view returns (Request memory) {
        return requests[requester][rounds.length - 1][requestId];
    }

    function getDonation(address requester, uint requestId, uint donationId) public view returns (Donation memory) {
        return donations[requester][rounds.length - 1][donationId];
    }

    function getRequestToDonationRatio(address requester) public view returns (uint) {
        return requestToDonationRatios[requester].numberRequests / requestToDonationRatios[requester].numberDonations;
    }

    function getRewardsBalance (address requester) public view returns (uint) {
        return rewardBalances[requester];
    }
}
