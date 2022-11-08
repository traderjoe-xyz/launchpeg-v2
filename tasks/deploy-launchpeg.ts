import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'
import 'hardhat-deploy-ethers'
import { task } from 'hardhat/config'
import { loadLaunchConfig } from './utils'

task('deploy-launchpeg', 'Deploy Launchpeg contract')
  .addParam('configFilename')
  .setAction(async ({ configFilename }, hre) => {
    console.log('-- Deploying Launchpeg --')

    const ethers = hre.ethers
    const factoryAddress = (await hre.deployments.get('LaunchpegFactory')).address

    const factory = await ethers.getContractAt('LaunchpegFactory', factoryAddress)

    const launchConfig = loadLaunchConfig(configFilename)

    const creationTx = await factory.createLaunchpeg(
      launchConfig.name,
      launchConfig.symbol,
      launchConfig.projectOwner,
      launchConfig.royaltyReceiver,
      launchConfig.maxPerAddressDuringMint,
      launchConfig.collectionSize,
      launchConfig.amountForAuction,
      launchConfig.amountForAllowlist,
      launchConfig.amountForDevs,
      launchConfig.enableBatchReveal
    )

    await creationTx.wait()

    const launchpegNumber = await factory.numLaunchpegs(0)
    const launchpegAddress = await factory.allLaunchpegs(0, launchpegNumber - 1)

    console.log(`-- Contract deployed at ${launchpegAddress} --`)

    console.log('-- Initializating phases --')

    const launchpeg = await ethers.getContractAt('Launchpeg', launchpegAddress)

    const initTx = await launchpeg.initializePhases(
      launchConfig.auctionSaleStartTime,
      launchConfig.auctionStartPrice,
      launchConfig.auctionEndPrice,
      launchConfig.auctionDropInterval,
      launchConfig.preMintStartTime,
      launchConfig.allowlistStartTime,
      launchConfig.allowlistDiscountPercent,
      launchConfig.publicSaleStartTime,
      launchConfig.publicSaleEndTime,
      launchConfig.publicSaleDiscountPercent
    )

    await initTx.wait()

    if (launchConfig.allowlistLocalPath) {
      await hre.run('configure-allowlist', {
        csvPath: launchConfig.allowlistLocalPath,
        contractAddress: launchpeg.address,
      })
    }

    if (launchConfig.unrevealedURI && launchConfig.baseURI) {
      await hre.run('set-uris', {
        contractAddress: launchpeg.address,
        unrevealedURI: launchConfig.unrevealedURI,
        baseURI: launchConfig.baseURI,
      })
    }

    if (launchConfig.enableBatchReveal) {
      await hre.run('configure-batch-reveal', {
        baseLaunchpeg: launchpegAddress,
        revealBatchSize: launchConfig.revealBatchSize,
        revealStartTime: launchConfig.revealStartTime,
        revealInterval: launchConfig.revealInterval,
      })
    }
  })
