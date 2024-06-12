
// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts@4.9.0/token/ERC20/ERC20.sol";
import "../games/core/Access.sol";

contract MTD is ERC20, Access {
  event Mint(address indexed to, uint256 amount, uint256 remainingSupply);
  event Burn(address indexed from, uint256 amount);
  uint256 public MAX_SUPPLY;
  constructor(
    string memory _name,
    string memory _symbol,
    address _admin,
    uint256 _maxSupply
  ) ERC20(_name, _symbol) Access(_admin) {
    MAX_SUPPLY = _maxSupply;
  }

  function mint(
    address account,
    uint256 amount
  ) external onlyRole(MINTER_ROLE) returns (uint256, uint256) {
    bool canMint = (totalSupply() + amount <= MAX_SUPPLY);
    uint256 minted = canMint ? amount : 0;
    if (canMint) {
      _mint(account, amount);
    }

    uint256 remainingSupply = MAX_SUPPLY - totalSupply();
    emit Mint(account, minted, remainingSupply);

    return (minted, remainingSupply);
  }

  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
    MAX_SUPPLY -= amount;
    emit Burn(msg.sender, amount);
  }
}
