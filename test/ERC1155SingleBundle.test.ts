import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ContractFactory, Contract, BigNumber, Bytes } from 'ethers'
import { config as hardhatConfig, ethers, network } from 'hardhat'
import { advanceTimeAndBlockToPhase, getDefaultLaunchpegConfig, Phase, LaunchpegConfig } from './utils/helpers'
import { advanceTimeAndBlock, latest, duration } from './utils/time'
import { loadFixture, mine, reset, time } from '@nomicfoundation/hardhat-network-helpers'

describe('ERC1155SingleBundle', () => {
  let launchpeg: Contract
  let config: LaunchpegConfig

  let dev: SignerWithAddress
  let alice: SignerWithAddress
  let bob: SignerWithAddress
  let carol: SignerWithAddress
  let royaltyReceiver: SignerWithAddress
  let joeFeeCollector: SignerWithAddress

  const deployContractsFixture = async () => {
    const erc1155SingleBundleCF = await ethers.getContractFactory('ERC1155SingleBundle')
    const erc1155SingleBundle = await erc1155SingleBundleCF.deploy()

    const testConfig = await getDefaultLaunchpegConfig()

    await erc1155SingleBundle.initialize(
      dev.address,
      royaltyReceiver.address,
      testConfig.joeFeePercent,
      testConfig.baseTokenURI,
      testConfig.collectionSize,
      testConfig.amountForDevs,
      testConfig.amountForAllowlist,
      testConfig.maxPerAddressDuringMint,
      '1155 Single Token',
      '1155-ST'
    )

    await erc1155SingleBundle.initializePhases(
      testConfig.preMintStartTime,
      testConfig.publicSaleStartTime,
      testConfig.publicSaleEndTime,
      testConfig.flatAllowlistSalePrice,
      testConfig.flatPublicSalePrice
    )

    return { erc1155SingleBundle, testConfig }
  }

  before(async () => {
    const signers = await ethers.getSigners()
    dev = signers[0]
    alice = signers[1]
    bob = signers[2]
    carol = signers[3]
    royaltyReceiver = signers[4]
    joeFeeCollector = signers[5]
  })

  beforeEach(async () => {
    const { erc1155SingleBundle, testConfig } = await loadFixture(deployContractsFixture)
    launchpeg = erc1155SingleBundle
    config = testConfig
  })

  describe('Initialize Contract', () => {
    it('Should be correctly initialized', async () => {
      expect(await launchpeg.maxSupply()).to.eq(config.collectionSize)
      expect(await launchpeg.amountForDevs()).to.eq(config.amountForDevs)
      expect(await launchpeg.amountForPreMint()).to.eq(config.amountForAllowlist)
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
          config.amountForDevs,
          config.amountForAllowlist,
          config.maxPerAddressDuringMint,
          '1155 Single Token',
          '1155-ST'
        )
      ).to.be.revertedWith('Initializable: contract is already initialized')
    })
  })

  describe('Dev mint', () => {
    it('Dev should be able to mint their allocation anytime', async () => {
      await launchpeg.devMint(config.amountForDevs)

      expect(await launchpeg.amountMintedByDevs()).to.eq(config.amountForDevs)
      expect(await launchpeg.balanceOf(dev.address, 0)).to.eq(config.amountForDevs)
    })

    it('Dev should not be able to mint more than their allocation', async () => {
      await expect(launchpeg.devMint(config.amountForDevs + 1)).to.be.revertedWith(
        'Launchpeg__MaxSupplyForDevReached()'
      )
    })

    it("Non project owners can't mint dev allocation", async () => {
      await expect(launchpeg.connect(alice).devMint(config.amountForDevs)).to.be.revertedWith(
        'SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner'
      )

      await launchpeg.grantRole(await launchpeg.projectOwnerRole(), alice.address)
      await launchpeg.connect(alice).devMint(config.amountForDevs)

      expect(await launchpeg.amountMintedByDevs()).to.eq(config.amountForDevs)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(config.amountForDevs)
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
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(1)

      await launchpeg.connect(bob).preMint(1, { value: config.flatAllowlistSalePrice.mul(1) })
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(1)
      expect(await launchpeg.amountMintedDuringPreMint()).to.eq(4)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(2)
    })
  })

  describe('Claim PreMint', () => {
    beforeEach(async () => {
      await advanceTimeAndBlockToPhase(Phase.PreMint)

      await launchpeg.seedAllowlist([alice.address], [3])
      await launchpeg.seedAllowlist([bob.address], [2])
      await launchpeg.seedAllowlist([carol.address], [4])

      await launchpeg.connect(alice).preMint(3, { value: config.flatAllowlistSalePrice.mul(3) })
      await launchpeg.connect(bob).preMint(1, { value: config.flatAllowlistSalePrice.mul(1) })
      await launchpeg.connect(carol).preMint(4, { value: config.flatAllowlistSalePrice.mul(4) })

      await advanceTimeAndBlockToPhase(Phase.PublicSale)
    })

    it('Should be able to claim if preMinted', async () => {
      await launchpeg.connect(alice).claimPremint()
      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(3)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(2)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(3)
    })

    it('Should be able to claim all', async () => {
      await launchpeg.batchClaimPreMint(20)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(carol.address)).to.eq(0)

      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(8)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(0)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(3)
      expect(await launchpeg.balanceOf(bob.address, 0)).to.eq(1)
      expect(await launchpeg.balanceOf(carol.address, 0)).to.eq(4)
    })

    it('Should be able to batch mint a limited amount', async () => {
      await launchpeg.batchClaimPreMint(2)

      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(carol.address)).to.eq(0)
      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(5)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(1)
      expect(await launchpeg.balanceOf(bob.address, 0)).to.eq(1)
      expect(await launchpeg.balanceOf(carol.address, 0)).to.eq(4)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(3)
    })

    it('Should be able to combine individuals claims with batchClaim', async () => {
      await launchpeg.connect(alice).claimPremint()
      await launchpeg.batchClaimPreMint(1)

      expect(await launchpeg.userPendingPreMints(alice.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(bob.address)).to.eq(0)
      expect(await launchpeg.userPendingPreMints(carol.address)).to.eq(4)

      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(4)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(1)

      await launchpeg.connect(carol).claimPremint()

      expect(await launchpeg.userPendingPreMints(carol.address)).to.eq(0)
      expect(await launchpeg.amountClaimedDuringPreMint()).to.eq(8)
      expect(await launchpeg.amountOfUsersWaitingForPremint()).to.eq(0)
    })
  })

  describe('Public Sale', () => {
    beforeEach(async () => {
      await advanceTimeAndBlockToPhase(Phase.PublicSale)
    })

    it('Should be able to mint during public sale', async () => {
      await launchpeg.connect(alice).publicSaleMint(2, { value: config.flatPublicSalePrice.mul(2) })
      expect(await launchpeg.amountMintedDuringPublicSale()).to.eq(2)
      expect(await launchpeg.balanceOf(alice.address, 0)).to.eq(2)

      await launchpeg.connect(bob).publicSaleMint(1, { value: config.flatPublicSalePrice.mul(1) })
      expect(await launchpeg.amountMintedDuringPublicSale()).to.eq(3)
      expect(await launchpeg.balanceOf(bob.address, 0)).to.eq(1)
    })
  })

  describe('Claim Funds', () => {
    beforeEach(async () => {
      await advanceTimeAndBlockToPhase(Phase.PublicSale)

      await launchpeg.connect(alice).publicSaleMint(10, { value: config.flatPublicSalePrice.mul(10) })
    })

    it('Should be able to claim funds', async () => {
      await advanceTimeAndBlock(duration.days(3))

      const totalProceeds = config.flatPublicSalePrice.mul(10)

      const ownerBalanceBefore = await ethers.provider.getBalance(royaltyReceiver.address)
      const joeFeeReceiverBalanceBefore = await ethers.provider.getBalance(dev.address)

      await launchpeg.connect(royaltyReceiver).withdrawAVAX(royaltyReceiver.address)

      const ownerBalanceAfter = await ethers.provider.getBalance(royaltyReceiver.address)
      const joeFeeReceiverBalanceAfter = await ethers.provider.getBalance(dev.address)

      expect(ownerBalanceAfter.sub(ownerBalanceBefore)).to.be.closeTo(
        totalProceeds.sub(totalProceeds.mul(config.joeFeePercent).div(10_000)),
        ethers.utils.parseEther('0.0001')
      )
      expect(joeFeeReceiverBalanceAfter.sub(joeFeeReceiverBalanceBefore)).to.be.closeTo(
        totalProceeds.mul(config.joeFeePercent).div(10_000),
        ethers.utils.parseEther('0.0001')
      )
    })

    it("Should not be able to claim funds if it's not a project owner", async () => {
      await expect(launchpeg.connect(alice).withdrawAVAX(alice.address)).to.be.revertedWith(
        'SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner'
      )
    })

    it('Should not be able to withdraw the funds before the withdraw period', async () => {
      await expect(launchpeg.connect(royaltyReceiver).withdrawAVAX(royaltyReceiver.address)).to.be.revertedWith(
        'Launchpeg__WithdrawAVAXNotAvailable'
      )
    })
  })
})
