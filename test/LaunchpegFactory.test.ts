import { config as hardhatConfig, ethers, network, upgrades } from 'hardhat'
import { expect } from 'chai'
import { getDefaultLaunchpegConfig, LaunchpegConfig } from './utils/helpers'
import { Bytes, ContractFactory, Contract } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('LaunchpegFactory', () => {
  let launchpegCF: ContractFactory
  let flatLaunchpegCF: ContractFactory
  let launchpegFactoryCF: ContractFactory
  let batchRevealCF: ContractFactory

  let launchpeg: Contract
  let flatLaunchpeg: Contract
  let launchpegFactory: Contract
  let batchReveal: Contract

  let config: LaunchpegConfig

  let signers: SignerWithAddress[]
  let dev: SignerWithAddress
  let alice: SignerWithAddress
  let bob: SignerWithAddress
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress

  let LAUNCHPEG_PAUSER_ROLE: Bytes

  before(async () => {
    launchpegCF = await ethers.getContractFactory('Launchpeg')
    flatLaunchpegCF = await ethers.getContractFactory('FlatLaunchpeg')
    launchpegFactoryCF = await ethers.getContractFactory('LaunchpegFactory')
    batchRevealCF = await ethers.getContractFactory('BatchReveal')

    signers = await ethers.getSigners()
    dev = signers[0]
    alice = signers[1]
    bob = signers[2]
    projectOwner = signers[3]
    royaltyReceiver = signers[4]

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
  })

  const deployBatchReveal = async () => {
    batchReveal = await batchRevealCF.deploy()
    await batchReveal.initialize()
  }

  const deployLaunchpeg = async () => {
    launchpeg = await launchpegCF.deploy()

    await launchpeg.initialize(
      'JoePEG',
      'JOEPEG',
      projectOwner.address,
      royaltyReceiver.address,
      config.maxBatchSize,
      config.collectionSize,
      config.amountForAuction,
      config.amountForAllowlist,
      config.amountForDevs
    )
  }

  const deployFlatLaunchpeg = async () => {
    flatLaunchpeg = await flatLaunchpegCF.deploy()

    await flatLaunchpeg.initialize(
      'JoePEG',
      'JOEPEG',
      projectOwner.address,
      royaltyReceiver.address,
      config.maxBatchSize,
      config.collectionSize,
      config.amountForDevs,
      config.amountForAllowlist
    )
  }

  const deployLaunchpegFactory = async () => {
    launchpegFactory = await upgrades.deployProxy(launchpegFactoryCF, [
      launchpeg.address,
      flatLaunchpeg.address,
      batchReveal.address,
      200,
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
          batchReveal.address,
          200,
          royaltyReceiver.address,
        ])
      ).to.be.revertedWith('LaunchpegFactory__InvalidImplementation()')

      await expect(
        upgrades.deployProxy(launchpegFactoryCF, [
          launchpeg.address,
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
        config.maxBatchSize,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs
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
        config.maxBatchSize,
        config.collectionSize,
        config.amountForDevs,
        config.amountForAllowlist
      )

      expect(await launchpegFactory.numLaunchpegs(1)).to.equal(1)
      const launchpegAddress = await launchpegFactory.allLaunchpegs(1, 0)
      expect(await launchpegFactory.isLaunchpeg(1, launchpegAddress)).to.equal(true)
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
        config.maxBatchSize,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs
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
        config.maxBatchSize,
        config.collectionSize,
        config.amountForAuction,
        config.amountForAllowlist,
        config.amountForDevs
      )
      const launchpegAddress = await launchpegFactory.allLaunchpegs(0, 0)
      const launchpeg = await ethers.getContractAt('Launchpeg', launchpegAddress)
      await launchpeg.connect(dev).becomeOwner()

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
