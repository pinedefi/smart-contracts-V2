/**
  * ControlPlane01.sol
  * Registers the current global params
 */
pragma solidity 0.8.3;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./CloneFactory02.sol";
import "./ERC721LendingPool02.sol";
import "./PineLendingLibrary.sol";

contract ControlPlane01 is Ownable {
  using SafeERC20 for IERC20;
  mapping (address => bool) public whitelistedIntermediaries;
  address public whitelistedFactory;
  uint32 public feeBps = 0;
  uint256 constant PRECISION = 1000000000000;

  mapping (address => uint256) public currentUserNonce;

  function setUserNonce(uint256 nonce) external {
    require(CloneFactory02(whitelistedFactory).genuineClone(msg.sender), "only genuine clones can set nonce");
    require((currentUserNonce[tx.origin] == 0 && nonce == 0) || nonce == currentUserNonce[tx.origin] + 1, "wrong nonce");
    currentUserNonce[tx.origin] = nonce;
  }


  function toggleWhitelistedIntermediaries(address target) external onlyOwner {
    whitelistedIntermediaries[target] = !whitelistedIntermediaries[target];
  }

  function setWhitelistedFactory(address target) external onlyOwner {
    whitelistedFactory = target;
  }

  function setFee(uint32 f) external onlyOwner {
    require(f < PineLendingLibrary.ONE_HUNDRED_PERCENT_BPS);
    feeBps = f;
  }

  function ceil(uint256 a, uint256 m) public pure returns (uint256 ) {
      return ((a + m - 1) / m) * m;
  }


  function outstanding(PineLendingLibrary.LoanTerms calldata loanTerms, uint256 txSpeedBlocks) external view returns (uint256) {
    uint256 adjustedO = PineLendingLibrary.outstanding(loanTerms, txSpeedBlocks);
    uint256 ogO = PineLendingLibrary.outstanding(loanTerms);
    if (adjustedO != ogO) {
      return ceil(adjustedO, PRECISION);
    } else {
      return ogO;
    }
  }

  function outstanding(PineLendingLibrary.LoanTerms calldata loanTerms) external view returns (uint256) {
    return PineLendingLibrary.outstanding(loanTerms);
  }

  function withdraw(uint256 amount) external onlyOwner {
    (bool success, ) = owner().call{value: amount}("");
    require(success, "cannot send ether");
  }

  function withdrawERC20(address currency, uint256 amount) external onlyOwner {
    IERC20(currency).safeTransfer(owner(), amount);
  }


  function liquidateNFT(address payable target, uint256 loanID) external {
    ERC721LendingPool02 pool = ERC721LendingPool02(target);
    // TODO: check unhealthy
    (uint256 loanStartBlock,
    uint256 loanExpireTimestamp,
    uint32 interestBPS1000000XBlock,
    ,
    uint256 borrowedWei,
    uint256 returnedWei,
    uint256 accuredInterestWei,
    uint256 repaidInterestWei,
    ) = pool._loans(loanID);
    PineLendingLibrary.LoanTerms memory lt = PineLendingLibrary.LoanTerms(
     loanStartBlock,
     loanExpireTimestamp,
     interestBPS1000000XBlock,
     0,
     borrowedWei,
     returnedWei,
     accuredInterestWei,
     repaidInterestWei,
     address(0));
    bool unhealthy = PineLendingLibrary.isUnHealthyLoan(lt);
    require(unhealthy, "Loan is not liquidable");
    require((pool.owner() == msg.sender), "wrong operator");
    pool.withdrawERC721(pool._supportedCollection(), loanID, pool.owner(), true);
  }

  function withdrawNFT(address payable target, address nft, uint256 id) external {
    ERC721LendingPool02 pool = ERC721LendingPool02(target);
    // TODO: check unhealthy
    (uint256 loanStartBlock,
    uint256 loanExpireTimestamp,
    uint32 interestBPS1000000XBlock,
    ,
    uint256 borrowedWei,
    uint256 returnedWei,
    uint256 accuredInterestWei,
    uint256 repaidInterestWei,
    ) = pool._loans(id);
    PineLendingLibrary.LoanTerms memory lt = PineLendingLibrary.LoanTerms(loanStartBlock,
     loanExpireTimestamp,
     interestBPS1000000XBlock,
     0,
     borrowedWei,
     returnedWei,
     accuredInterestWei,
     repaidInterestWei,
     address(0));
    (bool has) = PineLendingLibrary.nftHasLoan(lt);
    require(!has, "Loan is active");
    require((pool.owner() == msg.sender), "wrong operator");
    pool.withdrawERC721(nft, id, pool.owner(), false);
  }
}