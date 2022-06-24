pragma solidity ^0.8.14;
contract RequestManager {
    
    
    // The current round.
    uint256 public currentRound;

    // The current round's start time.
    uint256 public currentRoundStartTime;

    // The request period duration.
    uint256 public requestPhaseDuration;

    // The funding period duration.
    uint256 public fundingPhaseDuration;

    // The settlement period duration.
    uint256 public settlementPhaseDuration;

    event AidRoundStarted(uint indexed currentRound, uint indexed startTime);
    event AidRoundEnded(uint indexed currentRound, uint indexed endTime);
    event RequestPhaseStarted(uint indexed currentRound, uint indexed startTime);
    event RequestPhaseEnded(uint indexed currentRound, uint indexed endTime);
    event FundingPhaseStarted(uint indexed currentRound, uint indexed startTime);
    event FundingPhaseEnded(uint indexed currentRound, uint indexed endTime);
    event SettlementPhaseStarted(uint indexed currentRound, uint indexed startTime);
    event SettlementPhaseEnded(uint indexed currentRound, uint indexed endTime);

     
    // The current round's state.
    enum RoundPhase {
        // The round is not started.
        NotStarted,
        // The round is in the request period.
        RequestPhase,
        // The round is in the funding period.
        FundingPhase,
        // The round is in the settlement period.
        SettlementPhase,
    }
    
    // The current round's state.
    RoundPhase storage roundPhase;

    // Start the round with the request period
    function startRequestPhase() external onlyOwner {
        require(roundPhase == RoundPhase.NotStarted, "The round has already started.");
        roundPhase = RoundPhase.RequestPhase;
        emit RequestPhaseStarted(currentRound, block.timestamp);
    }

    // Start the funding period
    function startFundingPhase() external onlyOwner {
        require(roundPhase == RoundPhase.RequestPhase, "The funding period has closed for this round");
        roundPhase = RoundPhase.FundingPhase;
        emit RequestPhaseEnded(currentRound, block.timestamp);
        emit FundingPhaseStarted(currentRound, block.timestamp);
    }

    // Start the settlement period
    function startSettlementPhase() external onlyOwner {
        require(roundPhase == RoundPhase.FundingPhase, "The settlement period has closed for this round");
        roundPhase = RoundPhase.SettlementPhase;
        emit FundingPhaseEnded(currentRound, block.timestamp);
        emit SettlementPhaseStarted(currentRound, block.timestamp);
    }

    // Finish the round
    function finishRound() external onlyOwner {
        require(roundPhase == RoundPhase.SettlementPhase, "The round has already finished");
        roundPhase = RoundPhase.NotStarted;
        emit SettlementPhaseEnded(currentRound, block.timestamp);
        emit AidRoundEnded(currentRound, block.timestamp);
    }

    // Start the next round
    function startNextRound() external onlyOwner {
        require(roundPhase == RoundPhase.Finished, "The previous round has not finished yet");
        currentRound++;
        currentRoundStartTime = block.timestamp;
        roundPhase = RoundPhase.RequestPhase;
        emit AidRoundStarted(currentRound, currentRoundStartTime);
        emit RequestPhaseStarted(currentRound, currentRoundStartTime);
    }

    //Get current round state
    function getCurrentRoundInfo() external view returns (uint256, RoundPhase, uint256, uint256, uint256) {
        //Return current round number,current round state, current period start time, current period end time, current time
        switch (roundPhase) {
            case RoundPhase.NotStarted:
                return (
                    currentRound,
                    roundPhase,
                    0, 
                    0,
                    0,
                    block.timestamp
                );
            case RoundPhase.RequestPhase:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime,
                    currentRoundStartTime + requestPhaseDuration,
                    block.timestamp
                );
            case RoundPhase.FundingPhase:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime + requestPhaseDuration,
                    currentRoundStartTime + requestPhaseDuration + fundingPhaseDuration,
                    block.timestamp
                );
            case RoundPhase.SettlementPhase:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime + requestPhaseDuration + fundingPhaseDuration,
                    currentRoundStartTime + requestPhaseDuration + fundingPhaseDuration + settlementPhaseDuration,
                    block.timestamp
                );

        }
    }

}