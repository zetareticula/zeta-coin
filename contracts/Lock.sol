// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

import 

/// @title ZetaReticulaLock
/// @notice An advanced consensus-driven locking mechanism inspired by Byzantine fault tolerance and relativistic consensus.
contract ZetaReticulaLock is EIP712, Ownable {
    using ECDSA for bytes32;

    struct Lock {
        address proposer; // Address of the proposer
        uint256 value; // Value locked
        uint256 unlockTime; // Time when the lock is eligible for unlocking
        bool isUnlocked; // Status of the lock
        uint256 totalVotesWeight; // Total weighted votes
        uint256 positiveVotesWeight; // Weighted votes for unlocking
        uint256 negativeVotesWeight; // Weighted votes against unlocking
    }

    uint256 public lockCounter;
    mapping(uint256 => Lock) public locks;

    // Track member participation
    mapping(address => bool) public isMember;
    mapping(address => uint256) public memberJoinTime; // When the member joined (used for time-weighted voting)

    uint256 public minConsensusWeight; // Minimum weight required for consensus
    uint256 public voteDecayPeriod = 365 days; // Period for full weight decay

    event LockProposed(uint256 lockId, address proposer, uint256 value, uint256 unlockTime);
    event VoteCast(uint256 lockId, address voter, bool vote, uint256 weight);
    event LockUnlocked(uint256 lockId, address proposer);

    constructor(address[] memory initialMembers, uint256 _minConsensusWeight) EIP712("ZetaReticulaLock", "1") {
        require(initialMembers.length > 0, "Must have initial members");
        require(_minConsensusWeight > 0, "Consensus weight must be positive");

        for (uint256 i = 0; i < initialMembers.length; i++) {
            _addMember(initialMembers[i]);
        }

        minConsensusWeight = _minConsensusWeight;
    }

    /// @notice Propose a new lock
    function proposeLock(uint256 value, uint256 unlockTime) external {
        require(unlockTime > block.timestamp, "Unlock time must be in the future");

        locks[lockCounter] = Lock({
            proposer: msg.sender,
            value: value,
            unlockTime: unlockTime,
            isUnlocked: false,
            totalVotesWeight: 0,
            positiveVotesWeight: 0,
            negativeVotesWeight: 0
        });

        emit LockProposed(lockCounter, msg.sender, value, unlockTime);
        lockCounter++;
    }

    /// @notice Cast a vote off-chain using EIP-712
    function castVote(
        uint256 lockId,
        bool vote,
        bytes memory signature
    ) external {
        require(lockId < lockCounter, "Invalid lock ID");
        Lock storage targetLock = locks[lockId];
        require(!targetLock.isUnlocked, "Lock already unlocked");
        require(block.timestamp >= targetLock.unlockTime, "Lock not eligible yet");

        // Recover signer and ensure membership
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            keccak256("Vote(uint256 lockId,bool vote)"),
            lockId,
            vote
        )));
        address signer = digest.recover(signature);
        require(isMember[signer], "Invalid or non-member signature");

        // Calculate time-weighted voting power
        uint256 weight = _getVotingWeight(signer);
        require(weight > 0, "Insufficient voting power");

        if (vote) {
            targetLock.positiveVotesWeight += weight;
        } else {
            targetLock.negativeVotesWeight += weight;
        }
        targetLock.totalVotesWeight += weight;

        emit VoteCast(lockId, signer, vote, weight);

        // Auto-unlock if consensus is reached
        if (targetLock.positiveVotesWeight >= minConsensusWeight) {
            _unlockLock(lockId);
        }
    }

    /// @notice Unlock a lock manually if consensus is reached
    function unlock(uint256 lockId) external {
        require(lockId < lockCounter, "Invalid lock ID");
        Lock storage targetLock = locks[lockId];
        require(block.timestamp >= targetLock.unlockTime, "Lock not eligible yet");
        require(!targetLock.isUnlocked, "Lock already unlocked");

        require(targetLock.positiveVotesWeight >= minConsensusWeight, "Consensus not reached");
        _unlockLock(lockId);
    }

    /// @notice Get the time-weighted voting power of a member
    function _getVotingWeight(address voter) internal view returns (uint256) {
        uint256 joinTime = memberJoinTime[voter];
        if (joinTime == 0 || joinTime > block.timestamp) return 0;

        uint256 timeInSystem = block.timestamp - joinTime;
        uint256 decayFactor = timeInSystem > voteDecayPeriod ? 0 : voteDecayPeriod - timeInSystem;
        return decayFactor; // Weight decreases as membership ages
    }

    /// @notice Unlock a lock
    function _unlockLock(uint256 lockId) internal {
        Lock storage targetLock = locks[lockId];
        targetLock.isUnlocked = true;

        emit LockUnlocked(lockId, targetLock.proposer);
    }

    /// @notice Add a new parliament member
    function addMember(address newMember) external onlyOwner {
        _addMember(newMember);
    }

    /// @notice Internal helper to add a new member
    function _addMember(address newMember) internal {
        require(!isMember[newMember], "Already a member");
        isMember[newMember] = true;
        memberJoinTime[newMember] = block.timestamp;
    }

    /// @notice Remove a parliament member
    function removeMember(address member) external onlyOwner {
        require(isMember[member], "Not a member");
        isMember[member] = false;
        delete memberJoinTime[member];
    }
}
