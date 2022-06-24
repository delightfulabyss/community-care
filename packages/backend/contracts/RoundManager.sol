pragma solidity ^0.8.14;
contract RoundManager {
    
    
    // The current round.
    uint256 public currentRound;

    // The current round's start time.
    uint256 public currentRoundStartTime;

    // The request period duration.
    uint256 public requestPeriodDuration;

    // The funding period duration.
    uint256 public fundingPeriodDuration;

    // The settlement period duration.
    uint256 public settlementPeriodDuration;

    event AidRoundStarted(uint indexed currentRound, uint indexed startTime);
    event AidRoundEnded(uint indexed currentRound, uint indexed endTime);
    event RequestPeriodStarted(uint indexed currentRound, uint indexed startTime);
    event RequestPeriodEnded(uint indexed currentRound, uint indexed endTime);
    event FundingPeriodStarted(uint indexed currentRound, uint indexed startTime);
    event FundingPeriodEnded(uint indexed currentRound, uint indexed endTime);
    event SettlementPeriodStarted(uint indexed currentRound, uint indexed startTime);
    event SettlementPeriodEnded(uint indexed currentRound, uint indexed endTime);

     
    // The current round's state.
    enum RoundPhase {
        // The round is not started.
        NotStarted,
        // The round is in the request period.
        RequestPeriod,
        // The round is in the funding period.
        FundingPeriod,
        // The round is in the settlement period.
        SettlementPeriod,
    }
    
    // The current round's state.
    RoundPhase storage roundPhase;

    // Start the round with the request period
    function startRequestPeriod() external onlyOwner {
        require(roundPhase == RoundPhase.NotStarted, "The round has already started.");
        roundPhase = RoundPhase.RequestPeriod;
        emit RequestPeriodStarted(currentRound, block.timestamp);
    }

    // Start the funding period
    function startFundingPeriod() external onlyOwner {
        require(roundPhase == RoundPhase.RequestPeriod, "The funding period has closed for this round");
        roundPhase = RoundPhase.FundingPeriod;
        emit RequestPeriodEnded(currentRound, block.timestamp);
        emit FundingPeriodStarted(currentRound, block.timestamp);
    }

    // Start the settlement period
    function startSettlementPeriod() external onlyOwner {
        require(roundPhase == RoundPhase.FundingPeriod, "The settlement period has closed for this round");
        roundPhase = RoundPhase.SettlementPeriod;
        emit FundingPeriodEnded(currentRound, block.timestamp);
        emit SettlementPeriodStarted(currentRound, block.timestamp);
    }

    // Finish the round
    function finishRound() external onlyOwner {
        require(roundPhase == RoundPhase.SettlementPeriod, "The round has already finished");
        roundPhase = RoundPhase.NotStarted;
        emit SettlementPeriodEnded(currentRound, block.timestamp);
        emit AidRoundEnded(currentRound, block.timestamp);
    }

    // Start the next round
    function startNextRound() external onlyOwner {
        require(roundPhase == RoundPhase.Finished, "The previous round has not finished yet");
        currentRound++;
        currentRoundStartTime = block.timestamp;
        roundPhase = RoundPhase.RequestPeriod;
        emit AidRoundStarted(currentRound, currentRoundStartTime);
        emit RequestPeriodStarted(currentRound, currentRoundStartTime);
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
            case RoundPhase.RequestPeriod:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime,
                    currentRoundStartTime + requestPeriodDuration,
                    block.timestamp
                );
            case RoundPhase.FundingPeriod:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime + requestPeriodDuration,
                    currentRoundStartTime + requestPeriodDuration + fundingPeriodDuration,
                    block.timestamp
                );
            case RoundPhase.SettlementPeriod:
                return (
                    currentRound,
                    roundPhase,
                    currentRoundStartTime + requestPeriodDuration + fundingPeriodDuration,
                    currentRoundStartTime + requestPeriodDuration + fundingPeriodDuration + settlementPeriodDuration,
                    block.timestamp
                );

        }
    }

}