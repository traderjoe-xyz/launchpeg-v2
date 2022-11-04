import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { BigNumber, Contract, ContractFactory } from 'ethers'
import { config as hardhatConfig, ethers, network, upgrades } from 'hardhat'
import { Address } from 'hardhat-deploy/types'
import { getDefaultLaunchpegConfig, LaunchpegConfig } from './utils/helpers'

// skip LaunchpegLens test suite
describe.skip('LaunchpegLens', function () {
  const launchpegFactoryV1Address: Address = '0x7bfd7192e76d950832c77bb412aae841049d8d9b'

  let launchpegCF: ContractFactory
  let flatLaunchpegCF: ContractFactory
  let launchpegFactoryCF: ContractFactory
  let batchRevealCF: ContractFactory
  let lensCF: ContractFactory

  let launchpegImpl: Contract
  let flatLaunchpegImpl: Contract
  let launchpegFactory: Contract
  let batchReveal: Contract
  let lens: Contract

  let config: LaunchpegConfig

  let signers: SignerWithAddress[]
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress

  before(async () => {
    launchpegCF = await ethers.getContractFactory('Launchpeg')
    flatLaunchpegCF = await ethers.getContractFactory('FlatLaunchpeg')
    launchpegFactoryCF = await ethers.getContractFactory('LaunchpegFactory')
    batchRevealCF = await ethers.getContractFactory('BatchReveal')
    lensCF = await ethers.getContractFactory('LaunchpegLens')

    signers = await ethers.getSigners()
    projectOwner = signers[3]
    royaltyReceiver = signers[4]

    const rpcConfig: any = hardhatConfig.networks.avalanche
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: rpcConfig.url,
          },
          live: false,
          saveDeployments: true,
          tags: ['test', 'local'],
        },
      ],
    })

    const setUp = async () => {
      config = await getDefaultLaunchpegConfig()

      batchReveal = await batchRevealCF.deploy()
      await batchReveal.initialize()
      launchpegImpl = await launchpegCF.deploy()
      flatLaunchpegImpl = await flatLaunchpegCF.deploy()

      launchpegFactory = await upgrades.deployProxy(launchpegFactoryCF, [
        launchpegImpl.address,
        flatLaunchpegImpl.address,
        batchReveal.address,
        config.joeFeePercent,
        royaltyReceiver.address,
      ])
      await launchpegFactory.deployed()

      lens = await lensCF.deploy(launchpegFactoryV1Address, launchpegFactory.address, batchReveal.address)
    }

    await setUp()
  })

  const createLaunchpeg = async (enableBatchReveal = true) => {
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
      enableBatchReveal
    )
  }

  const createFlatLaunchpeg = async (enableBatchReveal = true) => {
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
  }

  const configureBatchReveal = async (launchpegAddress: Address) => {
    await batchReveal.configure(
      launchpegAddress,
      config.batchRevealSize,
      config.batchRevealStart,
      config.batchRevealInterval
    )
  }

  describe('LaunchpegV1 data', async () => {
    const lpAddress: Address = '0x5C1890eBB39014975b3981febff2A43420CEf76d'
    const flpAddress: Address = '0xC70DF87e1d98f6A531c8E324C9BCEC6FC82B5E8d'

    it('Should return Launchpeg type and version', async () => {
      expect(await lens.getLaunchpegType(lpAddress)).to.eql([1, 1])
      expect(await lens.getLaunchpegType(flpAddress)).to.eql([2, 1])
    })

    it('Should return all Launchpegs by type and version', async () => {
      const launchpegType = 0
      const flatLaunchpegType = 1
      const version = 1
      const numEntries = 1
      const user = ethers.constants.AddressZero

      let lastIdx = 1
      let lensDataArr = await lens.getLaunchpegsByTypeAndVersion(launchpegType, version, numEntries, lastIdx, user)
      let lpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(1)
      expect(lpAddresses).to.eql([lpAddress])

      lensDataArr = await lens.getLaunchpegsByTypeAndVersion(flatLaunchpegType, version, numEntries, 2, user)
      let flpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(1)
      expect(flpAddresses).to.eql([flpAddress])
    })

    it('Should return Launchpeg data', async () => {
      const launchpegType = 1
      const flatLaunchpegType = 2
      const user = ethers.constants.AddressZero

      let lensData = await lens.getLaunchpegData(lpAddress, user)
      expect(lensData.id).to.eq(lpAddress)
      expect(lensData.launchType).to.eq(launchpegType)
      expect(lensData.collectionData.name).to.eq('MUAFNFT')
      expect(lensData.revealData.revealBatchSize).to.eq(7)

      lensData = await lens.getLaunchpegData(flpAddress, user)
      expect(lensData.id).to.eq(flpAddress)
      expect(lensData.launchType).to.eq(flatLaunchpegType)
      expect(lensData.collectionData.name).to.eq('Smol Joes')
      expect(lensData.revealData.revealBatchSize).to.eq(100)
    })
  })

  describe('LaunchpegV2 data', async () => {
    let lpWithReveal: Address
    let lpWithoutReveal: Address
    let flpWithReveal: Address
    let flpWithoutReveal: Address

    const expectLensDataEqual = (
      lensData: any,
      launchpegAddress: Address,
      launchpegType: number,
      isBatchRevealEnabled: boolean
    ) => {
      const {
        id,
        launchType,
        collectionData,
        launchpegData,
        flatLaunchpegData,
        revealData,
        userData,
        projectOwnerData,
      } = lensData
      expect(id).to.eq(launchpegAddress)
      expect(launchType).to.eq(launchpegType)
      expect(collectionData.name).to.eq('JoePEG')
      if (launchpegType == 1) {
        expect(launchpegData.currentPhase).to.eq(0)
      } else if (launchpegType == 2) {
        expect(flatLaunchpegData.currentPhase).to.eq(0)
      }
      if (isBatchRevealEnabled) {
        expect(revealData.revealBatchSize).to.eq(config.batchRevealSize)
      } else {
        expect(revealData.revealBatchSize).to.eq(0)
      }
      expect(userData.balanceOf).to.eq(0)
      expect(projectOwnerData.projectOwners).to.eql([projectOwner.address])
    }

    before(async () => {
      await createLaunchpeg(true)
      lpWithReveal = await launchpegFactory.allLaunchpegs(0, 0)
      await configureBatchReveal(lpWithReveal)

      await createLaunchpeg(false)
      lpWithoutReveal = await launchpegFactory.allLaunchpegs(0, 1)

      await createFlatLaunchpeg(true)
      flpWithReveal = await launchpegFactory.allLaunchpegs(1, 0)
      await configureBatchReveal(flpWithReveal)

      await createFlatLaunchpeg(false)
      flpWithoutReveal = await launchpegFactory.allLaunchpegs(1, 1)
    })

    it('Should return Launchpeg type and version', async () => {
      expect(await lens.getLaunchpegType(lpWithReveal)).to.eql([1, 2])
      expect(await lens.getLaunchpegType(lpWithoutReveal)).to.eql([1, 2])
      expect(await lens.getLaunchpegType(flpWithReveal)).to.eql([2, 2])
      expect(await lens.getLaunchpegType(flpWithoutReveal)).to.eql([2, 2])
    })

    it('Should return all Launchpegs by type and version', async () => {
      const launchpegType = 0
      const flatLaunchpegType = 1
      const version = 2
      const numEntries = 4
      const lastIdx = 4
      const user = ethers.constants.AddressZero

      let lensDataArr = await lens.getLaunchpegsByTypeAndVersion(launchpegType, version, numEntries, lastIdx, user)
      let lpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(2)
      expect(lpAddresses).to.eql([lpWithoutReveal, lpWithReveal])

      lensDataArr = await lens.getLaunchpegsByTypeAndVersion(flatLaunchpegType, version, numEntries, lastIdx, user)
      let flpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(2)
      expect(flpAddresses).to.eql([flpWithoutReveal, flpWithReveal])
    })

    it('Should return Launchpeg data', async () => {
      const launchpegType = 1
      const flatLaunchpegType = 2
      const user = ethers.constants.AddressZero

      let lensData = await lens.getLaunchpegData(lpWithReveal, user)
      expectLensDataEqual(lensData, lpWithReveal, launchpegType, true)

      lensData = await lens.getLaunchpegData(lpWithoutReveal, user)
      expectLensDataEqual(lensData, lpWithoutReveal, launchpegType, false)

      lensData = await lens.getLaunchpegData(flpWithReveal, user)
      expectLensDataEqual(lensData, flpWithReveal, flatLaunchpegType, true)

      lensData = await lens.getLaunchpegData(flpWithoutReveal, user)
      expectLensDataEqual(lensData, flpWithoutReveal, flatLaunchpegType, false)
    })
  })

  after(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    })
  })
})
