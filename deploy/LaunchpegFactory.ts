import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction, DeployResult } from 'hardhat-deploy/types'
import { getProxyOwner } from '../tasks/utils'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getChainId, getNamedAccounts, run } = hre
  const { deploy, catchUnknownSigner } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()

  const launchpegAddress = (await deployments.get('Launchpeg')).address
  const flatLaunchpegAddress = (await deployments.get('FlatLaunchpeg')).address
  const erc1155SingleBundleAddress = (await deployments.get('ERC1155SingleBundle')).address
  const batchRevealAddress = (await deployments.get('BatchReveal')).address
  const feePercent = 750
  const feeCollector = deployer

  const proxyOwner = getProxyOwner(chainId)
  const constructorArgs: any[] = []
  const initArgs = [
    launchpegAddress,
    flatLaunchpegAddress,
    erc1155SingleBundleAddress,
    batchRevealAddress,
    feePercent,
    feeCollector,
  ]

  let proxyContract: DeployResult | undefined
  await catchUnknownSigner(async () => {
    proxyContract = await deploy('LaunchpegFactory', {
      from: deployer,
      args: constructorArgs,
      proxy: {
        owner: proxyOwner,
        proxyContract: 'OpenZeppelinTransparentProxy',
        viaAdminContract: 'DefaultProxyAdmin',
        execute: {
          init: {
            methodName: 'initialize',
            args: initArgs,
          },
        },
      },
      log: true,
    })
  })

  if (proxyContract && proxyContract.implementation) {
    try {
      const implementationContract = await ethers.getContractAt('LaunchpegFactory', proxyContract.implementation)
      await implementationContract.initialize(...initArgs)

      if (hre.network.name !== 'hardhat') {
        await run('verify:verify', {
          address: proxyContract.implementation,
          constructorArguments: constructorArgs,
        })
      }
    } catch (err) {
      console.error(err)
    }
  }
}
export default func
func.tags = ['LaunchpegFactory']
func.dependencies = ['Launchpeg', 'FlatLaunchpeg', 'ERC1155SingleBundle', 'BatchReveal']
