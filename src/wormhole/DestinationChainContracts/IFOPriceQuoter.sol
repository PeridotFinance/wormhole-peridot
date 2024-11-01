//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import 'wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol';
import 'wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

contract IFOPriceQuoter is IWormholeReceiver, Ownable {
    IWormholeRelayer public wormholeRelayer;
    address public wormholeIFO;
    uint256 constant GAS_LIMIT = 100000;
    uint256 public currentBlindBoxPrice;

    mapping(uint16 => bytes32) public registeredSenders;
    mapping(address => uint256) public blindBoxPrice;

    struct Price {
        address miniNFT;
        uint256 price;
    }

    event MessageReceived(string message);

    modifier isRegisteredSender(uint16 sourceChain, bytes32 sourceAddress) {
        require(
            registeredSenders[sourceChain] == sourceAddress,
            "Not registered sender"
        );
        _;
    }

    modifier onlyWormholeIFO() {
        require(
            msg.sender == wormholeIFO,
            "Only the Wormhole IFO can call this function"
        );
        _;
    }

    constructor(address _wormholeRelayer, address _wormholeIFO) Ownable() {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        wormholeIFO = _wormholeIFO;
    }

    function getQuote(address miniNFTAddress) public onlyWormholeIFO returns (uint256) {
        
        blindBoxPrice[miniNFTAddress] = currentBlindBoxPrice;
        
        return currentBlindBoxPrice;
    }

    function setRegisteredSender(
        uint16 sourceChain,
        bytes32 sourceAddress
    ) public onlyOwner {
        registeredSenders[sourceChain] = sourceAddress;
    }

    function quoteCrossChainCost(
        uint16 targetChain
    ) public view returns (uint256 cost) {
        (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            GAS_LIMIT
        );
    }

    /**
     * @notice Sends a Wormhole message to the IFOPriceReceiver contract.
     * @param targetChain The chain ID of the target chain.
     * @param targetAddress The address of the IFOPriceReceiver contract.
     * @param miniNFTAddress The address of the MiniNFT contract.
     */
    function sendMessage(
        uint16 targetChain,
        address targetAddress,
        uint256 miniNFTAddress	
    ) public payable {
        uint256 cost = quoteCrossChainCost(targetChain);

        require(
            msg.value >= cost,
            "Insufficient funds for cross-chain delivery"
        );

        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetAddress,
            abi.encode(miniNFTAddress),
            0,
            GAS_LIMIT
        );

    }

    /**
     * @notice Handles incoming Wormhole messages from the IFOPriceReceiver contract.
     * @param payload The payload of the Wormhole message.
     * @param sourceAddress The address of the sender on the source chain.
     * @param sourceChain The chain ID of the source chain.
     */
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32
    ) public payable override isRegisteredSender(sourceChain, sourceAddress) {
        require(
            msg.sender == address(wormholeRelayer),
            "Only the Wormhole relayer can call this function"  
        );

        Price memory _price = abi.decode(payload, (Price));
        blindBoxPrice[_price.miniNFT] = _price.price;
        currentBlindBoxPrice = _price.price;
    }

    function withdrawETH() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {}
}