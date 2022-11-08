import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction, DeployResult } from 'hardhat-deploy/types'
import { getProxyOwner } from '../tasks/utils'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, ethers, getChainId, getNamedAccounts, run } = hre
  const { deploy, catchUnknownSigner } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()

  const proxyOwner = getProxyOwner(chainId)
  const constructorArgs: any[] = []
  let proxyContract: DeployResult | undefined
  await catchUnknownSigner(async () => {
    proxyContract = await deploy('BatchReveal', {
      from: deployer,
      args: constructorArgs,
      proxy: {
        owner: proxyOwner,
        proxyContract: 'OpenZeppelinTransparentProxy',
        viaAdminContract: 'DefaultProxyAdmin',
        execute: {
          init: {
            methodName: 'initialize',
            args: [],
          },
        },
      },
      log: true,
    })
  })

  if (proxyContract && proxyContract.implementation) {
    try {
      const implementationContract = await ethers.getContractAt('BatchReveal', proxyContract.implementation)
      await implementationContract.initialize()
    } catch (err) {
      console.error(err)
    }
  }

  if (proxyContract && proxyContract.implementation) {
    try {
      await run('verify:verify', {
        address: proxyContract.implementation,
        constructorArguments: constructorArgs,
      })
    } catch (err) {
      console.error(err)
    }
  }
}

export default func
func.tags = ['BatchReveal']
