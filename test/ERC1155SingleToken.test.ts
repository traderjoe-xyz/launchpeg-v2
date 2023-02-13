import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ContractFactory, Contract, BigNumber, Bytes } from 'ethers'
import { config as hardhatConfig, ethers, network } from 'hardhat'
import { advanceTimeAndBlockToPhase, getDefaultLaunchpegConfig, Phase, LaunchpegConfig } from './utils/helpers'
import { advanceTimeAndBlock, latest, duration } from './utils/time'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'

describe.only('ERC1155SingleToken', () => {
  let launchpeg: Contract
  let config: LaunchpegConfig

  let dev: SignerWithAddress
  let alice: SignerWithAddress
  let bob: SignerWithAddress
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress
  let joeFeeCollector: SignerWithAddress

  const deployContractsFixture = async () => {
    const erc1155SingleTokenCF = await ethers.getContractFactory('ERC1155SingleToken')
    const erc1155SingleToken = await erc1155SingleTokenCF.deploy()

    const testConfig = await getDefaultLaunchpegConfig()

    await erc1155SingleToken.initialize(
      dev.address,
      royaltyReceiver.address,
      testConfig.joeFeePercent,
      testConfig.baseTokenURI,
      testConfig.collectionSize,
      testConfig.maxPerAddressDuringMint,
      '1155 Single Token',
      '1155-ST'
    )

    await erc1155SingleToken.initializePhases(
      testConfig.preMintStartTime,
      testConfig.publicSaleStartTime,
      testConfig.publicSaleEndTime,
      testConfig.flatAllowlistSalePrice,
      testConfig.flatPublicSalePrice
    )

    return { erc1155SingleToken, testConfig }
  }

  before(async () => {
    const signers = await ethers.getSigners()
    dev = signers[0]
    alice = signers[1]
    bob = signers[2]
    projectOwner = signers[3]
    royaltyReceiver = signers[4]
    joeFeeCollector = signers[5]
  })

  beforeEach(async () => {
    const { erc1155SingleToken, testConfig } = await loadFixture(deployContractsFixture)
    launchpeg = erc1155SingleToken
    config = testConfig
  })

  describe('Initialize ERC1155SingleToken', () => {
    it('Should be correctly initialized', async () => {
      expect(await launchpeg.maxSupply()).to.eq(config.collectionSize)
      expect(await launchpeg.maxPerAddressDuringMint()).to.eq(config.maxPerAddressDuringMint)

      expect(await launchpeg.preMintPrice()).to.eq(config.flatAllowlistSalePrice)
      expect(await launchpeg.publicSalePrice()).to.eq(config.flatPublicSalePrice)

      expect(await launchpeg.preMintStartTime()).to.eq(config.preMintStartTime)
      expect(await launchpeg.publicSaleStartTime()).to.eq(config.publicSaleStartTime)
      expect(await launchpeg.publicSaleEndTime()).to.eq(config.publicSaleEndTime)

      expect(await launchpeg.amountMintedByDevs()).to.eq(0)
      expect(await launchpeg.amountMintedDuringPreMint()).to.eq(0)
      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(0)
      expect(await launchpeg.amountMintedDuringPublicSale()).to.eq(0)
    })

    it("Can't be initialized twice", async () => {
      await expect(
        launchpeg.initialize(
          dev.address,
          royaltyReceiver.address,
          config.joeFeePercent,
          config.baseTokenURI,
          config.collectionSize,
          config.maxPerAddressDuringMint,
          '1155 Single Token',
          '1155-ST'
        )
      ).to.be.revertedWith('Initializable: contract is already initialized')
    })
  })

  describe('PreMint phase', () => {
    beforeEach(async () => {
      await advanceTimeAndBlockToPhase(Phase.PreMint)

      await launchpeg.seedAllowlist([alice.address], [3])
      await launchpeg.seedAllowlist([bob.address], [2])
    })

    it('Should be able to mint during pre-mint phase if user is on the allowlist', async () => {
      await launchpeg.connect(alice).preMint(3, { value: config.flatAllowlistSalePrice.mul(3) })
      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(3)
      expect(await launchpeg.amountMintedDuringPreMint()).to.eq(3)

      await launchpeg.connect(bob).preMint(1, { value: config.flatAllowlistSalePrice.mul(1) })
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(1)
      expect(await launchpeg.amountMintedDuringPreMint()).to.eq(4)
    })
  })

  describe.only('Claim PreMint', () => {
    beforeEach(async () => {
      await advanceTimeAndBlockToPhase(Phase.PreMint)

      await launchpeg.seedAllowlist([alice.address], [3])
      await launchpeg.seedAllowlist([bob.address], [2])
      await launchpeg.seedAllowlist([dev.address], [4])

      await launchpeg.connect(alice).preMint(3, { value: config.flatAllowlistSalePrice.mul(3) })
      await launchpeg.connect(bob).preMint(1, { value: config.flatAllowlistSalePrice.mul(1) })
      await launchpeg.connect(dev).preMint(4, { value: config.flatAllowlistSalePrice.mul(4) })

      await advanceTimeAndBlockToPhase(Phase.PublicSale)
    })

    it('Should be able to claim if preMinted', async () => {
      await launchpeg.connect(alice).claimPremint()
      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(3)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(3)
    })

    it('Should be able to batch claim', async () => {
      await launchpeg.connect(alice).claimPremint()

      await launchpeg.batchClaimPreMint(5)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(dev.address)).to.eq(0)

      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(8)
      expect(await launchpeg.balanceOf(bob.address, 0)).to.eq(1)
      expect(await launchpeg.balanceOf(dev.address, 0)).to.eq(4)
    })

    it('Should be able to claim all', async () => {
      await launchpeg.batchClaimPreMint(5)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(dev.address)).to.eq(0)

      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(8)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(3)
      expect(await launchpeg.balanceOf(bob.address, 0)).to.eq(1)
      expect(await launchpeg.balanceOf(dev.address, 0)).to.eq(4)
    })

    it('Should be able to batch mint a limited amount', async () => {
      await launchpeg.batchClaimPreMint(2)

      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(dev.address)).to.eq(0)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(3)
    })
  })
})
