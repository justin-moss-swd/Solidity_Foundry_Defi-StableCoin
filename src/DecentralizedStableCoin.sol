// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Justin Moss 2023
 * @dev Value: Pegged to USD
 * Minting: Algorithmic (Decentralized)
 * Collateral: Exogenous
 * Collateral Type: Crypto
 *
 * @dev This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();
    
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

        function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if(_to == address(0))  revert DecentralizedStableCoin__NotZeroAddress();
        if(_amount <= 0)       revert DecentralizedStableCoin__MustBeMoreThanZero();

        _mint(_to, _amount);

        return true;
    }
    
    function burn(uint256 _amount) public override onlyOwner() {
        uint256 balance = balanceOf(msg.sender);

        if(_amount <= 0)       revert DecentralizedStableCoin__MustBeMoreThanZero(); 
        if(_amount > balance)  revert DecentralizedStableCoin__BurnAmountExceedsBalance();

        super.burn(_amount);
    }
}