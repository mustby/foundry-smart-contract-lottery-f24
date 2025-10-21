// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {
    VRFConsumerBaseV2Plus
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/dev/vrf/VRFConsumerBaseV2Plus.sol";
import {
    VRFV2PlusClient
} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/dev/vrf/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author Mustby
 * @notice This contract is for creating a sample raffle contract
 * @dev Implements Chainlink VRF for random number generation VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 length, uint256 s_raffleState);

    /*//////////////////////////////////////////////////////////////
                            Type Declarations
    //////////////////////////////////////////////////////////////*/

    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev The duration of the raffle in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players; // storage variable because the amount fo players will be changing!
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState; // start as open

    // Variable Structure
    // Type - Visibility - Name!

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        // s_vrfCoordinator.requestRandomWords();
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not Enough ETH Sent!");
        // require(msg.value >= i_entranceFee, SendMoreToEnterRaffle());
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked
    //**
    /**
     * @dev this is the function that the chainlink automation nodes call
     * if the lottery is ready to have a winner picked. (using a cron job)
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is OPEN
     * 3. The contract has ETH
     * 4. The contract has players
     * 5. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        returns (
            bool upkeepNeeded, // this bool defaults to false...
            bytes memory /*performData*/
        )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 3. Be automatically called - where is it being directly called? Called by another function? Chainlink auto calls this too?
    function performUpkeep(
        bytes calldata /* perform Data */
    )
        external
    {
        // check to see if enough time has passed
        (bool upkeepNeeded,) = checkUpkeep(bytes(""));
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING; // This starts after the chainlink VRF request....
        // uint256 requestId = s_vrfCoordinator.requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, // gas price
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit, // gas limit
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); // this is where we request the random words!
        // Quiz... is this redundant?
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions Pattern
    // Governs picking the random winners...then resets the lottery!

    // Where does this function get called from???? Do we need this?

    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] memory randomwords
    )
        internal
        override
    {
        // Checks - requires/conditionals/etc
        // Effects (Internal contract state changes)
        uint256 indexOfWinner = randomwords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN; // Reopen the raffle after a winner is picked!
        s_players = new address payable[](0); // Reset the players array
        s_lastTimeStamp = block.timestamp; // Reset the timestamp & interval on when somebody can call pick winner
        emit WinnerPicked(s_recentWinner);

        // Interactions (External contract interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
