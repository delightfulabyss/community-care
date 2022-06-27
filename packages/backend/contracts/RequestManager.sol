pragma solidity ^0.8.14;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RequestManager {

    using EnumerableSet for EnumerableSet.AddressSet;
    
    // The request period duration.
    uint256 public requestPhaseDuration = 7 days;

    // The funding period duration.
    uint256 public fundingPhaseDuration = 7 days;

    //The allocation period duration.
    uint256 public allocationPhaseDuration = 24 hours;

    // The settlement period duration.
    uint256 public settlementPhaseDuration = 7 days;

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
    Round[] public rounds;
    
    event PhaseStarted(uint indexed roundNumber, Phases indexed phase);
    event RequestSubmitted(address indexed requester, uint indexed requestAmountInWei);
    event FundingAllocated(address[] indexed requesters, uint currentRoundNumber);
    event RequestSettled(address indexed requester, uint indexed requestAmountInWei);

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
        uint startTime = block.timestamp;
        uint totalRequests = 0;
        uint totalFundsInWei = 0;
        uint totalSettlementsInWei = 0;

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
        requestToDonationRatios[msg.sender].numberRequests++;
        EnumerableSet.contains(requestors, msg.sender) ? 0 : donators.add(msg.sender);
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
        requestToDonationRatios[msg.sender].numberDonations++;
        EnumerableSet.AddressSet.contains(donators, msg.sender) ? 0 : donators.add(msg.sender);

        //Calculate rewards and save in rewards manager
    }

    function allocateFundingPool() public checkTime onlyPhase(Phases.Allocation) {
        address[] memory requestorsArray = EnumerableSet.AddressSet.values(requestors);
        uint currentRoundNumber = rounds.length - 1;
        _calculateFundingForRequests(requestorsArray, currentRoundNumber);
        emit FundingAllocated(requestorsArray, currentRoundNumber);
        }

    //Simple algorithm for funding for now but can be improved
    function _calculateFundingForRequests(address[] memory _requestorsArray, uint _currentRoundNumber) internal {
        for (uint i = 0; i < _requestorsArray; i++) {
            Request[] memory requestsArray = requests[_requestorsArray[i]][rounds.length - 1];
            for (uint j = 0; j < requestsArray; j++ ){
                if (rounds[_currentRoundNumber].totalFundsDonated >= rounds[_currentRoundNumber].totalFundsRequested) {
                    requestsArray[j].amountFundedInWei = requestsArray[j].requestAmountInWei;
                } else {
                    requestsArray[j].amountFundedInWei = rounds[_currentRoundNumber].totalFundsDonated / rounds[_currentRoundNumber].totalRequests;
                }
            }
        }
    }
    function settleRequests() public view checkTime onlyPhase(Phases.Settlement){
        require(requests[msg.sender][rounds.length - 1].length > 0, "No requests to settle");
        uint currentRoundNumber = rounds.length - 1;
        uint totalSettlementAmount;
        for (uint i = 0; i < requests[msg.sender][currentRoundNumber]; i++) {
            Request memory request = requests[msg.sender][currentRoundNumber][i];
            if (request.amountFundedInWei >= 0 && !request.hasBeenSettled) {
                requests[msg.sender][currentRoundNumber][i].hasBeenSettled = true;
                totalSettlementAmount += request.amountFundedInWei;
                emit RequestSettled(msg.sender, request.amountFundedInWei);
            }
        address(this).transfer(msg.sender, totalSettlementAmount);
        }
    }


    // Getter functions
    function getCurrentRoundNumber() public view returns (uint) {
        return rounds.length - 1;
    }

    function getCurrentRound() public view returns (Round memory) {
        return rounds[rounds.length - 1];
    }

    function getCurrentRoundStartTime() public view returns (uint) {
        Round memory currentRound = rounds[rounds.length - 1];
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
}
