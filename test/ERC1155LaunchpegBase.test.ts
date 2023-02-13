import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { ContractFactory, Contract, BigNumber, Bytes } from 'ethers'
import { config as hardhatConfig, ethers, network } from 'hardhat'
import { initializePhasesLaunchpeg, getDefaultLaunchpegConfig, Phase, LaunchpegConfig } from './utils/helpers'
import { advanceTimeAndBlock, latest, duration } from './utils/time'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'

describe.only('ERC1155LaunchpegBase', () => {
  let launchpegBase: Contract
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
      joeFeeCollector.address,
      testConfig.joeFeePercent,
      testConfig.baseTokenURI,
      testConfig.collectionSize,
      testConfig.flatPublicSalePrice,
      testConfig.preMintStartTime,
      testConfig.publicSaleStartTime,
      testConfig.publicSaleEndTime,
      '1155 Single Token',
      '1155-ST'
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
    launchpegBase = erc1155SingleToken
    config = testConfig
  })

  describe('Initialize ERC1155LaunchpegBase', () => {
    it('Should be correctly initialized', async () => {
      expect(await launchpegBase.owner()).to.eq(dev.address)
      expect(await launchpegBase.uri(0)).to.eq(config.baseTokenURI + '0')
      expect(await launchpegBase.name()).to.eq('1155 Single Token')
      expect(await launchpegBase.symbol()).to.eq('1155-ST')

      const royaltyInfo = await launchpegBase.royaltyInfo(0, 100)
      expect(royaltyInfo[0]).to.eq(royaltyReceiver.address)
      expect(royaltyInfo[1]).to.eq(5)

      expect(await launchpegBase.withdrawAVAXStartTime()).to.eq(config.publicSaleStartTime.add(duration.days(3)))
      expect(await launchpegBase.joeFeePercent()).to.eq(config.joeFeePercent)
      expect(await launchpegBase.joeFeeCollector()).to.eq(joeFeeCollector.address)

      expect(await launchpegBase.operatorFilterRegistry()).to.eq('0x000000000000AAeB6D7670E522A718067333cd4E')
      expect(await launchpegBase.hasRole(await launchpegBase.projectOwnerRole(), royaltyReceiver.address)).to.be.true
    })

    it("Can't be initialized twice", async () => {
      await expect(
        launchpegBase.initialize(
          dev.address,
          royaltyReceiver.address,
          joeFeeCollector.address,
          config.joeFeePercent,
          config.baseTokenURI,
          config.collectionSize,
          config.flatPublicSalePrice,
          config.preMintStartTime,
          config.publicSaleStartTime,
          config.publicSaleEndTime,
          '1155 Single Token',
          '1155-ST'
        )
      ).to.be.revertedWith('Initializable: contract is already initialized')
    })
  })

  describe('Configure ERC1155LaunchpegBase', () => {
    it('Should update the operatorFilterRegistry', async () => {
      await launchpegBase.setOperatorFilterRegistryAddress(alice.address)
      expect(await launchpegBase.operatorFilterRegistry()).to.eq(alice.address)

      await launchpegBase.setOperatorFilterRegistryAddress(ethers.constants.AddressZero)
      expect(await launchpegBase.operatorFilterRegistry()).to.eq(ethers.constants.AddressZero)

      await expect(launchpegBase.connect(bob).setOperatorFilterRegistryAddress(bob.address)).to.be.revertedWith(
        'PendingOwnableUpgradeable__NotOwner()'
      )
    })

    it('Should update the royalty infos', async () => {
      await launchpegBase.setRoyaltyInfo(alice.address, 1_000)
      const royaltyInfo = await launchpegBase.royaltyInfo(0, 100)
      expect(royaltyInfo[0]).to.eq(alice.address)
      expect(royaltyInfo[1]).to.eq(10)

      await expect(launchpegBase.setRoyaltyInfo(dev.address, 5_000)).to.be.revertedWith(
        'Launchpeg__InvalidRoyaltyInfo()'
      )

      await expect(launchpegBase.connect(bob).setRoyaltyInfo(bob.address, 10)).to.be.revertedWith(
        'PendingOwnableUpgradeable__NotOwner()'
      )
    })

    it('Should update the withdrawAVAXStartTime', async () => {
      await launchpegBase.setWithdrawAVAXStartTime(config.publicSaleStartTime.add(duration.days(7)))
      expect(await launchpegBase.withdrawAVAXStartTime()).to.eq(config.publicSaleStartTime.add(duration.days(7)))

      await expect(
        launchpegBase.connect(bob).setWithdrawAVAXStartTime(config.publicSaleStartTime.add(duration.days(7)))
      ).to.be.revertedWith('PendingOwnableUpgradeable__NotOwner()')
    })
  })
})
