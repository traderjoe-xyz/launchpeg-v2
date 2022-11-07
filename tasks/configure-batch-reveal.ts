import '@nomiclabs/hardhat-ethers'
import 'hardhat-deploy'
import 'hardhat-deploy-ethers'
import { task } from 'hardhat/config'
import { loadLaunchConfig } from './utils'

task('configure-batch-reveal', 'Configure batch reveal for a given launchpeg')
  .addParam('baseLaunchpeg')
  .addParam('revealBatchSize')
  .addParam('revealStartTime')
  .addParam('revealInterval')
  .setAction(async ({ baseLaunchpeg, revealBatchSize, revealStartTime, revealInterval }, hre) => {
    console.log('-- Configuring batch reveal --')

    const ethers = hre.ethers

    const batchRevealAddress = (await hre.deployments.get('BatchReveal')).address
    const batchReveal = await ethers.getContractAt('BatchReveal', batchRevealAddress)

    const tx = await batchReveal.configure(baseLaunchpeg, revealBatchSize, revealStartTime, revealInterval)

    await tx.wait()

    console.log(`-- Batch reveal configured --`)
  })
