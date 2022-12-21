import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { Contract, ContractFactory } from 'ethers'
import { config as hardhatConfig, ethers, network } from 'hardhat'
import { getDefaultLaunchpegConfig, LaunchpegConfig } from './utils/helpers'

describe.only('OperatorFilterRegistry', function () {
  let flatLaunchpegCF: ContractFactory
  let launchpeg: Contract
  let batchRevealCF: ContractFactory
  let batchReveal: Contract
  let filterRegistry: Contract
  let osOwnedRegistrant: Contract

  let config: LaunchpegConfig

  let signers: SignerWithAddress[]
  let dev: SignerWithAddress
  let alice: SignerWithAddress
  let bob: SignerWithAddress
  let projectOwner: SignerWithAddress
  let royaltyReceiver: SignerWithAddress
  let joeFeeCollector: SignerWithAddress
  let registrantOwner: SignerWithAddress

  const abi = ethers.utils.defaultAbiCoder

  const deployFixture = async () => {
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

    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [await osOwnedRegistrant.owner()],
    })

    await network.provider.send('hardhat_setBalance', [await osOwnedRegistrant.owner(), '0x100000000000000000000000'])

    config = await getDefaultLaunchpegConfig()
    await deployBatchReveal()
    await deployFlatLaunchpeg()

    registrantOwner = await ethers.getSigner(await osOwnedRegistrant.owner())
  }

  const deployFlatLaunchpeg = async () => {
    launchpeg = await flatLaunchpegCF.deploy()
    await launchpeg.initialize(
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
    await batchReveal.configure(
      launchpeg.address,
      config.batchRevealSize,
      config.batchRevealStart,
      config.batchRevealInterval
    )

    await launchpeg.devMint(10)
  }

  const deployBatchReveal = async () => {
    batchReveal = await batchRevealCF.deploy()
    await batchReveal.initialize()
  }

  // Selector for "AddressFiltered(address)" error
  const addressFilteredError = (address: string) => `0xa8cf495d${abi.encode(['address'], [address]).slice(2)}`

  before(async () => {
    flatLaunchpegCF = await ethers.getContractFactory('FlatLaunchpeg')
    batchRevealCF = await ethers.getContractFactory('BatchReveal')
    filterRegistry = await ethers.getContractAt('IOperatorFilterRegistry', '0x000000000000AAeB6D7670E522A718067333cd4E')
    osOwnedRegistrant = await ethers.getContractAt(
      'MockPendingOwnableUpgradeable',
      '0x3cc6CddA760b79bAfa08dF41ECFA224f810dCeB6'
    )

    signers = await ethers.getSigners()
    dev = signers[0]
    alice = signers[1]
    bob = signers[2]
    projectOwner = signers[3]
    royaltyReceiver = signers[4]
    joeFeeCollector = signers[5]
  })

  beforeEach(async () => {
    await loadFixture(deployFixture)
  })

  describe('Using OpenSea list', async () => {
    const nftID = 5

    it('Should be corretly setup', async () => {
      expect(await launchpeg.operatorFilterRegistry()).to.equal(filterRegistry.address)
      expect(await filterRegistry.callStatic.isRegistered(launchpeg.address)).to.be.true
      expect(await filterRegistry.callStatic.subscriptionOf(launchpeg.address)).to.be.equal(osOwnedRegistrant.address)
    })

    it('Should be transferable by operators', async () => {
      await launchpeg.setApprovalForAll(alice.address, true)
      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)

      await launchpeg.connect(bob).approve(alice.address, nftID)
      await launchpeg.connect(alice).transferFrom(bob.address, dev.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)
    })

    it('Should block individual approvals if the operator is blocked', async () => {
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)
      // Hardhat doesn't seem to recognize custom revert reasons from external contracts
      // Doing a static call is a workaround
      await expect(launchpeg.callStatic.approve(alice.address, nftID)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )
    })

    it('Should block approvals for all if the operator is blocked', async () => {
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)
      await expect(launchpeg.callStatic.setApprovalForAll(alice.address, true)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )
    })

    it('Should block transfers if the operator is blocked', async () => {
      await launchpeg.setApprovalForAll(alice.address, true)
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)

      await expect(
        launchpeg.connect(alice).callStatic.transferFrom(dev.address, bob.address, nftID)
      ).to.be.revertedWith(addressFilteredError(alice.address))

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)
    })

    it('Should block safe transfers if the operator is blocked', async () => {
      await launchpeg.setApprovalForAll(alice.address, true)
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)

      await expect(
        launchpeg
          .connect(alice)
          .callStatic['safeTransferFrom(address,address,uint256)'](dev.address, bob.address, nftID)
      ).to.be.revertedWith(addressFilteredError(alice.address))

      await expect(
        launchpeg
          .connect(alice)
          .callStatic['safeTransferFrom(address,address,uint256,bytes)'](dev.address, bob.address, nftID, [])
      ).to.be.revertedWith(addressFilteredError(alice.address))

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)
    })

    it('Should allow transfers back if the operator is unblocked', async () => {
      await launchpeg.setApprovalForAll(alice.address, true)
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)

      await expect(
        launchpeg.connect(alice).callStatic.transferFrom(dev.address, bob.address, nftID)
      ).to.be.revertedWith(addressFilteredError(alice.address))

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)

      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, false)
      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID)

      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)
    })

    it('Should disable the filter if the address is updated to address zero', async () => {
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)
      await expect(launchpeg.callStatic.approve(alice.address, nftID)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )

      await launchpeg.updateOperatorFilterRegistryAddress(ethers.constants.AddressZero)

      await launchpeg.approve(alice.address, nftID)
      expect(await launchpeg.getApproved(nftID)).to.equal(alice.address)

      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)
    })

    it('Should disable the filter if launchpeg is unregistered', async () => {
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)
      await expect(launchpeg.callStatic.approve(alice.address, nftID)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )

      await filterRegistry.unregister(launchpeg.address)

      await launchpeg.approve(alice.address, nftID)
      expect(await launchpeg.getApproved(nftID)).to.equal(alice.address)

      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)
    })

    it("Shouldn't be possible to update the filter registry address if the caller is not the owner", async () => {
      await expect(
        launchpeg.connect(alice).updateOperatorFilterRegistryAddress(filterRegistry.address)
      ).to.be.revertedWith('PendingOwnableUpgradeable__NotOwner()')
    })

    it("Shouldn't be possible to update the filter registry list if the caller is not the owner", async () => {
      await expect(
        filterRegistry.connect(alice).callStatic.updateOperator(osOwnedRegistrant.address, alice.address, false)
      ).to.be.revertedWith('0xfcf5eff8') // OnlyAddressOrOwner()
    })
  })

  describe('Using custom list', async () => {
    const nftID = 5

    beforeEach(async () => {
      // Opensea blocks Alice
      await filterRegistry.connect(registrantOwner).updateOperator(osOwnedRegistrant.address, alice.address, true)
      // Joepegs forks from Opensea's list
      await filterRegistry.unregister(launchpeg.address)
      await filterRegistry.registerAndCopyEntries(launchpeg.address, osOwnedRegistrant.address)
    })

    it('Should block individual approvals if the operator is blocked for new and previous operators', async () => {
      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.callStatic.approve(alice.address, nftID)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )

      await expect(launchpeg.callStatic.approve(bob.address, nftID)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )
    })

    it('Should block approvals for all if the operator is blocked for new and previous operators', async () => {
      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.callStatic.setApprovalForAll(alice.address, true)).to.be.revertedWith(
        addressFilteredError(alice.address)
      )

      await expect(launchpeg.callStatic.setApprovalForAll(bob.address, true)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )
    })

    it('Should block transfers if the operator is blocked for new  operators', async () => {
      await launchpeg.setApprovalForAll(bob.address, true)

      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.connect(bob).callStatic.transferFrom(dev.address, bob.address, nftID)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)
    })

    it('Should block safe transfers if the operator is blocked for new operators', async () => {
      await launchpeg.setApprovalForAll(bob.address, true)

      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(
        launchpeg.connect(bob).callStatic['safeTransferFrom(address,address,uint256)'](dev.address, bob.address, nftID)
      ).to.be.revertedWith(addressFilteredError(bob.address))

      await expect(
        launchpeg
          .connect(bob)
          .callStatic['safeTransferFrom(address,address,uint256,bytes)'](dev.address, bob.address, nftID, [])
      ).to.be.revertedWith(addressFilteredError(bob.address))

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)
    })

    it('Should allow transfers back if the operator is unblocked for new and previous operators', async () => {
      await launchpeg.setApprovalForAll(bob.address, true)

      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.connect(bob).callStatic.transferFrom(dev.address, bob.address, nftID)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )

      expect(await launchpeg.ownerOf(nftID)).to.equal(dev.address)

      await filterRegistry.updateOperator(launchpeg.address, bob.address, false)
      await launchpeg.connect(bob).transferFrom(dev.address, bob.address, nftID)

      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)
    })

    it('Should disable the filter if the address is updated to address zero for new and previous operators', async () => {
      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.callStatic.approve(bob.address, nftID)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )

      await launchpeg.updateOperatorFilterRegistryAddress(ethers.constants.AddressZero)

      await launchpeg.approve(bob.address, nftID)
      expect(await launchpeg.getApproved(nftID)).to.equal(bob.address)

      await launchpeg.connect(bob).transferFrom(dev.address, bob.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)

      await launchpeg.approve(alice.address, nftID + 1)
      expect(await launchpeg.getApproved(nftID + 1)).to.equal(alice.address)

      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID + 1)
      expect(await launchpeg.ownerOf(nftID + 1)).to.equal(bob.address)
    })

    it('Should disable the filter if launchpeg is unregistered for new and previous operators', async () => {
      await filterRegistry.updateOperator(launchpeg.address, bob.address, true)

      await expect(launchpeg.callStatic.approve(bob.address, nftID)).to.be.revertedWith(
        addressFilteredError(bob.address)
      )

      await filterRegistry.unregister(launchpeg.address)

      await launchpeg.approve(alice.address, nftID)
      expect(await launchpeg.getApproved(nftID)).to.equal(alice.address)

      await launchpeg.connect(alice).transferFrom(dev.address, bob.address, nftID)
      expect(await launchpeg.ownerOf(nftID)).to.equal(bob.address)

      await launchpeg.approve(bob.address, nftID + 1)
      expect(await launchpeg.getApproved(nftID + 1)).to.equal(bob.address)

      await launchpeg.connect(bob).transferFrom(dev.address, bob.address, nftID + 1)
      expect(await launchpeg.ownerOf(nftID + 1)).to.equal(bob.address)
    })
  })
})
