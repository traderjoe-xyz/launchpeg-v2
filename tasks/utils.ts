import fs from 'fs'
import path from 'path'

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
