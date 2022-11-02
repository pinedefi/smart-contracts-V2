// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;
import "./VerifySignaturePool02.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IControlPlane01.sol";
import "./interfaces/ICloneFactory02.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./PineLendingLibrary.sol";

contract ERC721LendingPool02 is
    OwnableUpgradeable,
    IERC721Receiver,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    /**
     * Pool Constants
     */
    address public _valuationSigner;

    address public _supportedCollection;

    address public _controlPlane;

    address public _fundSource;

    address public _supportedCurrency;


    mapping(uint256 => PineLendingLibrary.PoolParams) public durationSeconds_poolParam;
    mapping(uint256 => uint256) public blockLoanAmount;
    uint256 public blockLoanLimit;

    /**
     * Pool Setup
     */

    function initialize(
        address supportedCollection,
        address valuationSigner,
        address controlPlane,
        address supportedCurrency,
        address fundSource
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        require(supportedCollection != address(0));
        require(valuationSigner != address(0));
        require(controlPlane != address(0));
        require(supportedCurrency != address(0));
        require(fundSource != address(0));
        _supportedCollection = supportedCollection;
        _valuationSigner = valuationSigner;
        _controlPlane = controlPlane;
        _supportedCurrency = supportedCurrency;
        _fundSource = fundSource;
        blockLoanLimit = 80000000000000000000;
    }

    function setBlockLoanLimit(uint256 bll) public onlyOwner {
        require(bll > 0);
        blockLoanLimit = bll;
    }

    function setDurationParam(uint256 duration, PineLendingLibrary.PoolParams calldata ppm)
        external
        onlyOwner
    {
        durationSeconds_poolParam[duration] = ppm;
        require(durationSeconds_poolParam[0].collateralFactorBPS == 0);

        emit PineLendingLibrary.PoolParamsChanged(address(this), duration, ppm);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateBlockLoanAmount(uint256 loanAmount) internal {
        blockLoanAmount[block.number] += loanAmount;
        require(
            blockLoanAmount[block.number] < blockLoanLimit,
            "Amount exceed block limit"
        );
    }

    /**
     * Storage and Events
     */

    mapping(uint256 => PineLendingLibrary.LoanTerms) public _loans;

    /**
     * Loan origination
     */
    function flashLoan(
        address payable _receiver,
        address _reserve,
        uint256 _amount,
        bytes memory _params
    ) external nonReentrant whenNotPaused {
        //check that the reserve has enough available liquidity
        uint256 availableLiquidityBefore = _reserve == address(0)
            ? address(this).balance
            : IERC20(_reserve).balanceOf(_fundSource);
        require(
            availableLiquidityBefore >= _amount,
            "There is not enough liquidity available to borrow"
        );

        uint256 lenderFeeBips = durationSeconds_poolParam[0]
            .interestBPS1000000XBlock;
        //calculate amount fee
        uint256 amountFee = (_amount * (lenderFeeBips)) / (PineLendingLibrary.INTEREST_PRECISION);

        //get the FlashLoanReceiver instance
        IFlashLoanReceiver receiver = IFlashLoanReceiver(_receiver);

        //transfer funds to the receiver
        if (_reserve == address(0)) {
            (bool success, ) = _receiver.call{value: _amount}("");
            require(success, "Flash loan: cannot send ether");
        } else {
            IERC20(_reserve).safeTransferFrom(_fundSource, _receiver, _amount);
        }

        //execute action of the receiver
        receiver.executeOperation(_reserve, _amount, amountFee, _params);

        //check that the actual balance of the core contract includes the returned amount
        uint256 availableLiquidityAfter = _reserve == address(0)
            ? address(this).balance
            : IERC20(_reserve).balanceOf(_fundSource);

        require(
            availableLiquidityAfter == availableLiquidityBefore + (amountFee),
            "The actual balance of the protocol is inconsistent"
        );
        require(lenderFeeBips == 0 || _amount*lenderFeeBips > PineLendingLibrary.INTEREST_PRECISION, "borrow amount too low");
    }

    function borrow(
        uint256[6] calldata x,
        bytes memory signature,
        bool proxy,
        address pineWallet
    ) external nonReentrant whenNotPaused returns (bool) {
        //valuation = x[0]
        //nftID = x[1]
        //uint256 loanDurationSeconds = x[2];
        //uint256 expireAtBlock = x[3];
        //uint256 borrowedAmount = x[4];
        address contextUser = proxy ? tx.origin : msg.sender;
        require(
            VerifySignaturePool02.verify(
                _supportedCollection,
                x[1],
                x[0],
                x[3],
                _valuationSigner,
                x[5],
                contextUser,
                signature
            ),
            "SignatureVerifier: fake valuation provided!"
        );
        IControlPlane01(_controlPlane).setUserNonce(x[5]);
        require(
            IControlPlane01(_controlPlane).whitelistedIntermediaries(
                msg.sender
            ) || msg.sender == tx.origin,
            "Phishing!"
        );
        require(
            !PineLendingLibrary.nftHasLoan(_loans[x[1]]),
            "NFT already has loan!"
        );
        uint32 maxLTVBPS = durationSeconds_poolParam[x[2]].collateralFactorBPS;
        require(maxLTVBPS > 0, "Duration not supported");

        uint256 pineMirrorID = uint256(
            keccak256(abi.encodePacked(_supportedCollection, x[1]))
        );

        if (pineWallet == (address(0))) {
            require(
                IERC721(_supportedCollection).ownerOf(x[1]) == contextUser,
                "Stealer1!"
            );
        } else {
            require(
                ICloneFactory02(
                    IControlPlane01(_controlPlane).whitelistedFactory()
                ).genuineClone(pineWallet),
                "Scammer!"
            );
            require(
                IERC721(pineWallet).ownerOf(pineMirrorID) == contextUser,
                "Stealer2!"
            );
        }

        require(block.number < x[3], "Valuation expired");
        require(
            x[4] <= (x[0] * maxLTVBPS) / PineLendingLibrary.ONE_HUNDRED_PERCENT_BPS,
            "Can't borrow more than max LTV"
        );
        require(
            x[4] < IERC20(_supportedCurrency).balanceOf(_fundSource),
            "not enough money"
        );

        uint32 protocolFeeBips = IControlPlane01(_controlPlane).feeBps();
        require(protocolFeeBips == 0 || (x[4] * (protocolFeeBips)) > PineLendingLibrary.ONE_HUNDRED_PERCENT_BPS, "borrow amount too low");
        uint256 protocolFee = (x[4] * (protocolFeeBips)) / (PineLendingLibrary.ONE_HUNDRED_PERCENT_BPS);

        updateBlockLoanAmount(x[4]);

        IERC20(_supportedCurrency).safeTransferFrom(
            _fundSource,
            msg.sender,
            x[4] - protocolFee
        );
        IERC20(_supportedCurrency).safeTransferFrom(
            _fundSource,
            _controlPlane,
            protocolFee
        );
        _loans[x[1]] = PineLendingLibrary.LoanTerms(
            block.number,
            block.timestamp + x[2],
            durationSeconds_poolParam[x[2]].interestBPS1000000XBlock,
            maxLTVBPS,
            x[4],
            0,
            0,
            0,
            contextUser
        );

        if (pineWallet == (address(0))) {
            IERC721(_supportedCollection).safeTransferFrom(
                contextUser,
                address(this),
                x[1]
            );
        } else {
            IERC721(pineWallet).safeTransferFrom(
                contextUser,
                address(this),
                pineMirrorID
            );
        }

        emit PineLendingLibrary.LoanInitiated(
            contextUser,
            _supportedCollection,
            x[1],
            _loans[x[1]]
        );
        return true;
    }

    /**
     * Repay
     */

    // repay change loan terms, renew loan start, fix interest to borrowed amount, dont renew loan expiry
    function repay(
        uint256 nftID,
        uint256 repayAmount,
        address pineWallet
    ) external nonReentrant whenNotPaused returns (bool) {
        uint256 pineMirrorID = uint256(
            keccak256(abi.encodePacked(_supportedCollection, nftID))
        );
        require(
            PineLendingLibrary.nftHasLoan(_loans[nftID]),
            "NFT does not have active loan"
        );
        IERC20(_supportedCurrency).safeTransferFrom(
            msg.sender,
            address(this),
            repayAmount
        );
        PineLendingLibrary.LoanTerms memory oldLoanTerms = _loans[nftID];

        if (repayAmount >= PineLendingLibrary.outstanding(_loans[nftID])) {
            IERC20(_supportedCurrency).safeTransfer(
                msg.sender,
                repayAmount - PineLendingLibrary.outstanding(_loans[nftID])
            );
            repayAmount = PineLendingLibrary.outstanding(_loans[nftID]);
            _loans[nftID].returnedWei = _loans[nftID].borrowedWei;
            if (pineWallet == address(0)) {
                IERC721(_supportedCollection).safeTransferFrom(
                    address(this),
                    _loans[nftID].borrower,
                    nftID
                );
            } else {
                require(
                    ICloneFactory02(
                        IControlPlane01(_controlPlane).whitelistedFactory()
                    ).genuineClone(pineWallet),
                    "Scammer!"
                );
                IERC721(pineWallet).safeTransferFrom(
                    address(this),
                    _loans[nftID].borrower,
                    pineMirrorID
                );
            }
            clearLoanTerms(nftID);
        } else {
            // lump in interest
            _loans[nftID].accuredInterestWei +=
                ((block.number - _loans[nftID].loanStartBlock) *
                    (_loans[nftID].borrowedWei - _loans[nftID].returnedWei) *
                    _loans[nftID].interestBPS1000000XBlock) /
                PineLendingLibrary.INTEREST_PRECISION;
            uint256 outstandingInterest = _loans[nftID].accuredInterestWei -
                _loans[nftID].repaidInterestWei;
            if (repayAmount > outstandingInterest) {
                _loans[nftID].repaidInterestWei = _loans[nftID]
                    .accuredInterestWei;
                _loans[nftID].returnedWei += (repayAmount -
                    outstandingInterest);
            } else {
                _loans[nftID].repaidInterestWei += repayAmount;
            }
            // restart interest calculation
            _loans[nftID].loanStartBlock = block.number;
        }
        
        IERC20(_supportedCurrency).safeTransferFrom(
            address(this),
            _fundSource,
            IERC20(_supportedCurrency).balanceOf(address(this))
        );
        emit PineLendingLibrary.LoanTermsChanged(
            _loans[nftID].borrower,
            _supportedCollection,
            nftID,
            oldLoanTerms,
            _loans[nftID]
        );
        return true;
    }

    /**
     * Admin functions
     */

    function withdraw(uint256 amount) external onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "cannot send ether");
    }

    function withdrawERC20(address currency, uint256 amount)
        external
        onlyOwner
    {
        IERC20(currency).safeTransfer(owner(), amount);
    }

    function withdrawERC721(
        address collection,
        uint256 nftID,
        address target,
        bool liquidation
    ) external {
        require(msg.sender == _controlPlane, "not control plane");
        if ((target == _supportedCollection) && liquidation) {
            PineLendingLibrary.LoanTerms memory lt = _loans[nftID];
            emit PineLendingLibrary.Liquidation(
                lt.borrower,
                _supportedCollection,
                nftID,
                block.timestamp,
                tx.origin
            );
            clearLoanTerms(nftID);
        }
        IERC721(collection).safeTransferFrom(address(this), target, nftID);
    }

    function clearLoanTerms(uint256 nftID) internal {
        _loans[nftID] = PineLendingLibrary.LoanTerms(
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            address(0)
        );
    }
}
