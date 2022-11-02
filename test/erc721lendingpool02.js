const Lending = artifacts.require("ERC721LendingPool02")
const ERC721 = artifacts.require("Doodles")
const ControlPlane = artifacts.require("ControlPlane01")
const CloneFactory = artifacts.require("CloneFactory02")
const LandRover = artifacts.require("LandRover01")
const WETH = artifacts.require("WETH9")
const PineLendingLibrary = artifacts.require("PineLendingLibrary")
const VerifyLibrary = artifacts.require("VerifySignaturePool02")
const VerifyContract = artifacts.require("VerifySignaturePool02Contract")
const BN = require('bn.js')

contract("ERC721 Lending", async accounts => {
  /*
  9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de: lender
  accounts[1]: borrower

  */
  before(async () => {
    library = await PineLendingLibrary.new()
    vLib = await VerifyLibrary.new()
    vContract = await VerifyContract.new()
    await Lending.link('PineLendingLibrary', library.address);
    await Lending.link('VerifySignaturePool02', vLib.address)
    await ControlPlane.link('PineLendingLibrary', library.address);
    lender_pkey = "9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de"
    lender_address = "0xf31EEB5433cE3F307d20D07Ac0329Da857eEb485"

    // Deploy
    nft = await ERC721.new()
    nft2 = await ERC721.new()
    weth = await WETH.new()
    control_plane = await ControlPlane.new()
    clone_factory = await CloneFactory.new()
    lending = await Lending.new()

    flash_loan_pool = await Lending.new()

    loan_rover = await LandRover.new(weth.address)


    // Init
    await nft.setSaleState(true)
    await control_plane.setWhitelistedFactory(clone_factory.address)
    // await loan_rover.approvePool(weth.address, lending.address, '999999999999999999009999999999999999999999999')
    await control_plane.toggleWhitelistedIntermediaries(loan_rover.address)
    await clone_factory.toggleWhitelistedTarget(lending.address)
    lending = await clone_factory.createClone(lending.address, '847662837')
    lending = await Lending.at(lending.logs[0].args.result)
    // (address supportedCollection, address valuationSigner, address controlPlane, address supportedCurrency, address fundSource)
    await flash_loan_pool.initialize(nft.address, lender_address, control_plane.address, weth.address, accounts[7])
    await lending.initialize(nft.address, lender_address, control_plane.address, weth.address, accounts[5])
    await lending.setDurationParam(15, [1000, 3000])
    await weth.deposit({ from: accounts[1], value: "10000000000000000000" })
    await weth.deposit({ from: accounts[5], value: "10000000000000000000" })
    await weth.deposit({ from: accounts[7], value: "10000000000000000000" })
    await weth.approve(lending.address, "10000000000000000000", { from: accounts[5] })
    await weth.approve(flash_loan_pool.address, "10000000000000000000", { from: accounts[7] })
    // Funding
    // web3.eth.sendTransaction({ from: accounts[20], to: lending.address, value: web3.utils.toWei("1", "ether") })
    // web3.eth.sendTransaction({ from: accounts[20], to: flash_loan_pool.address, value: web3.utils.toWei("1", "ether") })
    console.log(lending.address)
    console.log(flash_loan_pool.address)
    console.log(loan_rover.address)
    /*
      uint256 valuation = x[0];
      uint256 nftID = x[1];
      uint256 loanDurationSeconds = x[20];
      uint256 expireAtBlock = x[3];
      uint256 borrowedAmount = x[4];
    */
    lending_params = [100000000000, 1, 15, 200, 30000000000, 0]
    /*
      address nft,
      uint punkID,
      uint valuation,
      uint expireAtBlock
    */

    valuation_hash = await vContract.getMessageHash(nft.address, lending_params[1], lending_params[0], lending_params[3], lending_params[5], accounts[1])

    signed_valuation_hash = await web3.eth.accounts.sign(valuation_hash, lender_pkey)

    lending_params2 = [100000000000, 2, 15, 200, 30000000000, 1]
    /*
      address nft,
      uint punkID,
      uint valuation,
      uint expireAtBlock
    */

    valuation_hash2 = await vContract.getMessageHash(nft.address, lending_params2[1], lending_params2[0], lending_params2[3], lending_params2[5], accounts[1])

    signed_valuation_hash2 = await web3.eth.accounts.sign(valuation_hash2, lender_pkey)
  });

  it("should approve the contract for spending NFTs", async () => {
    await nft.setApprovalForAll(lending.address, true, { from: accounts[1] })
  })

  it("should mint NFTs", async () => {
    await nft.mint(5, { from: accounts[1], value: 1000000000000000000 })
    await nft.safeTransferFrom(accounts[1], lending.address, 4, { from: accounts[1] })
  })

  // it("should not borrow more than what it could", async () => {
  //   try {
  //     await lending.borrow(lending_params, signed_valuation_hash.signature, false, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
      
  //     assert(false)
  //   } catch (e) {
  //     console.log(e)
  //     console.log('here')
  //     assert(e)
  //   }
  // })

  it("should not supply fake valuation", async () => {
    try {
      params = { ...lending_params }
      params[0] = 8988888888888888
      params[4] = 8988888888888888
      await lending.borrow(params, signed_valuation_hash.signature, false, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    } catch (e) {
      assert(e)
    }
  })

  it("should borrow some money and the NFT is located in the contract", async () => {
    console.log(lending_params)
    const prev_balance = await web3.eth.getBalance(accounts[1])
    const receipt = await lending.borrow(lending_params, signed_valuation_hash.signature, false, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    const gasUsed = receipt.receipt.gasUsed;
    assert.equal(lending.address, await nft.ownerOf(lending_params[1]))
  })

  it("should borrow some money and the NFT is located in the contract (nftid 2)", async () => {
    const receipt = await lending.borrow(lending_params2, signed_valuation_hash2.signature, false, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    assert.equal(lending.address, await nft.ownerOf(lending_params[1]))
  })

  it("should return part of the money (eating into principal)", async () => {
    await weth.approve(lending.address, '100000000000000000000000000', { from: accounts[1] })
    await lending.repay(lending_params[1], 10000009000, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    assert.equal(lending.address, await nft.ownerOf(lending_params[1]))
    //assert.equal(20000000000, await lending.outstanding(lending_params[1]))
  })

  // it("should rollover", async () => {
  //   const loan = await lending._loans(lending_params[1])
  //   const loan_iter = []
  //   for (x of [0, 1, 2, 3, 4, 5, 6, 7]) {
  //     loan_iter.push(loan[x].toString())
  //   }
  //   console.log(JSON.stringify(loan_iter))
  //   outstanding = await control_plane.outstanding([...loan_iter, loan[8]]) + 50000
  //   console.log(outstanding)
  //   let y = await loan_rover.rover(nft.address, flash_loan_pool.address, lending.address, [...lending_params, outstanding], signed_valuation_hash.signature, '0x0000000000000000000000000000000000000000', { from: accounts[1], value: 1000000000000 })
  //   assert.equal(lending.address, await nft.ownerOf(lending_params[1]))
  //   //console.log(y)
  // })

  it("should return part of the money (doesn't eat into principal)", async () => {
    await lending.repay(lending_params[1], 100, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    assert.equal(lending.address, await nft.ownerOf(lending_params[1]))
  })

  it("admin should withdraw nfts", async () => {
    await control_plane.withdrawNFT(lending.address, nft.address, 4)
  })

  it("admin should not withdraw nfts on lien", async () => {
    try {
      await control_plane.withdrawNFT(lending.address, nft.address, lending_params[1])
    } catch (e) {
      assert(e)
    }

  })
  it("should not let people steal NFTs", async () => {
    try {
      await nft.safeTransferFrom(lending.address, accounts[5], lending_params[1])
    } catch (e) {
      assert(e)
    }
  })

  it("should return all of the money", async () => {
    const loan = await lending._loans(lending_params[1])
    const loan_iter = []
    for (x of [0, 1, 2, 3, 4, 5, 6, 7]) {
      loan_iter.push(loan[x].toString())
    }
    console.log((await weth.balanceOf(accounts[1])).toString())
    console.log(await control_plane.outstanding([...loan_iter, loan[8]]) + 1001)
    await lending.repay(lending_params[1], (await control_plane.outstanding([...loan_iter, loan[8]])) + 1001, '0x0000000000000000000000000000000000000000', { from: accounts[1] })
    assert.equal(accounts[1], await nft.ownerOf(lending_params[1]))
  })

  it("admin should withdraw proceeds", async () => {
    const prev_balance = await web3.eth.getBalance(lending.address)
    console.log((await web3.eth.getBalance(accounts[0])).toString())
    await lending.withdraw(prev_balance)
    console.log((await web3.eth.getBalance(accounts[0])).toString())
  })

  it("should not be liquidated when not expired", async () => {
    try {
      await control_plane.liquidateNFT(lending.address, 2)
    } catch (e) {
      console.log(e)
      assert(e)
    }

    assert.equal(lending.address, await nft.ownerOf(2))
  })

  function delay(t, val) {
    return new Promise(function (resolve) {
      setTimeout(function () {
        resolve(val);
      }, t);
    });
  }

  it("should not be liquidated by non-pool-owner when expired", async () => {
    await delay(15000)
    try {
      await control_plane.liquidateNFT(lending.address, 2, {from: accounts[8]})
    } catch (e) {
      console.log(e)
      assert(e)
    }
  })

  it("should be liquidated by pool-owner when expired", async () => {
    await control_plane.liquidateNFT(lending.address, 2)
    assert.equal(accounts[0], await nft.ownerOf(2))
  })
});

