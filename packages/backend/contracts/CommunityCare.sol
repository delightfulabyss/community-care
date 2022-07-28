// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './ERC20.sol';

contract CommunityCare is Ownable {
    /***************************************************************************
     ************************** State Variables ********************************
     ***************************************************************************/
    uint256 public something;
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
        uint256 startTime;
        uint256 totalRequests;
        Phases currentPhase;
        uint256 totalFundsRequested;
        uint256 totalDonationsToCommonPool;
        uint256 totalDonationsToRequests;
        uint256 totalFundsDonatedInWei;
        uint256 totalSettlementsInWei;
    }

    struct Request {
        string requestId;
        address requester;
        uint256 requestTime;
        string title;
        string description;
        uint256 requestAmountInWei;
        string supportingDocumentation;
        uint256 numberOfDonations;
        uint256 amountFundedInWei;
        bool hasBeenSettled;
    }

    struct Donation {
        address donator;
        uint256 donationTime;
        uint256 donationAmountInWei;
        string requestId;
    }
    //Long integers to allow for ratios below 1
    struct RTDRatio {
        uint256 numberRequests;
        uint256 numberDonations;
    }

    mapping(address => mapping(uint256 => Request[])) requests;
    EnumerableSet.AddressSet private requestors;
    mapping(address => mapping(uint256 => Donation[])) donations;
    EnumerableSet.AddressSet private donators;
    mapping(address => RTDRatio) public requestToDonationRatios;
    mapping(address => uint256) public rewardBalances;
    Round[] public rounds;
    CareToken internal rewardsToken;

    /***************************************************************************
     ************************** Events *****************************************
     ***************************************************************************/

    event PhaseStarted(uint256 indexed roundNumber, Phases indexed phase);
    event RequestCreated(
        address indexed requester,
        uint256 indexed requestAmountInWei
    );
    event DonationToCommonPoolCreated(
        address indexed donator,
        uint256 indexed donationAmountInWei
    );
    event DonationToRequestCreated(
        address indexed donator,
        uint256 indexed donationAmountInWei,
        string indexed requestTitle
    );
    event TokenRewardsGenerated(
        address indexed requester,
        uint256 indexed rewardAmountInWei
    );
    event TokenRewardsClaimed(
        address indexed requester,
        uint256 indexed rewardAmountInWei
    );
    event CommonPoolAllocated(
        address[] indexed requesters,
        uint256 currentRoundNumber
    );
    event RequestSettled(
        address indexed requester,
        uint256 indexed requestAmountInWei
    );

    constructor(
        uint256 _requestPhaseDuration,
        uint256 _fundingPhaseDuration,
        uint256 _allocationPhaseDuration,
        uint256 _settlementPhaseDuration,
        address _rewardsToken
    ) {
        requestPhaseDuration = _requestPhaseDuration;
        fundingPhaseDuration = _fundingPhaseDuration;
        allocationPhaseDuration = _allocationPhaseDuration;
        settlementPhaseDuration = _settlementPhaseDuration;
        rewardsToken = CareToken(_rewardsToken);
    }

    /***************************************************************************
     ************************** Modifiers **************************************
     ***************************************************************************/

    modifier onlyPhase(Phases phase) {
        require(
            phase == rounds[rounds.length - 1].currentPhase,
            'Operation not allowed during this phase'
        );
        _;
    }

    /***************************************************************************
     ************************** Public Functions *******************************
     ***************************************************************************/

    /**
     * @notice Creates a new request.
     * @param _title The title of the request.
     * @param _description The description of the request.
     * @param _requestAmountInWei The amount requested in wei.
     * @param _supportingDocumentation Optional link to the supporting documentation of the request uploaded to IPFS/Filecoin
     */
    function createRequest(
        string memory _title,
        string memory _description,
        uint256 _requestAmountInWei,
        string memory _supportingDocumentation
    ) public onlyPhase(Phases.Request) {
        require(
            _requestAmountInWei > 0,
            'Request amount must be greater than zero'
        );

        _checkTime();
        uint256 currentRoundNumber = rounds.length - 1;
        Request memory newRequest = Request(
            string.concat(
                Strings.toHexString(uint160(msg.sender)),
                '-',
                Strings.toString(block.timestamp)
            ),
            msg.sender,
            block.timestamp,
            _title,
            _description,
            _requestAmountInWei,
            _supportingDocumentation,
            0,
            0,
            false
        );

        requests[msg.sender][currentRoundNumber].push(newRequest);
        rounds[currentRoundNumber].totalRequests++;
        rounds[currentRoundNumber].totalFundsRequested += _requestAmountInWei;
        requestToDonationRatios[msg.sender].numberRequests += 1e18;
        EnumerableSet.contains(requestors, msg.sender)
            ? false
            : donators.add(msg.sender);
        emit RequestCreated(msg.sender, _requestAmountInWei);
    }

    /**
     * @notice Creates a new donation.
     * @dev This function calls the internal _donate function.
     * @param _requestId The id of the request to donate to. If empty, the donation is made to the common funding pool.
     */
    function donate(string memory _requestId)
        public
        payable
        onlyPhase(Phases.Funding)
    {
        require(msg.value > 0, 'Donation amount must be greater than zero');
        _checkTime();
        _donate(msg.sender, msg.value, _requestId);
        emit DonationToRequestCreated(msg.sender, msg.value, _requestId);
    }

    function donate() public payable onlyPhase(Phases.Funding) {
        require(msg.value > 0, 'Donation amount must be greater than zero');
        _checkTime();
        _donate(msg.sender, msg.value, '');
        emit DonationToCommonPoolCreated(msg.sender, msg.value);
    }

    /**
     * @notice Settles all requests for the given user.
     */
    function settleRequests() public onlyPhase(Phases.Settlement) {
        require(
            requests[msg.sender][rounds.length - 1].length > 0,
            'No requests to settle'
        );

        _checkTime();
        uint256 currentRoundNumber = rounds.length - 1;
        uint256 totalSettlementAmount;

        for (
            uint256 i = 0;
            i < requests[msg.sender][currentRoundNumber].length;
            i++
        ) {
            Request memory request = requests[msg.sender][currentRoundNumber][
                i
            ];
            if (request.amountFundedInWei >= 0 && !request.hasBeenSettled) {
                requests[msg.sender][currentRoundNumber][i]
                    .hasBeenSettled = true;
                totalSettlementAmount += request.amountFundedInWei;
                emit RequestSettled(msg.sender, request.amountFundedInWei);
            }
            rounds[currentRoundNumber]
                .totalSettlementsInWei += totalSettlementAmount;
        }
        payable(address(this)).transfer(totalSettlementAmount);
    }

    /**
     * @notice Allows a user to claim their token rewards balance.
     */

    function claimTokenRewards() public {
        require(rewardBalances[msg.sender] > 0, 'No token rewards to claim');

        uint256 tokenRewards = rewardBalances[msg.sender];
        rewardsToken.mint(msg.sender, tokenRewards);
        rewardBalances[msg.sender] = 0;

        emit TokenRewardsClaimed(msg.sender, tokenRewards);
    }

    /***************************************************************************
     **************************  Owner Functions********************************
     ***************************************************************************/

    /**
     * @notice Allocates funds in the common pool to the current round's requesters.
     * @dev This function calls the internal _allocateCommonPool function.
     */
    function allocateCommonPool()
        public
        onlyPhase(Phases.Allocation)
        onlyOwner
    {
        _checkTime();
        address[] memory requestorsArray = EnumerableSet.values(requestors);
        uint256 currentRoundNumber = rounds.length - 1;
        _allocateCommonPool(requestorsArray, currentRoundNumber);
        emit CommonPoolAllocated(requestorsArray, currentRoundNumber);
    }

    /**
     * @notice Starts a new round
     */
    function startNewRound() public onlyOwner {
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

    /***************************************************************************
     **************************  Internal Functions ****************************
     ***************************************************************************/

    /**
     * @dev The algorithm weighs each request based on how many donations it has received. This algorithm can be improved / replaced by the community.
     */
    function _allocateCommonPool(
        address[] memory _requestorsArray,
        uint256 _currentRoundNumber
    ) internal {
        require(
            _requestorsArray.length > 0,
            'No requests to allocate funding to'
        );
        require(
            rounds[rounds.length - 1].totalDonationsToCommonPool > 0,
            'No funding to allocate'
        );
        for (uint256 i = 0; i < _requestorsArray.length; i++) {
            address requester = _requestorsArray[i];
            Request[] memory requestsCopy = requests[requester][
                _currentRoundNumber
            ];
            for (uint256 j = 0; j < requestsCopy.length; j++) {
                Request storage request = requests[requester][
                    _currentRoundNumber
                ][j];
                Round storage round = rounds[_currentRoundNumber];
                uint256 totalDonationsToRequest = request.numberOfDonations;
                uint256 totalDonationsInRound = round.totalDonationsToRequests +
                    round.totalDonationsToCommonPool;
                uint256 allocation = commonPoolBalanceInWei /
                    (totalDonationsToRequest / totalDonationsInRound);
                request.amountFundedInWei += allocation;
                commonPoolBalanceInWei -= allocation;
            }
        }
    }

    function _donate(
        address _donator,
        uint256 _donationAmount,
        string memory _requestId
    ) internal {
        uint256 currentRoundNumber = rounds.length - 1;
        uint256 donationTime = block.timestamp;

        Donation memory newDonation = Donation(
            _donator,
            donationTime,
            _donationAmount,
            _requestId
        );

        donations[_donator][currentRoundNumber].push(newDonation);

        //Check if donation is for a request or common pool and take actions accordingly
        if (bytes(_requestId).length > 0) {
            for (
                uint256 i = 0;
                i < requests[_donator][currentRoundNumber].length;
                i++
            ) {
                string memory requestId = requests[_donator][
                    currentRoundNumber
                ][i].requestId;
                if (
                    keccak256(abi.encodePacked(requestId)) ==
                    keccak256(abi.encodePacked(_requestId))
                ) {
                    requests[_donator][currentRoundNumber][i]
                        .amountFundedInWei += _donationAmount;
                    requests[_donator][currentRoundNumber][i]
                        .numberOfDonations++;
                    rounds[currentRoundNumber].totalDonationsToRequests++;
                }
            }
        } else {
            rounds[currentRoundNumber].totalDonationsToCommonPool++;
            commonPoolBalanceInWei += _donationAmount;
        }

        requestToDonationRatios[_donator].numberDonations += 1e18;
        EnumerableSet.contains(donators, _donator)
            ? false
            : donators.add(_donator);
        rounds[currentRoundNumber].totalFundsDonatedInWei += _donationAmount;

        //Calculate rewards and add to reward balance
        uint256 tokenRewards = _calculateTokenRewards(
            _donator,
            _donationAmount
        );
        if (tokenRewards > 0) {
            rewardBalances[_donator] += tokenRewards;
            emit TokenRewardsGenerated(_donator, tokenRewards);
        }
    }

    /**
     * @dev The algorithm generates token rewards by multiplying a donation's value by their request-to-donation ration. The resulting number is then multiplied by a 50x multiplyer. This algorithm can be improved / replaced by the community.
     */
    function _calculateTokenRewards(address donator, uint256 donationAmount)
        internal
        view
        returns (uint256 tokenRewards)
    {
        uint256 totalRewards;
        RTDRatio memory rtdRatio = requestToDonationRatios[donator];

        //Catch divide by zero error
        if (rtdRatio.numberDonations == 0) {
            return 0;
        }

        uint256 ratioUint = rtdRatio.numberRequests / rtdRatio.numberDonations;
        ratioUint > 1e18 ? donationAmount * ratioUint * 50e18 : 0;
        return totalRewards;
    }

    function _nextPhase() internal {
        Round memory currentRound = rounds[rounds.length - 1];
        currentRound.currentPhase = Phases(
            uint256(currentRound.currentPhase) + 1
        );
        emit PhaseStarted(rounds.length - 1, currentRound.currentPhase);
    }

    function _checkTime() internal {
        Round memory currentRound = rounds[rounds.length - 1];
        uint256 requestPhase = requestPhaseDuration;
        uint256 fundingPhase = fundingPhaseDuration;
        uint256 allocationPhase = allocationPhaseDuration;
        uint256 settlementPhase = settlementPhaseDuration;
        if (currentRound.currentPhase == Phases.Request) {
            if (
                block.timestamp >=
                currentRound.startTime + requestPhase + fundingPhase
            ) {
                _nextPhase();
            }
        } else if (currentRound.currentPhase == Phases.Funding) {
            if (
                block.timestamp >=
                currentRound.startTime +
                    requestPhase +
                    fundingPhase +
                    allocationPhase
            ) {
                _nextPhase();
            }
        } else if (currentRound.currentPhase == Phases.Allocation) {
            if (
                block.timestamp >=
                currentRound.startTime +
                    requestPhase +
                    fundingPhase +
                    allocationPhase +
                    settlementPhase
            ) {
                _nextPhase();
            }
        } else if (currentRound.currentPhase == Phases.Settlement) {
            if (
                block.timestamp >=
                currentRound.startTime +
                    requestPhase +
                    fundingPhase +
                    allocationPhase +
                    settlementPhase +
                    settlementPhaseDuration
            ) {
                _nextPhase();
            }
        }
    }
}
