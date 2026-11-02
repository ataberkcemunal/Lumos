# Lumos

Lumos is a modern macOS app for controlling two WiZ lights over your local network. It does not require a cloud account and communicates directly with the lights using the WiZ UDP protocol on port `38899`.

## Features

- Turn each light on or off individually, or control both at once
- Live brightness control
- White temperature control from 2,200 K to 6,500 K
- Color and HEX selection
- Up to eight favorites in total, at most five colors and five white temperatures
- Compact menu bar controls; right-click the menu bar icon to quit
- Full keyboard control: Tab moves between controls, arrow keys adjust sliders, ⌘R refreshes
- Connection status monitoring and automatic refresh after wake
- Local-network operation with no external server or account required

## Requirements

- macOS 14 or later
- Swift 6 toolchain
- A Mac and WiZ lights connected to the same local network

## Device configuration

This version uses two fixed local IP addresses for a personal setup:

- Desk Lamp: `192.168.1.196`
- Room Lamp: `192.168.1.195`

To use Lumos on a different network, replace the IP addresses in `Sources/Lumos/LightStore.swift` with the reserved IP addresses of your lights.

## Build and install

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open /Applications/Lumos.app
```

The script creates a release build, installs it at `/Applications/Lumos.app`, and applies an ad hoc signature for local use.

The app icon is drawn in code by `scripts/make-icon.swift`. Run `sh scripts/build-icon.sh` after changing it to regenerate `icon.png`, the iconset and `Resources/Lumos.icns`.

On first launch, allow macOS local-network access. The downloadable GitHub build is not notarized, so macOS may display a security warning the first time it is opened.

## Privacy

Lumos communicates only with the configured lights on your local network. It does not collect telemetry or send data to the cloud.

### Automatic address recovery

Lumos saves each lamp's MAC identity and last working IP. Refreshes and controls verify the identity before using an address, and recover changed addresses through local UDP discovery. For lamps that ignore broadcast queries, discovery also probes directly on active IPv4 subnets of at most 1,024 addresses. Unknown identities are never substituted for saved lamps. Discovery requires local-network access and a network that permits communication between devices.

The two configured home lamps have their verified MAC identities seeded for migration from older settings. Newly added lamps learn their identity on their first successful query. Saved IP addresses now survive app restarts.

Run `sh scripts/test-discovery.sh` on this home network for read-only integration checks covering stale addresses, addresses occupied by another lamp, unknown identities, and identity learning. The test does not switch lights or alter their settings.

Writes reuse an identity confirmed within the last minute, so each command is a
single packet. Commands to a lamp are sent one at a time in order, and slider
previews never trigger a subnet scan. A missing lamp is rescanned with backoff
(15 s doubling to 5 min). Run `sh scripts/test-command-path.sh` for offline checks
against a fake lamp on `127.0.0.1` and of the favorite limits.

### Menu bar lifecycle

Lumos keeps one fixed-width status item and presents controls in an AppKit
popover. Display, Space, and sleep transitions close the popover without
recreating the status item. Long device lists scroll within the popover.

Run `sh scripts/test-menu-bar.sh` in a logged-in macOS GUI session for offline
lifecycle regression checks. The test uses synthetic lights and does not send
commands to your lamps. See [the menu bar review](docs/MENU-BAR-REVIEW.md) for
findings and the limits of the external-display diagnosis.
