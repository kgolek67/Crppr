# Crppr

A simple native SwiftUI app for iPhones running iOS 17 or later. Choose a photo, enter an exact **width:height** ratio, move the crop box over the image, and save the result to Photos.

## Use the app

1. Tap **Choose Photo** and select an image from your photo library.
2. Enter **width** and **height** separately, such as `1:1`, `9:16`, or `1.5:1`. Each value can be **0.1 to 999.9**, with at most one decimal place. The default is `1:1`; use the swap button to exchange width and height. The applied-ratio label shows the active ratio.
3. Drag the crop box to choose the area to keep. Pinch or use **Crop size** to resize it while preserving the selected ratio. **Reset** restores the centered box.
4. Tap **Save to Photos**. Allow permission to add photos when iOS asks.

The crop box changes shape when the ratio changes. There is no freeform crop mode. Width and height keep their entered precision: `9:16` stays exactly `9:16`, rather than becoming a rounded decimal quotient. Images use whole pixels, so exported dimensions are exact multiples of the reduced ratio. For example, `9:16` can produce 900 × 1600, `1.5:1` reduces to `3:2`, and `2.5:3.7` reduces to `25:37`. There is no aspect-ratio rounding or stretching. Some small images cannot support every ratio.

Your original photo stays unchanged. Crops are saved as PNG images. The system photo picker only gives the app access to images you select; saving uses add-only Photos permission. Crppr has no camera, accounts, tracking, network calls, or third-party dependencies.

## Get an unsigned IPA with GitHub

You need a GitHub account and a browser. **A Mac, Xcode installation, Apple Developer account, signing certificate, and repository secrets are not required to build the IPA.** GitHub's macOS runner compiles it for physical iPhones.

1. Download and extract this project's source archive.
2. Create an empty GitHub repository.
3. Use **Add file → Upload files** to upload the extracted project's contents to the repository root. Include the hidden `.github` folder. The root must contain `Crppr.xcodeproj`, `Crppr/`, `scripts/`, and `.github/workflows/`; avoid adding an extra enclosing project folder.
4. Commit the files. Open the repository's **Actions** tab and enable workflows if GitHub asks.
5. Open **Build unsigned iPhone IPA** and choose **Run workflow**. Keep the default macOS runner, or choose **macos-26-intel** if the default runner queue is slow. A push to `main` or `master` also starts a build automatically.
6. Open the completed successful run and download **Crppr-unsigned-ipa** from **Artifacts**. GitHub wraps the download in a ZIP file; extract it to get `Crppr-unsigned.ipa`.

If your uploader omits hidden folders, use GitHub's **Add file → Create new file** to create `.github/workflows/unsigned-ipa.yml` and paste the matching workflow from this project. The workflow must be committed before it appears in Actions. GitHub Actions usage limits depend on your account and repository visibility.

The IPA contains `Payload/Crppr.app` and is intentionally unsigned. Transfer it to your iPhone, extract the artifact ZIP in Files if needed, then import the `.ipa` into **Feather** and sign/install it using your existing Feather signing setup. Creating the unsigned IPA needs no Apple credentials; installation still requires a valid signing method in Feather.

## Development

The complete checked-in Xcode project and shared `Crppr` scheme require no project generator or package installation. On a Mac with Xcode, open `Crppr.xcodeproj`, or build and package exactly as CI does:

```sh
bash scripts/build-unsigned-ipa.sh
```

This creates `dist/Crppr-unsigned.ipa`. To compile without packaging:

```sh
xcodebuild \
  -project Crppr.xcodeproj \
  -scheme Crppr \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build
```

The workflow builds an `arm64` iPhoneOS app, checks the packaged app, and uploads the unsigned IPA. It does not use an archive export, signing team, provisioning profile, or simulator build. A successful Actions run is the device compilation check; Linux cannot compile SwiftUI or the iOS SDK.

Run the exact-ratio geometry checks on a machine with Swift installed:

```sh
swiftc Crppr/CropGeometry.swift Tests/CropGeometryTests.swift -o /tmp/crppr-geometry-tests
/tmp/crppr-geometry-tests
```

Validate a generated IPA's layout, device architecture, platform, and lack of signatures:

```sh
python3 scripts/validate-ipa.py dist/Crppr-unsigned.ipa
```
