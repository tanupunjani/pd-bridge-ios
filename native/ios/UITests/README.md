# Physical iPhone UI checks

`PDBridgeUITests` uses only fictional text. Each launch passes a random run ID and opens a separate protected vault and Keychain item. The normal diary is not opened. WatchConnectivity is disabled for this test launch. Do not enter real health information.

The automated journey covers note capture, History search, correction with original wording, appointment inclusion and exclusion, opening the iOS print preview, deletion, and Undo. A print sheet opening is not proof that a PDF was saved.

Run on an unlocked iPhone using the verified Tanvi development team. Xcode may create a free development provisioning profile for the UI test runner. Do not switch to the disputed Personal Team.

## Checks requiring a person on the iPhone

- Microphone prompt, actual recording sound, playback, save, relaunch, and deletion; confirm no note audio leaves the device.
- Notification permission, actual reminder delivery, denial, and cancellation.
- Caregiver Help manual name/number entry, validation, review, and cancel. V1 has no contact picker. The Open Phone action is separate and must only be used with a fictional number; never place a call.
- Share/print destination and PDF contents in the system sheet; avoid transmitting the fictional report.
- VoiceOver spoken order, large text, Comfort Mode, physical touch reach, and Urdu right-to-left layout.
- Encrypted vault persistence after force quit and relaunch, plus locked-device behavior. The automated test uses a separate vault and does not prove all hardware security properties.

Automatic fall detection, Samsung Watch support, and Watch-to-iPhone physical delivery remain unverified. Do not simulate a physical fall or trigger an emergency call.
