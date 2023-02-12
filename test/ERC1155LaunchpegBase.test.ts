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
    it('Should be correctly intialized', async () => {
      expect(await launchpegBase.owner()).to.eq(dev.address)
      expect(await launchpegBase.uri(0)).to.eq(config.baseTokenURI + '0')
      expect(await launchpegBase.name()).to.eq('1155 Single Token')
      expect(await launchpegBase.symbol()).to.eq('1155-ST')

      const royaltyInfo = await launchpegBase.royaltyInfo(0, 100)
      expect(royaltyInfo[0]).to.eq(royaltyReceiver.address)
      expect(royaltyInfo[1]).to.eq(5)
    })
  })
})
