pragma solidity 0.8.3;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./ERC721LendingPool02.sol";

contract LandRover01 is IFlashLoanReceiver, Ownable {
    using SafeERC20 for IERC20;

    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        // repay the loan
        address payable currentFlashLoanSource;
        address payable currentLendingPool;
        address currency;
        // uint256 valuation;
        // uint256 nftID;
        // uint256 loanDurationSeconds;
        // uint256 expireAtBlock;
        // uint256 borrowedWei;
        // uint256 outstanding;
        uint256[7] memory numbers;
        address pineWallet;
        bytes memory signature;
        (
            currency,
            currentFlashLoanSource,
            currentLendingPool,
            numbers,
            signature,
            pineWallet
        ) = abi.decode(
            _params,
            (address, address, address, uint256[7], bytes, address)
        );
        IERC20(currency).approve(currentLendingPool, numbers[5]);
        require(
            ERC721LendingPool02(currentLendingPool).repay(
                numbers[1],
                numbers[5],
                pineWallet
            )
        );
        require(ERC721LendingPool02(currentLendingPool).borrow(
            [numbers[0], numbers[1], numbers[2], numbers[3], numbers[4], numbers[6]],
            signature,
            true,
            pineWallet
        ));
        IERC20(currency).safeTransfer(
            ERC721LendingPool02(currentFlashLoanSource)._fundSource(),
            _amount + _fee
        );
    }

    function rover(
        address erc721,
        address payable flashLoanSource,
        address payable lendingPool,
        uint256[7] calldata numbers,
        bytes memory signature,
        address pineWallet
    ) external payable {
        address currency = ERC721LendingPool02(lendingPool)
            ._supportedCurrency();
        ERC721LendingPool02(flashLoanSource).flashLoan(
            payable(this),
            currency,
            numbers[5],
            abi.encode(
                currency,
                flashLoanSource,
                lendingPool,
                numbers,
                signature,
                pineWallet
            )
        );
    }

    receive() external payable {
        // React to receiving ether
    }
}
