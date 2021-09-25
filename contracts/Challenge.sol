// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "./lib/Lib_RLPReader.sol";

interface IMIPS {
  function Step(bytes32 stateHash) external view returns (bytes32);
  function ReadMemory(bytes32 stateHash, uint32 addr) external view returns (uint32);
  function WriteMemory(bytes32 stateHash, uint32 addr, uint32 val) external pure returns (bytes32);
}

contract Challenge {
  address payable immutable owner;
  IMIPS immutable mips;
  bytes32 immutable GlobalStartState;

  struct Chal {
    uint256 L;
    uint256 R;
    mapping(uint256 => bytes32) assertedState;
    mapping(uint256 => bytes32) defendedState;
    address payable challenger;
  }
  mapping(uint256 => Chal) challenges;

  constructor(IMIPS imips, bytes32 globalStartState) {
    owner = msg.sender;
    mips = imips;
    GlobalStartState = globalStartState;
  }

  // allow getting money
  fallback() external payable {}
  receive() external payable {}
  function withdraw() external {
    require(msg.sender == owner);
    owner.transfer(address(this).balance);
  }

  // memory helpers

  function writeBytes32(bytes32 stateHash, uint32 addr, bytes32 val) internal view returns (bytes32) {
    for (uint32 i = 0; i < 32; i += 4) {
      uint256 tv = uint256(val>>(224-(i*8)));

      stateHash = mips.WriteMemory(stateHash, addr+i, uint32(tv));
    }
    return stateHash;
  }

  function readBytes32(bytes32 stateHash, uint32 addr) internal view returns (bytes32) {
    uint256 ret = 0;
    for (uint32 i = 0; i < 32; i += 4) {
      ret <<= 32;
      ret |= uint256(mips.ReadMemory(stateHash, addr+i));
    }
    return bytes32(ret);
  }
  
  // create challenge
  uint256 lastChallengeId = 0;

  function newChallengeTrusted(bytes32 startState, bytes32 finalSystemState, uint256 stepCount) internal returns (uint256) {
    uint256 challengeId = lastChallengeId;
    Chal storage c = challenges[challengeId];
    lastChallengeId += 1;

    // the challenger arrives
    c.challenger = msg.sender;

    // the state is set 
    c.assertedState[0] = startState;
    c.defendedState[0] = startState;
    c.assertedState[stepCount] = finalSystemState;

    // init the binary search
    c.L = 0;
    c.R = stepCount;

    // find me later
    return challengeId;
  }

  function InitiateChallenge(uint blockNumberN,
        bytes calldata blockHeaderN, bytes calldata blockHeaderNp1,
        bytes32 assertionRoot, bytes32 finalSystemState, uint256 stepCount) external returns (uint256) {
    require(blockhash(blockNumberN) == keccak256(blockHeaderN), "start block hash wrong");
    require(blockhash(blockNumberN+1) == keccak256(blockHeaderNp1), "end block hash wrong");

    // decode the blocks
    Lib_RLPReader.RLPItem[] memory blockN = Lib_RLPReader.readList(blockHeaderN);
    Lib_RLPReader.RLPItem[] memory blockNp1 = Lib_RLPReader.readList(blockHeaderNp1);
    bytes32 newroot = Lib_RLPReader.readBytes32(blockNp1[3]);
    require(assertionRoot != newroot, "asserting that the real state is correct is not a challenge");

    // input oracle info
    bytes32 root = Lib_RLPReader.readBytes32(blockN[3]);
    bytes32 txhash = Lib_RLPReader.readBytes32(blockNp1[4]);
    address coinbase = Lib_RLPReader.readAddress(blockNp1[2]);
    bytes32 uncles = Lib_RLPReader.readBytes32(blockNp1[1]);

    // load starting info into the input oracle
    // we both agree at the beginning
    bytes32 startState = GlobalStartState;
    startState = writeBytes32(startState, 0xD0000000, root);
    startState = writeBytes32(startState, 0xD0000020, txhash);
    startState = writeBytes32(startState, 0xD0000040, bytes32(uint256(coinbase)));
    startState = writeBytes32(startState, 0xD0000060, uncles);

    // confirm the finalSystemHash asserts the state you claim (in $t0-$t7) and the machine is stopped
    // we disagree at the end
    require(readBytes32(finalSystemState, 0xC0000020) == assertionRoot, "you are claiming a different state in machine");
    require(mips.ReadMemory(finalSystemState, 0xC0000080) == 0xDEAD0000, "machine is not stopped in final state (PC == 0xDEAD0000)");

    return newChallengeTrusted(startState, finalSystemState, stepCount);
  }

  // binary search

  function getStepNumber(uint256 challengeId) view public returns (uint256) {
    Chal storage c = challenges[challengeId];
    return (c.L+c.R)/2;
  }

  function ProposeState(uint256 challengeId, bytes32 riscState) external {
    Chal storage c = challenges[challengeId];
    require(c.challenger == msg.sender, "must be challenger");

    uint256 stepNumber = getStepNumber(challengeId);
    require(c.assertedState[stepNumber] == bytes32(0), "state already proposed");
    c.assertedState[stepNumber] = riscState;
  }

  function RespondState(uint256 challengeId, bytes32 riscState) external {
    Chal storage c = challenges[challengeId];
    require(msg.sender == owner, "must be owner");

    uint256 stepNumber = getStepNumber(challengeId);
    require(c.assertedState[stepNumber] != bytes32(0), "challenger state not proposed");
    require(c.defendedState[stepNumber] == bytes32(0), "state already proposed");
    // technically, we don't have to save these states
    // but if we want to prove us right and not just the attacker wrong, we do
    c.defendedState[stepNumber] = riscState;
    if (c.assertedState[stepNumber] == c.defendedState[stepNumber]) {
      // agree
      c.L = stepNumber;
    } else {
      // disagree
      c.R = stepNumber;
    }
  }

  // final payout

  function ConfirmStateTransition(uint256 challengeId) external {
    Chal storage c = challenges[challengeId];
    require(c.challenger == msg.sender, "must be challenger");

    require(c.L + 1 == c.R, "binary search not finished");
    bytes32 newState = mips.Step(c.assertedState[c.L]);
    require(newState == c.assertedState[c.R], "wrong asserted state");

    // pay out bounty!!
    msg.sender.transfer(address(this).balance);
  }
}
