import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MutualToken is ERC20, Ownable {
    constructor (string name , string symbol) ERC20(name, symbol) public {}

    function mint(uint256 amount , address to) onlyOwner public {
        _mint(amount, to);
    }
}