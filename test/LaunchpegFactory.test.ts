import { config as hardhatConfig, ethers, network, upgrades } from 'hardhat'
import { expect } from 'chai'
import { getDefaultLaunchpegConfig, LaunchpegConfig } from './utils/helpers'
import { Bytes, ContractFactory, Contract } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe.only('LaunchpegFactory', () => {
  let launchpegCF: ContractFactory
  let flatLaunchpegCF: ContractFactory
  let erc1155SingleBundleCF: ContractFactory
  let launchpegFactoryCF: ContractFactory
  let batchRevealCF: ContractFactory

  let launchpeg: Contract
  let flatLaunchpeg: Contract
  let erc1155SingleBundle: Contract
  let launchpegFactory: Contract
  let batchReveal: Contract

  let config: LaunchpegConfig

  let signers: SignerWithAddress[]
  let dev: SignerWithAddress
  let alice: SignerWithAddress
  let bob: SignerWithAddress
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress
  let joeFeeCollector: SignerWithAddress

  let LAUNCHPEG_PAUSER_ROLE: Bytes

  before(async () => {
    launchpegCF = await ethers.getContractFactory('Launchpeg')
    flatLaunchpegCF = await ethers.getContractFactory('FlatLaunchpeg')
    erc1155SingleBundleCF = await ethers.getContractFactory('ERC1155SingleBundle')
    launchpegFactoryCF = await ethers.getContractFactory('LaunchpegFactory')
    batchRevealCF = await ethers.getContractFactory('BatchReveal')

    signers = await ethers.getSigners()
    dev = signers[0]
    alice = signers[1]
    bob = signers[2]
    projectOwner = signers[3]
    royaltyReceiver = signers[4]
    joeFeeCollector = signers[5]

    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          live: false,
          saveDeployments: true,
          tags: ['test', 'local'],
        },
      ],
    })

    config = await getDefaultLaunchpegConfig()
    await deployBatchReveal()
    await deployLaunchpeg()
    await deployFlatLaunchpeg()
    await deploy1155SingleBundle()
  })

  const deployBatchReveal = async () => {
    batchReveal = await batchRevealCF.deploy()
    await batchReveal.initialize()
  }

  const deployLaunchpeg = async () => {
    launchpeg = await launchpegCF.deploy()

    await launchpeg.initialize(
      [
        'JoePEG',
        'JOEPEG',
        batchReveal.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAuction,
        config.amountForAllowlist,
      ],
      [dev.address, projectOwner.address, royaltyReceiver.address, joeFeeCollector.address, config.joeFeePercent]
    )
  }

  const deployFlatLaunchpeg = async () => {
    flatLaunchpeg = await flatLaunchpegCF.deploy()

    await flatLaunchpeg.initialize(
      [
        'JoePEG',
        'JOEPEG',
        batchReveal.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        0,
        config.amountForAllowlist,
      ],
      [dev.address, projectOwner.address, royaltyReceiver.address, joeFeeCollector.address, config.joeFeePercent]
    )
  }

  const deploy1155SingleBundle = async () => {
    erc1155SingleBundle = await erc1155SingleBundleCF.deploy()
  }

  const deployLaunchpegFactory = async () => {
    launchpegFactory = await upgrades.deployProxy(launchpegFactoryCF, [
      launchpeg.address,
      flatLaunchpeg.address,
      erc1155SingleBundle.address,
      batchReveal.address,
      config.joeFeePercent,
      royaltyReceiver.address,
    ])
    await launchpegFactory.deployed()
  }

  beforeEach(async () => {
    await deployLaunchpegFactory()
  })

  describe('Initialisation', () => {
    it('Should block zero address implementation', async () => {
      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          ethers.constants.AddressZero,
          flatLaunchpeg.address,
          erc1155SingleBundle.address,
          batchReveal.address,
          200,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('LaunchpegFactory__InvalidImplementation()')

      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
          ethers.constants.AddressZero,
          erc1155SingleBundle.address,
          batchReveal.address,
          200,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('LaunchpegFactory__InvalidImplementation()')

      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
          flatLaunchpeg.address,
          ethers.constants.AddressZero,
          batchReveal.address,
          200,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('LaunchpegFactory__InvalidImplementation()')
    })

    it('Should revert with batch reveal zero address', async () => {
      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
          flatLaunchpeg.address,
          erc1155SingleBundle.address,
          ethers.constants.AddressZero,
          200,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('LaunchpegFactory__InvalidBatchReveal()')
    })

    it('Invalid default fees should be blocked', async () => {
      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
          flatLaunchpeg.address,
          erc1155SingleBundle.address,
          batchReveal.address,
          10_001,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('Launchpeg__InvalidPercent()')
    })

    it('Invalid fee collector should be blocked', async () => {
      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
          flatLaunchpeg.address,
          erc1155SingleBundle.address,
          batchReveal.address,
          200,
          ethers.constants.AddressZero,
        ])
      ).to.be.revertedWith('Launchpeg__InvalidJoeFeeCollector()')
    })
  })

  describe('Launchpeg creation', () => {
    it('Should increment the number of Launchpegs', async () => {
      expect(await launchpegFactory.numLaunchpegs(0)).to.equal(0)

      await launchpegFactory.createLaunchpeg(
        'JoePEG',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs,
        config.enableBatchReveal
      )

      expect(await launchpegFactory.numLaunchpegs(0)).to.equal(1)
      const launchpegAddress = await launchpegFactory.allLaunchpegs(0, 0)
      expect(await launchpegFactory.isLaunchpeg(0, launchpegAddress)).to.equal(true)
    })

    it('Should create FlatLaunchpegs as well', async () => {
      expect(await launchpegFactory.numLaunchpegs(1)).to.equal(0)

      await launchpegFactory.createFlatLaunchpeg(
        'JoePEG',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAllowlist,
        config.enableBatchReveal
      )

      expect(await launchpegFactory.numLaunchpegs(1)).to.equal(1)
      const launchpegAddress = await launchpegFactory.allLaunchpegs(1, 0)
      expect(await launchpegFactory.isLaunchpeg(1, launchpegAddress)).to.equal(true)
    })

    it('Should create ERC1155SingleBundle as well', async () => {
      expect(await launchpegFactory.numLaunchpegs(2)).to.equal(0)

      await launchpegFactory.create1155SingleToken(
        'JoePEG',
        'JOEPEG',
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAllowlist,
        [0],
        false
      )

      expect(await launchpegFactory.numLaunchpegs(2)).to.equal(1)
      const launchpegAddress = await launchpegFactory.allLaunchpegs(2, 0)
      expect(await launchpegFactory.isLaunchpeg(2, launchpegAddress)).to.equal(true)
    })

    it('Should correctly setup upgradeable ERC1155SingleBundle', async () => {
      expect(await launchpegFactory.numLaunchpegs(2)).to.equal(0)

      const tx = await launchpegFactory.create1155SingleToken(
        'JoePEG',
        'JOEPEG',
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAllowlist,
        [0],
        true
      )

      const receipt = await tx.wait()

      const logAdmin = receipt.events.find((e: { event: string }) => e.event === 'ProxyAdminFor1155Created').args
      const logLaunchpeg = receipt.events.find((e: { event: string }) => e.event === 'ERC1155SingleBundleCreated').args

      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', logAdmin.proxyAdmin)
      const erc1155SingleBundleProxy = await ethers.getContractAt(
        'ERC1155SingleBundle',
        logLaunchpeg.erc1155SingleBundle
      )

      expect(await proxyAdmin.owner()).to.eq(dev.address)
      expect(await erc1155SingleBundleProxy.owner()).to.eq(dev.address)
      expect(await proxyAdmin.getProxyImplementation(erc1155SingleBundleProxy.address)).to.eq(
        erc1155SingleBundle.address
      )
      expect(await proxyAdmin.getProxyAdmin(erc1155SingleBundleProxy.address)).to.eq(proxyAdmin.address)

      // Checks that the proxy is correctly initialized
      expect(await erc1155SingleBundleProxy.name()).to.eq('JoePEG')

      // Test to see if the proxy can be upgraded
      const newImplementation = await erc1155SingleBundleCF.deploy()
      await proxyAdmin.upgrade(erc1155SingleBundleProxy.address, newImplementation.address)

      expect(await proxyAdmin.getProxyImplementation(erc1155SingleBundleProxy.address)).to.eq(newImplementation.address)
      expect(await erc1155SingleBundleProxy.name()).to.eq('JoePEG')
    })

    it('Should not initialize batch reveal if disabled', async () => {
      await launchpegFactory.createLaunchpeg(
        'JoePEG',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs,
        false
      )

      const launchpegAddress = await launchpegFactory.allLaunchpegs(0, 0)
      const launchpeg = await ethers.getContractAt('Launchpeg', launchpegAddress)
      expect(await launchpeg.batchReveal()).to.equal(ethers.constants.AddressZero)

      await launchpegFactory.createFlatLaunchpeg(
        'JoePEG',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAllowlist,
        false
      )
      const flatLaunchpegAddress = await launchpegFactory.allLaunchpegs(1, 0)
      const flatLaunchpeg = await ethers.getContractAt('FlatLaunchpeg', flatLaunchpegAddress)
      expect(await flatLaunchpeg.batchReveal()).to.equal(ethers.constants.AddressZero)
    })
  })

  describe('Factory configuration', () => {
    it('Should set the new Launchpeg implementation', async () => {
      const newAddress = '0x44c14d53D7B7672d7fD6E4A97fDA1A5f68F62aB6'
      await launchpegFactory.setLaunchpegImplementation(newAddress)
      expect(await launchpegFactory.launchpegImplementation()).to.equal(newAddress)
      await expect(launchpegFactory.setLaunchpegImplementation(ethers.constants.AddressZero)).to.be.revertedWith(
        'LaunchpegFactory__InvalidImplementation()'
      )
    })

    it('Should set the new FlatLaunchpeg implementation', async () => {
      const newAddress = '0x44c14d53D7B7672d7fD6E4A97fDA1A5f68F62aB6'
      await launchpegFactory.setFlatLaunchpegImplementation(newAddress)
      expect(await launchpegFactory.flatLaunchpegImplementation()).to.equal(newAddress)
      await expect(launchpegFactory.setFlatLaunchpegImplementation(ethers.constants.AddressZero)).to.be.revertedWith(
        'LaunchpegFactory__InvalidImplementation()'
      )
    })

    it('Should set the new Batch Reveal contract', async () => {
      const newAddress = '0x44c14d53D7B7672d7fD6E4A97fDA1A5f68F62aB6'
      await launchpegFactory.setBatchReveal(newAddress)
      expect(await launchpegFactory.batchReveal()).to.equal(newAddress)
      await expect(launchpegFactory.setBatchReveal(ethers.constants.AddressZero)).to.be.revertedWith(
        'LaunchpegFactory__InvalidBatchReveal()'
      )
    })

    it('Should set the new fee configuration', async () => {
      const newFees = 499
      const newFeeCollector = bob.address

      await launchpegFactory.setDefaultJoeFeePercent(newFees)
      await launchpegFactory.setDefaultJoeFeeCollector(newFeeCollector)
      expect(await launchpegFactory.joeFeePercent()).to.equal(newFees)
      expect(await launchpegFactory.joeFeeCollector()).to.equal(newFeeCollector)

      await launchpegFactory.createLaunchpeg(
        'My new collection',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs,
        config.enableBatchReveal
      )
      const launchpeg0Address = await launchpegFactory.allLaunchpegs(0, 0)
      const launchpeg0 = await ethers.getContractAt('Launchpeg', launchpeg0Address)

      expect(await launchpeg0.joeFeePercent()).to.equal(newFees)
      expect(await launchpeg0.joeFeeCollector()).to.equal(newFeeCollector)

      await expect(launchpegFactory.setDefaultJoeFeePercent(20_000)).to.be.revertedWith('Launchpeg__InvalidPercent()')
      await expect(launchpegFactory.setDefaultJoeFeeCollector(ethers.constants.AddressZero)).to.be.revertedWith(
        'Launchpeg__InvalidJoeFeeCollector()'
      )
    })

    it('Should allow owner to add and remove Launchpeg pausers', async () => {
      LAUNCHPEG_PAUSER_ROLE = await launchpegFactory.LAUNCHPEG_PAUSER_ROLE()

      // Add multiple times
      await launchpegFactory.addLaunchpegPauser(alice.address)
      await launchpegFactory.addLaunchpegPauser(alice.address)
      expect(await launchpegFactory.hasRole(LAUNCHPEG_PAUSER_ROLE, alice.address)).to.eq(true)
      await launchpegFactory.addLaunchpegPauser(bob.address)
      expect(await launchpegFactory.hasRole(LAUNCHPEG_PAUSER_ROLE, bob.address)).to.eq(true)

      // Remove multiple times
      await launchpegFactory.removeLaunchpegPauser(bob.address)
      await launchpegFactory.removeLaunchpegPauser(bob.address)
      expect(await launchpegFactory.hasRole(LAUNCHPEG_PAUSER_ROLE, bob.address)).to.eq(false)
      expect(await launchpegFactory.hasRole(LAUNCHPEG_PAUSER_ROLE, alice.address)).to.eq(true)
    })

    it('Should allow owner or pauser to pause any Launchpeg collection', async () => {
      await launchpegFactory.createLaunchpeg(
        'My new collection',
        'JOEPEG',
        projectOwner.address,
        royaltyReceiver.address,
        config.maxPerAddressDuringMint,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs,
        config.enableBatchReveal
      )
      const launchpegAddress = await launchpegFactory.allLaunchpegs(0, 0)
      const launchpeg = await ethers.getContractAt('Launchpeg', launchpegAddress)

      await launchpegFactory.pauseLaunchpeg(launchpegAddress)
      expect(await launchpeg.paused()).to.eq(true)
      await launchpeg.unpause()

      await launchpegFactory.addLaunchpegPauser(alice.address)
      await launchpegFactory.connect(alice).pauseLaunchpeg(launchpegAddress)
      expect(await launchpeg.paused()).to.eq(true)
      await expect(launchpeg.connect(alice).unpause()).to.be.revertedWith(
        'SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner'
      )
      await launchpeg.unpause()

      await expect(launchpegFactory.connect(bob).pauseLaunchpeg(launchpegAddress)).to.be.revertedWith(
        'SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner'
      )
      await launchpegFactory.addLaunchpegPauser(bob.address)
      await launchpegFactory.removeLaunchpegPauser(alice.address)
      await expect(launchpegFactory.connect(alice).pauseLaunchpeg(launchpegAddress)).to.be.revertedWith(
        'SafeAccessControlEnumerableUpgradeable__SenderMissingRoleAndIsNotOwner'
      )
      await launchpegFactory.connect(bob).pauseLaunchpeg(launchpegAddress)
      expect(await launchpeg.paused()).to.eq(true)
    })
  })

  after(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    })
  })
})
