# ShopPilot — Distribution Guide

**Date:** 2026-07-28  
**Purpose:** Step-by-step instructions for building, signing, notarizing, and distributing ShopPilot.

---

## Build Process

### Prerequisites
- Xcode 15+ installed (command line tools: `xcode-select --install`)
- Swift 5.9+ toolchain
- Apple Developer account (for code signing and notarization)

### Building from Command Line

```bash
# Navigate to project root
cd ~/Desktop/ShopPilot

# Build all targets
swift build

# Run tests
swift test

# Build the macOS app bundle
xcodebuild -scheme ShopPilot \
  -destination 'platform=macOS,arch=x86_64' \
  -configuration Release \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
```

### Build Scripts

The project includes `scripts/build.sh` and `scripts/test.sh` for convenience. These are created by SPK-0110 and should be updated as the build process evolves.

---

## Code Signing

### Developer ID Application Certificate
For distribution outside the Mac App Store, you need a "Developer ID Application" certificate:

1. Go to [developer.apple.com/certificates](https://developer.apple.com/certificates/)
2. Create a new "Developer ID Application" certificate
3. Download and install it in your keychain
4. Note your Team ID (found in the Apple Developer portal)

### Signing the App Bundle

```bash
codesign --force \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --timestamp \
  /path/to/ShopPilot.app
```

The `--options runtime` flag enables Hardened Runtime, which is required for notarization.

---

## Notarization

### Step 1: Create a DMG

```bash
# Create a disk image from the app
hdiutil create -volname "ShopPilot" \
  -srcfolder /path/to/ShopPilot.app \
  -ov -format UDZO \
  ShopPilot.dmg
```

### Step 2: Staple (Optional — for App Store distribution)

Notarization stapling attaches Apple's notarization ticket to the DMG so users don't need an internet connection to verify.

```bash
xcrun notarytool staple \
  --team-id TEAMID \
  --apple-id "your@appleid.com" \
  --password "@keychain:NOTARIZATION_PASSWORD" \
  ShopPilot.dmg
```

### Step 3: Submit for Notarization (via xcrun altool)

```bash
# Upload the DMG
xcrun altool --notarize-app \
  --primary-framework ShopPilot.dmg \
  --apiKey NOTARIZATION_API_KEY \
  --apiIssuer "YOUR_ISSUER_ID"

# Check status (poll until complete)
xcrun altool --notarization-info NOTARIZATION_UUID \
  --apiKey NOTARIZATION_API_KEY \
  --apiIssuer "YOUR_ISSUER_ID"
```

### Alternative: notarytool (Recommended — simpler)

Apple's newer `notarytool` CLI is easier to use than `altool`:

```bash
# Generate an API key in the Apple Developer portal
# Store credentials for future use
xcrun notarytool store-credentials "NOTARIZATION_PROFILE" \
  --apple-id "your@appleid.com" \
  --team-id TEAMID \
  --password "@keychain:NOTARIZATION_PASSWORD"

# Submit for notarization
xcrun notarytool submit ShopPilot.dmg \
  --keychain-profile "NOTARIZATION_PROFILE" \
  --wait

# Staple the ticket
xcrun notarytool staple ShopPilot.dmg \
  --keychain-profile "NOTARIZATION_PROFILE"
```

---

## Gatekeeper Compliance

macOS Gatekeeper checks that apps are:
1. **Signed** with a valid Developer ID certificate
2. **Notarized** by Apple (for apps downloaded from the internet)
3. **Hardened Runtime** enabled (`--options runtime` during signing)

If any of these fail, macOS will show a warning dialog to users. The notarization process eliminates this warning for most users.

---

## Distribution Channels

### 1. Direct Download (Website + GitHub Releases)
- Host the `.dmg` on your website or GitHub Releases page.
- Users download and drag ShopPilot.app to Applications folder.
- Gatekeeper will show "ShopPilot is downloaded from the internet" — clicking Open once registers the app as trusted.

### 2. Mac App Store
- Create an App Store Connect listing for ShopPilot Control (free tier).
- Submit via Xcode's Organizer or `xcrun altool --upload-app`.
- In-app purchases for Studio2D and Studio3D upgrades.
- Apple handles distribution, updates, and payment processing (takes 15% commission).

### 3. GitHub Releases (Nightly/Testing)
- Tag commits with version numbers (e.g., `v0.1.0-nightly`).
- Attach the `.dmg` as a release asset.
- Include checksums (SHA-256) for integrity verification.
- Note: Notarized builds recommended even for nightly releases to avoid Gatekeeper warnings.

---

## Manual Distribution Checklist

When distributing ShopPilot manually, verify each step:

- [ ] App is signed with Developer ID Application certificate
- [ ] Hardened Runtime is enabled (`--options runtime`)
- [ ] DMG is created and contains only the app bundle
- [ ] Notarization ticket obtained from Apple
- [ ] Ticket stapled to DMG (optional but recommended)
- [ ] SHA-256 checksum published alongside download link
- [ ] Release notes included with version number

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "App can't be opened because Apple cannot check it for malicious software" | Run `xattr -cr /Applications/ShopPilot.app` to remove quarantine attribute (temporary fix; proper notarization is the real solution) |
| Notarization rejected | Check rejection email from Apple for specific reasons. Common causes: missing entitlements, unsigned frameworks, or prohibited APIs |
| Stapling fails | Ensure you have an internet connection and the correct Team ID |
