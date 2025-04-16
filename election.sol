pragma solidity >=0.7.0 <0.9.0;

contract election
{
    mapping(uint=>address) voter; // store the voter's address
    mapping(uint=>uint) D; // store the deposit made
    mapping(uint=>uint) signD; // store the deposit made for signing
    mapping(uint256=>address) hiddenVoter; // store the address of voter who voted with sn 
    mapping(uint=>uint) signStatus; // store the signing status of each deposit
    mapping(uint=>uint256) mdPrimes; // store the committed mdPrimes in the function received_signature()
    mapping(uint256=>bytes32) voteHashes; // store the vote hashes correspond to particular serial numbers (sn)
    mapping(uint256=>bytes32) signatureHashes; // store the blind signature hashes correspond to particular serial numbers (sn)
    mapping(uint=>uint) count; // store number of votes obtained for each candidate
    

    uint n = 0; // number of votes created (number of deposit made)
    uint k; // numeber of candidates/options
    uint e; // signer's public key
    uint deployedBlockNumber;
    
    uint highestVoteNum = 0;
    uint elected;
    uint depos = 500000000000000000; // deposit = 0.5 ETH

    address payable signer = payable(address(0));
    uint N; // modulo in blind signature

    uint t1; // register deadline
    uint t1_1; // request signing deadline
    uint t1_2; // signing deadline
    uint t1_3; // report signature received deadline
    uint t2; // voting deadline
    uint t3; // revelation deadline
    uint t4; // withdraw deadline

    constructor(uint _k, uint _N, uint _e, address _signer, uint _t1, uint _t1_1, uint _t1_2, uint _t1_3, uint _t2, uint _t3, uint _t4)
    {
        deployedBlockNumber = block.number;
        signer = payable(_signer); // specify a signer for this election
        k = _k;
        e = _e;
        N = _N;
        t1 = _t1 + block.number;
        t1_1 = _t1_1 + block.number; 
        t1_2 = _t1_2 + block.number; 
        t1_3 = _t1_3 + block.number; 
        t2 = _t2 + block.number; 
        t3 = _t3 + block.number; 
        t4 = _t4 + block.number; 
    }

    function voter_register() public payable
    {
        require(block.number >= deployedBlockNumber && block.number < deployedBlockNumber + t1);
        require(msg.value == depos, "Wrong value."); // require deposit of 0.5 eth for each vote
        voter[n] = msg.sender;
        D[n] = depos;
        n++;
    }

  
    function request_sign(uint depositID) public
    {
    
        require(block.number >= deployedBlockNumber + t1 && block.number < deployedBlockNumber + t1_1);
        require(msg.sender == voter[depositID]);
        require(signStatus[depositID] == 0);
        signD[depositID] += 200000000000000000; // deposit 0.2 ether to make sure that the voter call recieved_signature honestly later
        D[depositID] -= 200000000000000000;
        signStatus[depositID] = 1; // status 1: requesting
    }

    function signed(uint depositID) public payable
    {
        require(block.number >= deployedBlockNumber + t1_1 && block.number < deployedBlockNumber + t1_2);
        require(msg.sender == signer, "You're not the signer.");
        require(msg.value == 100000000000000000, "Wrong deposit value."); // deposit 0.1 ether to make sure that the signer doesn't fake that he signed
        require(signStatus[depositID] == 1, "Wrong status."); // The signature should be requested
        signStatus[depositID] = 2; // status 2: signed 
        signD[depositID] += msg.value;
    }

    function received_signature(uint depositID, uint256 mdPrime) public 
    {
        require(block.number >= deployedBlockNumber + t1_2 && block.number < deployedBlockNumber + t1_3);
        require(msg.sender == voter[depositID]);
        require(signStatus[depositID] == 2); // The signer should have claimed that he signed
        signStatus[depositID] == 3; // status 3: signature received by voter
        mdPrimes[depositID] = mdPrime; // (m')^d is recorded in case of the voter need to prove his vote later
        signD[depositID] -= 100000000000000000;
        D[depositID] += 100000000000000000; // return 0.1 ether to the voter's deposit, another 0.1 is going to be paid to signer
        uint val = signD[depositID]; // should be 0.2 eth (0.1 from voter's deposit + 0.1 from signer's deposit)
        signD[depositID] = 0;
        (bool sent, bytes memory data) = signer.call{value: val}(""); // return the deposit to the signer and give him reward for signing
        require(sent, "Sending ether threw an exception.");
    }

    function vote(uint256 sn, bytes32 hs, bytes32 hv) public payable
    {
        require(block.number >= deployedBlockNumber + t1_3 && block.number < deployedBlockNumber + t2);
        require(msg.value == depos);
        require(voteHashes[sn] == bytes32(0)); // prevent re-entrancy (or others want to change hv)
        hiddenVoter[sn] = msg.sender;
        voteHashes[sn] = hv;
        signatureHashes[sn] = hs;
    }

    function reveal(uint256 sn, uint256 s, uint v, uint nonce) public
    {
        require(block.number >= deployedBlockNumber + t2 && block.number < deployedBlockNumber + t3);
        require(msg.sender == hiddenVoter[sn]);
        require(bytes32(((s % N) ** e) % N) == sha256(abi.encodePacked(sn))); // verifying blind signature 
        
        require(v > 0 && v < k);
        if (sha256(abi.encodePacked(v, nonce)) == voteHashes[sn] && sha256(abi.encodePacked(s)) == signatureHashes[sn])
        {
            count[v]++;
            if (count[v] > highestVoteNum)
            {
                highestVoteNum = count[v];
                elected = v;
            }
            voteHashes[sn] = 0; // prevent re-entrancy
            (bool sent, bytes memory data) = hiddenVoter[sn].call{value: depos}(""); // return deposit of 0.5 ETH
            require(sent, "Sending ether threw an exception.");
        }
        
    }

    function withdraw(uint depositID) public 
    {
        require(block.number >= deployedBlockNumber + t3 && block.number < deployedBlockNumber + t4);

        if (D[depositID] != 0)
        {
            uint refund = D[depositID]; 
            D[depositID] = 0; // prevent re-entrancy
            if (signStatus[depositID] == 1) // The signer didn't sign
            {
                refund += signD[depositID];
                signD[depositID] = 0;
            }
            (bool sent, bytes memory data) = voter[depositID].call{value: refund}("");
            require(sent, "Sending ether threw an exception.");
        }
    }

}
