const TESTNET_PROXY_OWNER = '0xdB40a7b71642FE24CC546bdF4749Aa3c0B042f78'
const MAINNET_PROXY_OWNER = '0x64c4607AD853999EE5042Ba8377BfC4099C273DE'

export const getProxyOwner = (chainId: string): string => {
  if (chainId === '4' || chainId === '43113') {
    return '0xdB40a7b71642FE24CC546bdF4749Aa3c0B042f78'
  } else if (chainId === '43114' || chainId === '31337') {
    return '0x64c4607AD853999EE5042Ba8377BfC4099C273DE'
  } else {
    throw `Unknown chain ID ${chainId}`
  }
}

export const getLaunchpegFactoryV1 = (chainId: string): string => {
  if (chainId === '43113') {
    return '0xdB40a7b71642FE24CC546bdF4749Aa3c0B042f78'
  } else if (chainId === '43114') {
    return '0x64c4607AD853999EE5042Ba8377BfC4099C273DE'
  } else {
    throw `Unknown chain ID ${chainId}`
  }
}
