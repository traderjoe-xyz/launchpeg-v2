import fs from 'fs'
import path from 'path'

const TESTNET_PROXY_OWNER = '0xdB40a7b71642FE24CC546bdF4749Aa3c0B042f78'
const MAINNET_PROXY_OWNER = '0x64c4607AD853999EE5042Ba8377BfC4099C273DE'

export const loadLaunchConfig = (filename: string) => {
  const file = path.join(__dirname, `config/${filename}`)
  const launchConfig = JSON.parse(fs.readFileSync(file, 'utf8'))
  return convertTimestampIfNeeded(launchConfig)
}

// This is used for testing purposes
const convertTimestampIfNeeded = (launchConfig: any) => {
  if (launchConfig.auctionSaleStartTime) {
    // Launchpeg
    if (launchConfig.auctionSaleStartTime === 'Soon') {
      launchConfig.auctionSaleStartTime = Math.floor(Date.now() / 1000) + 120
    }
    if (launchConfig.preMintStartTime === 'Soon') {
      launchConfig.preMintStartTime = launchConfig.auctionSaleStartTime + launchConfig.auctionDropInterval * 5
    }
  } else {
    // FlatLaunchpeg
    if (launchConfig.preMintStartTime === 'Soon') {
      launchConfig.preMintStartTime = Math.floor(Date.now() / 1000) + 120
    }
  }
  if (launchConfig.allowlistStartTime === 'Soon') {
    launchConfig.allowlistStartTime = launchConfig.preMintStartTime + 120
  }
  if (launchConfig.publicSaleStartTime === 'Soon') {
    launchConfig.publicSaleStartTime = launchConfig.allowlistStartTime + 120
  }
  if (launchConfig.publicSaleEndTime === 'Soon') {
    launchConfig.publicSaleEndTime = launchConfig.publicSaleStartTime + 120
  }

  return launchConfig
}

export const getProxyOwner = (chainId: string): string => {
  if (chainId === '4' || chainId === '43113') {
    return '0xdB40a7b71642FE24CC546bdF4749Aa3c0B042f78'
  } else if (chainId === '43114' || chainId === '31337') {
    return '0x64c4607AD853999EE5042Ba8377BfC4099C273DE'
  } else {
    return '0x0000000000000000000000000000000000000000'
  }
}

export const getLaunchpegFactoryV1 = (chainId: string): string => {
  if (chainId === '43113') {
    return '0x0E88dFA65aF47A4e6Dbda59F2b7A27f06557D833'
  } else if (chainId === '43114') {
    return '0x7BFd7192E76D950832c77BB412aaE841049D8D9B'
  } else {
    return '0x0000000000000000000000000000000000000000'
  }
}
