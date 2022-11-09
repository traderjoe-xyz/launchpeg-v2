import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { getLaunchpegFactoryV1 } from '../tasks/utils'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts, run } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()

  const factoryV1Address = getLaunchpegFactoryV1(chainId)
  const factoryV2Address = (await deployments.get('LaunchpegFactory')).address
  const batchRevealAddress = (await deployments.get('BatchReveal')).address

  const constructorArgs = [factoryV1Address, factoryV2Address, batchRevealAddress]
  const deployResult = await deploy('LaunchpegLens', {
    from: deployer,
    args: constructorArgs,
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  })

  try {
    await run('verify:verify', {
      address: deployResult.address,
      constructorArguments: constructorArgs,
    })
  } catch (err) {
    console.log(err)
  }
}
export default func
func.tags = ['LaunchpegLens']
func.dependencies = ['LaunchpegFactory', 'BatchReveal']
