pragma solidity 0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ERC721LendingPool02.sol";
import "./interfaces/WETH.sol";

contract Router01 is Ownable {
  using SafeERC20 for IERC20;
  address immutable WETHaddr;

  constructor (address w) {
    WETHaddr = w;
  }

  function approvePool(address currency, address target, uint256 amount) public onlyOwner{
    IERC20(currency).approve(target, amount);
  }

  function borrowETH(
    address payable target,
    uint256 valuation,
    uint256 nftID,
    uint256 loanDurationSeconds,
    uint256 expireAtBlock,
    uint256 borrowedWei,
    uint256 nonce,
    bytes memory signature,
    address pineWallet
  ) public{
    address currency = ERC721LendingPool02(target)._supportedCurrency();
    require(currency == WETHaddr, "only works for WETH");
    require(ERC721LendingPool02(target).borrow([valuation, nftID, loanDurationSeconds, expireAtBlock, borrowedWei, nonce], signature, true, pineWallet), "cannot borrow");
    WETH9(payable(currency)).withdraw(IERC20(currency).balanceOf(address(this)));
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "cannot send ether");
  }

  function repay(address payable target, uint256 nftID, uint256 repayAmount, address pineWallet) public {
    address currency = ERC721LendingPool02(target)._supportedCurrency();
    IERC20(currency).safeTransferFrom(msg.sender, address(this), repayAmount);
    ERC721LendingPool02(target).repay(nftID, repayAmount, pineWallet);
    IERC20(currency).safeTransferFrom(address(this), msg.sender, IERC20(currency).balanceOf(address(this)));
  }

  function repayETH(address payable target, uint256 nftID, address pineWallet) payable public {
    address currency = ERC721LendingPool02(target)._supportedCurrency();
    require(currency == WETHaddr, "only works for WETH");
    WETH9(payable(currency)).deposit{value: msg.value}();
    ERC721LendingPool02(target).repay(nftID, msg.value, pineWallet);
    WETH9(payable(currency)).withdraw(IERC20(currency).balanceOf(address(this)));
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "cannot send ether");
  }

  receive() external payable {
        // React to receiving ether
  }
}