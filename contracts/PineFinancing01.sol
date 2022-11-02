pragma solidity 0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./ERC721LendingPool02.sol";
import "./PineWallet01.sol";
import "./interfaces/WETH.sol";


contract PineFinancing is Ownable, IFlashLoanReceiver {
  using SafeERC20 for IERC20;
  address payable immutable WETHaddr;

  constructor (address w) {
    require(w != address(0));
    WETHaddr = payable(w);
  }
  
  mapping(bytes32 => bool) approvedMethods;

  function setWhitelistedMethods(address target, bytes4 selector, bool operable) public onlyOwner{
    approvedMethods[keccak256(abi.encodePacked(target, selector))] = operable;
  }

  function buyERC721(address marketplace, bytes calldata data, uint256 listedPrice) public {
    bytes4 selector;
    assembly {
        selector := calldataload(data.offset)
    }
    require(approvedMethods[keccak256(abi.encodePacked(marketplace, selector))], "cannot operate collateralized assets" );
    (bool success, ) = marketplace.call{value: listedPrice}(data);
    require(success);
  }

  function executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes calldata _params) external override {
    // address erc721;
    // address payable flashLoanSource;
    // address payable targetPool;
    // address marketplace;
    address[4] memory addresses;
    // uint256 valuation;
    // uint256 nftID;
    // uint256 loanDurationSeconds;
    // uint256 expireAtBlock;
    // uint256 borrowedWei;
    // uint256 listedPrice;
    uint256[7] memory numbers;
    bytes memory signature;
    bytes memory purchaseInstruction;
    address payable pineWallet;
    (addresses, numbers, signature, purchaseInstruction, pineWallet) = abi.decode(_params, (address[4], uint256[7], bytes, bytes, address));
    WETH9(WETHaddr).withdraw(numbers[5]);
    this.buyERC721(addresses[3], purchaseInstruction, numbers[5]);
    if (pineWallet != address(0)) {
      IERC721(addresses[0]).setApprovalForAll(pineWallet, true);
      PineWallet(pineWallet).depositCollateral(addresses[0], numbers[1]);
      ERC721LendingPool02(payable(addresses[2])).borrow([numbers[0], numbers[1], numbers[2], numbers[3], numbers[4], numbers[6]], signature, true, pineWallet);
    }
    else {
      IERC721(addresses[0]).safeTransferFrom(address(this), tx.origin, numbers[1]);
      ERC721LendingPool02(payable(addresses[2])).borrow([numbers[0], numbers[1], numbers[2], numbers[3], numbers[4], numbers[6]], signature, true, pineWallet);
    }
    WETH9(WETHaddr).deposit{value: address(this).balance}();
    IERC20(WETHaddr).safeTransfer(ERC721LendingPool02(payable(addresses[1]))._fundSource(), _amount + _fee);
  }


  function pnpl(
    address erc721,
    address payable flashLoanSource,
    address payable targetPool,
    address marketplace,
    uint256[7] calldata numbers,
    bytes memory signature,
    bytes calldata purchaseInstruction,
    address payable pineWallet) 
  external payable {
    ERC721LendingPool02(flashLoanSource).flashLoan(payable(address(this)), WETHaddr, numbers[5], abi.encode([erc721, flashLoanSource, targetPool], marketplace, numbers, signature, purchaseInstruction, pineWallet));
  }

  receive() external payable {
        // React to receiving ether
  }

  function withdraw(uint256 amount) public onlyOwner {
    (bool success, ) = owner().call{value: amount}("");
    require(success, "cannot send ether");
  }
  function withdrawERC20(address currency, uint256 amount) public onlyOwner {
    IERC20(currency).safeTransfer(owner(), amount);
  }

  function withdrawERC721(address collection, uint256 nftID)
    public
    onlyOwner
  {
      IERC721(collection).safeTransferFrom(address(this), owner(), nftID);
  }


}