# Lumos

Lumos is a modern macOS app for controlling two WiZ lights over your local network. It does not require a cloud account and communicates directly with the lights using the WiZ UDP protocol on port `38899`.

## Features

- Turn each light on or off individually, or control both at once
- Live brightness control
- White temperature control from 2,200 K to 6,500 K
- Color and HEX selection
- Up to five color and white-temperature favorites
- Compact menu bar controls
- Connection status monitoring and automatic refresh after wake
- Local-network operation with no external server or account required

## Requirements

- macOS 14 or later
- Swift 6 toolchain
- A Mac and WiZ lights connected to the same local network

## Device configuration

This version uses two fixed local IP addresses for a personal setup:

- Desk Lamp: `192.168.1.197`
- Room Lamp: `192.168.1.196`

To use Lumos on a different network, replace the IP addresses in `Sources/Lumos/LightStore.swift` with the reserved IP addresses of your lights.

## Build and install

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open /Applications/Lumos.app
```

The script creates a release build, installs it at `/Applications/Lumos.app`, and applies an ad hoc signature for local use.

On first launch, allow macOS local-network access. The downloadable GitHub build is not notarized, so macOS may display a security warning the first time it is opened.

## Privacy

Lumos communicates only with the configured lights on your local network. It does not collect telemetry or send data to the cloud.
