import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, run } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy('ERC1155SingleBundle', {
    from: deployer,
    args: [],
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  })

  if (deployResult.newlyDeployed) {
    const contract = await hre.ethers.getContractAt('ERC1155SingleBundle', deployResult.address)

    await contract.initialize(
      deployer,
      deployer,
      'ipfs://bafybeievehyetoezu5nhhjgyadlszdig2puspoopqfjypivm7nisj7zxdq/',
      10,
      0,
      1676502000,
      1676509200,
      1676516400,
      'Test 1155 Single Token',
      'T1155ST'
    )

    await contract.publicSaleMint(1)
  }

  if (hre.network.name !== 'hardhat') {
    try {
      await run('verify:verify', {
        address: deployResult.address,
      })
    } catch (err) {
      console.error(err)
    }
  }
}

export default func
func.tags = ['ERC1155SingleBundle']
