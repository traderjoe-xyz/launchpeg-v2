import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { Contract, ContractFactory } from 'ethers'
import { config as hardhatConfig, ethers, network, upgrades } from 'hardhat'
import { getDefaultLaunchpegConfig, LaunchpegConfig } from './utils/helpers'

describe('LaunchpegLens', function () {
  const LAUNCHPEG_TYPE = 1
  const FLAT_LAUNCHPEG_TYPE = 2
  const ERC1155_SINGLE_BUNDLE_TYPE = 3

  const launchpegFactoryV1Address: string = '0x7BFd7192E76D950832c77BB412aaE841049D8D9B'

  let launchpegCF: ContractFactory
  let flatLaunchpegCF: ContractFactory
  let erc1155SingleBundleCF: ContractFactory
  let launchpegFactoryCF: ContractFactory
  let batchRevealCF: ContractFactory
  let lensCF: ContractFactory

  let launchpegImpl: Contract
  let flatLaunchpegImpl: Contract
  let erc1155SingleBundleImpl: Contract
  let launchpegFactory: Contract
  let batchReveal: Contract
  let lens: Contract

  let config: LaunchpegConfig

  let signers: SignerWithAddress[]
  let alice: SignerWithAddress
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress

  before(async () => {
    launchpegCF = await ethers.getContractFactory('Launchpeg')
    flatLaunchpegCF = await ethers.getContractFactory('FlatLaunchpeg')
    erc1155SingleBundleCF = await ethers.getContractFactory('ERC1155SingleBundle')
    launchpegFactoryCF = await ethers.getContractFactory('LaunchpegFactory')
    batchRevealCF = await ethers.getContractFactory('BatchReveal')
    lensCF = await ethers.getContractFactory('LaunchpegLens')

    signers = await ethers.getSigners()
    alice = signers[0]
    projectOwner = signers[1]
    royaltyReceiver = signers[2]

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
      erc1155SingleBundleImpl = await erc1155SingleBundleCF.deploy()

      launchpegFactory = await upgrades.deployProxy(launchpegFactoryCF, [
        launchpegImpl.address,
        flatLaunchpegImpl.address,
        erc1155SingleBundleImpl.address,
        batchReveal.address,
        config.joeFeePercent,
        royaltyReceiver.address,
      ])
      await launchpegFactory.deployed()

      lens = await lensCF.deploy(launchpegFactoryV1Address, launchpegFactory.address, batchReveal.address)
    }

    await setUp()
  })

  const createLaunchpeg = async (enableBatchReveal: boolean) => {
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

  const createFlatLaunchpeg = async (enableBatchReveal: boolean) => {
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

  const create1155SingleBundle = async () => {
    await launchpegFactory.create1155SingleToken(
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
  }

  const configureBatchReveal = async (launchpegAddress: string) => {
    await batchReveal.configure(
      launchpegAddress,
      config.batchRevealSize,
      config.batchRevealStart,
      config.batchRevealInterval
    )
  }

  describe('LaunchpegV1 data', async () => {
    const lpAddress: string = '0x5C1890eBB39014975b3981febff2A43420CEf76d'
    const flpAddress: string = '0xC70DF87e1d98f6A531c8E324C9BCEC6FC82B5E8d'

    it('Should return Launchpeg type and version', async () => {
      expect(await lens.getLaunchpegType(lpAddress)).to.eql([1, 1])
      expect(await lens.getLaunchpegType(flpAddress)).to.eql([2, 1])
    })

    it('Should return all Launchpegs by type and version', async () => {
      const version = 1
      const numEntries = 1
      const user = ethers.constants.AddressZero

      let lastIdx = 1
      let lensDataArr = await lens.getLaunchpegsByTypeAndVersion(LAUNCHPEG_TYPE, version, numEntries, lastIdx, user)
      let lpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(1)
      expect(lpAddresses).to.eql([lpAddress])

      lastIdx = 2
      lensDataArr = await lens.getLaunchpegsByTypeAndVersion(FLAT_LAUNCHPEG_TYPE, version, numEntries, lastIdx, user)
      let flpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(1)
      expect(flpAddresses).to.eql([flpAddress])
    })

    it('Should return Launchpeg data', async () => {
      const launchpegType = 1
      const flatLaunchpegType = 2
      const user = alice.address

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
    let lpWithReveal: string
    let lpWithoutReveal: string
    let flpWithReveal: string
    let flpWithoutReveal: string
    let erc1155sb: string

    const expectLensDataEqual = (
      lensData: any,
      launchpegAddress: string,
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

      await create1155SingleBundle()
      erc1155sb = await launchpegFactory.allLaunchpegs(2, 0)
    })

    it('Should return Launchpeg type and version', async () => {
      expect(await lens.getLaunchpegType(lpWithReveal)).to.eql([1, 2])
      expect(await lens.getLaunchpegType(lpWithoutReveal)).to.eql([1, 2])
      expect(await lens.getLaunchpegType(flpWithReveal)).to.eql([2, 2])
      expect(await lens.getLaunchpegType(flpWithoutReveal)).to.eql([2, 2])
      expect(await lens.getLaunchpegType(erc1155sb)).to.eql([3, 2])
    })

    it('Should return all Launchpegs by type and version', async () => {
      const version = 2
      const numEntries = 4
      const lastIdx = 4
      const user = ethers.constants.AddressZero

      let lensDataArr = await lens.getLaunchpegsByTypeAndVersion(LAUNCHPEG_TYPE, version, numEntries, lastIdx, user)
      let lpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(2)
      expect(lpAddresses).to.eql([lpWithoutReveal, lpWithReveal])

      lensDataArr = await lens.getLaunchpegsByTypeAndVersion(FLAT_LAUNCHPEG_TYPE, version, numEntries, lastIdx, user)
      let flpAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(2)
      expect(flpAddresses).to.eql([flpWithoutReveal, flpWithReveal])

      lensDataArr = await lens.getLaunchpegsByTypeAndVersion(
        ERC1155_SINGLE_BUNDLE_TYPE,
        version,
        numEntries,
        lastIdx,
        user
      )
      let sbAddresses = lensDataArr.map((data: any) => data.id)
      expect(lensDataArr.length).to.eq(1)
      expect(sbAddresses).to.eql([erc1155sb])
    })

    it('Should return Launchpeg data', async () => {
      const user = alice.address

      let lensData = await lens.getLaunchpegData(lpWithReveal, user)
      expectLensDataEqual(lensData, lpWithReveal, LAUNCHPEG_TYPE, true)

      lensData = await lens.getLaunchpegData(lpWithoutReveal, user)
      expectLensDataEqual(lensData, lpWithoutReveal, LAUNCHPEG_TYPE, false)

      lensData = await lens.getLaunchpegData(flpWithReveal, user)
      expectLensDataEqual(lensData, flpWithReveal, FLAT_LAUNCHPEG_TYPE, true)

      lensData = await lens.getLaunchpegData(flpWithoutReveal, user)
      expectLensDataEqual(lensData, flpWithoutReveal, FLAT_LAUNCHPEG_TYPE, false)
    })
  })

  after(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [],
    })
  })
})
