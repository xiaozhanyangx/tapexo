// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title XRaffle - commit-reveal raffle for X/Twitter giveaways (operator-run)
/// @notice The operator (server key in a Cloudflare Worker) commits keccak256(seed) together with the
///         hash of the canonical entry list. After `revealDelay` blocks it reveals the seed. Randomness =
///         keccak256(seed, entriesHash, blockhash(commitBlock + revealDelay)). Winners are derived by
///         `deriveWinners`, a pure function anyone can re-run off-chain.
///         Storage is kept minimal (gas): full entry/result files live off-chain (R2); the chain holds
///         entriesHash (commit), randomness (reveal) and resultsHash (finalize, as an event, once).
contract XRaffle {
    struct Raffle {
        bytes32 entriesHash;   // keccak256 of canonical entries file (see README)
        bytes32 seedHash;      // keccak256(abi.encodePacked(seed))
        uint32 entryCount;
        uint16 winnerCount;
        uint64 commitBlock;
        bytes32 randomness;    // set on reveal
        bool revealed;
        bool blockhashMissing; // reveal happened > 256 blocks after target; seed-only randomness
        bool finalized;        // resultsHash recorded (see Finalized event); packed in the same slot as `revealed`
    }

    address public owner;
    mapping(address => bool) public operators;
    uint64 public immutable revealDelay;
    uint256 public raffleCount;
    mapping(uint256 => Raffle) public raffles;

    event OperatorSet(address indexed op, bool enabled);
    event Committed(uint256 indexed id, string ref, bytes32 entriesHash, uint32 entryCount, uint16 winnerCount, bytes32 seedHash);
    event Revealed(uint256 indexed id, bytes32 seed, bytes32 randomness, bool blockhashMissing);
    /// resultsHash = sha256(results.json bytes) — same hash a browser/curl user can compute on the downloaded file.
    event Finalized(uint256 indexed id, bytes32 resultsHash);

    error NotOwner(); error NotOperator(); error BadParams(); error AlreadyRevealed(); error TooEarly(); error BadSeed(); error NotRevealed(); error AlreadyFinalized();

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    modifier onlyOperator() { if (!operators[msg.sender]) revert NotOperator(); _; }

    constructor(address operator, uint64 _revealDelay) {
        owner = msg.sender;
        revealDelay = _revealDelay == 0 ? 1 : _revealDelay;
        operators[operator] = true;
        emit OperatorSet(operator, true);
    }

    function setOperator(address op, bool enabled) external onlyOwner { operators[op] = enabled; emit OperatorSet(op, enabled); }
    function transferOwnership(address n) external onlyOwner { owner = n; }

    function commit(string calldata ref, bytes32 entriesHash, uint32 entryCount, uint16 winnerCount, bytes32 seedHash)
        external onlyOperator returns (uint256 id)
    {
        if (entryCount == 0 || winnerCount == 0 || winnerCount > entryCount || winnerCount > 500 || seedHash == 0) revert BadParams();
        id = ++raffleCount;
        Raffle storage r = raffles[id];
        r.entriesHash = entriesHash; r.seedHash = seedHash; r.entryCount = entryCount;
        r.winnerCount = winnerCount; r.commitBlock = uint64(block.number); // ref only in the event (no string storage)
        emit Committed(id, ref, entriesHash, entryCount, winnerCount, seedHash);
    }

    function revealBlock(uint256 id) public view returns (uint256) { return raffles[id].commitBlock + revealDelay; }

    function reveal(uint256 id, bytes32 seed) external onlyOperator {
        Raffle storage r = raffles[id];
        if (r.commitBlock == 0) revert BadParams();
        if (r.revealed) revert AlreadyRevealed();
        uint256 target = revealBlock(id);
        if (block.number <= target) revert TooEarly();
        if (keccak256(abi.encodePacked(seed)) != r.seedHash) revert BadSeed();
        bytes32 bh = blockhash(target); // zero if older than 256 blocks
        r.blockhashMissing = bh == 0;
        r.randomness = keccak256(abi.encodePacked(seed, r.entriesHash, bh));
        r.revealed = true;
        emit Revealed(id, seed, r.randomness, r.blockhashMissing);
    }

    /// @notice Records the hash of the final results file (after the off-chain candidate walk). Once per raffle.
    function finalize(uint256 id, bytes32 resultsHash) external onlyOperator {
        Raffle storage r = raffles[id];
        if (!r.revealed) revert NotRevealed();
        if (r.finalized) revert AlreadyFinalized();
        r.finalized = true;
        emit Finalized(id, resultsHash);
    }

    /// @notice Primary winners (ranks 1..k of the ranking), computed on the fly from stored randomness (not stored).
    function winnersOf(uint256 id) external view returns (uint32[] memory) {
        Raffle storage r = raffles[id];
        if (!r.revealed) return new uint32[](0);
        return deriveWinners(r.randomness, r.entryCount, r.winnerCount);
    }

    /// @notice Deterministic: index_i = keccak256(randomness, nonce) % n, skipping duplicates. 0-based indices
    ///         into the canonical entries list.
    function deriveWinners(bytes32 randomness, uint32 n, uint16 k) public pure returns (uint32[] memory out) {
        if (k > n) revert BadParams();
        out = new uint32[](k);
        uint256 found; uint256 nonce;
        while (found < k) {
            uint32 idx = uint32(uint256(keccak256(abi.encodePacked(randomness, nonce))) % n);
            nonce++;
            bool dup;
            for (uint256 j; j < found; j++) if (out[j] == idx) { dup = true; break; }
            if (!dup) out[found++] = idx;
        }
    }
}
