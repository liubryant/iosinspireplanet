# Duix local digital human integration

This folder contains the Duix iOS SDK source project copied from:
https://github.com/liubryant/Duix-Mobile/tree/main/duix-ios/GJLocalDigitalDemo/GJLocalDigitalSDK

The app-side integration is already present under `agentClaw/Features/Avatar`:

- `DuixResourceLocator.swift` locates bundled `duix/gj_dh_res` and `duix/Lily`.
- `DuixDigitalHumanRuntime.swift` calls `GJLDigitalManager` through Objective-C runtime.
- `DuixDigitalHumanView.swift` provides the SwiftUI/UIKit render host.
- `AvatarSpeechSynthesizer.swift` feeds 16 kHz mono PCM to Duix when the SDK is loaded.

Bundled model resources:

- `agentClaw/Resources/duix/Lily`
- `agentClaw/Resources/duix/gj_dh_res`

The app target references `GJLocalDigitalSDK.xcodeproj` as a subproject, depends on the
`GJLocalDigitalSDK` target, links `GJLocalDigitalSDK.framework`, and embeds it with
`CodeSignOnCopy`.

The SDK project's bundled third-party frameworks under `GJFrameWork` are static framework
packages, so they are linked by the SDK target but are not embedded into the app bundle.
Embedding those static frameworks can cause app packaging errors.

Both the app target and the SDK target use automatic signing with team `MF7G4UB9D9`.

Without the SDK framework in the app process, the avatar page falls back to the existing
static portrait and text-to-speech path.
