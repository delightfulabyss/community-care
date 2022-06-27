pragma solidity ^0.8.14;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CareToken is ERC20, Ownable {
    constructor (string name , string symbol) ERC20(name, symbol) public {}

    function mint(address to, uint amount) onlyOwner public {
        _mint(amount, to);
    }
}