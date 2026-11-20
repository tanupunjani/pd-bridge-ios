import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const file = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const project = file("../../PDBridgeNative.xcodeproj/project.pbxproj");
const phone = file("../App/NativeViews.swift");
const talk = phone.slice(phone.indexOf("private struct ScriptedTalkDemoView"), phone.indexOf("private extension Observation.Kind"));
const watch = file("../../watch/PDBridgeWatchApp.swift");
const sender = file("../../watch/WatchTransfer.swift");
const receiver = file("../App/WatchInbox.swift");
const model = file("../App/DiaryModel.swift");
const appDelegate = file("../App/PDBridgeApp.swift");
const voiceCapture = model.slice(model.indexOf("final class LocalVoiceCapture"), model.indexOf("final class VoiceNotePlaybackController"));
const service = file("../ObservationService.swift");
const observation = file("../Observation.swift");
const backup = file("../ObservationBackup.swift");
const strings = file("../NativeStrings.swift");
const fallAdapter = file("../../watch/EntitlementGatedFallAdapter.swift");
const outbox = file("../../watch/FictionalWatchOutbox.swift");
const info = file("../../watch/Info.plist");
const buildCopy = file("../NativeStrings.swift");
const privacyManifest = file("../App/PrivacyInfo.xcprivacy");
const phoneInfo = file("../App/Info.plist");
const projectYAML = file("../../project.yml");

assert.match(project, /name = PDBridgeWatch;/, "The Watch target remains available for future validation");
assert.doesNotMatch(project, /PDBridgeWatch\.app in Embed Watch Content|Embed Watch Content/,
  "The V1 iPhone target does not package the unverified Watch companion");
assert.match(project, /PrivacyInfo\.xcprivacy in Resources/);
assert.match(project, /APP_DISPLAY_NAME = "PD Bridge"/);
assert.match(project, /MARKETING_VERSION = 1\.0\.0/);
assert.match(project, /DEVELOPMENT_TEAM = ""/,
  "Release signing has no Personal Team selected pending organization enrollment");
assert.match(projectYAML, /resources:[\s\S]*ios\/App\/Assets\.xcassets[\s\S]*ios\/App\/PrivacyInfo\.xcprivacy/);
assert.doesNotMatch(projectYAML, /target: PDBridgeWatch[\s\S]*embed: true/);
assert.match(project, /ObservationBackup\.swift in Sources/);
assert.match(project, /NativeStrings\.swift in Sources/);
assert.match(project, /FictionalWatchOutbox\.swift in Sources/);
assert.match(project, /EntitlementGatedFallAdapter\.swift in Sources/);
assert.doesNotMatch(project, /HealthKitFallSource\.swift in Sources/);
assert.doesNotMatch(project, /com\.apple\.developer\.health\.fall-detection/);
assert.match(info, /WKCompanionAppBundleIdentifier/);
assert.match(watch, /Send Fictional Test Event/);
assert.match(sender, /transferUserInfo\(event\.message\)/);
assert.match(sender, /sessionReachabilityDidChange[\s\S]*session\.isReachable[\s\S]*self\.flush\(\)/);
assert.match(sender, /case \.received:[\s\S]*has not been saved yet/);
assert.match(sender, /case \.stored, \.rejectedStale:[\s\S]*self\.finish\(receipt\)/);
assert.match(sender, /case \.rejectedStale: return "Rejected: this event predates diary deletion/);
assert.match(sender, /outbox\.complete\(receipt\.eventID, with: receipt\.state\)/);
assert.match(receiver, /service\.receiveWatch\(userInfo\)/);
assert.match(receiver, /send\(\.received, for: event\.id, through: session\)/);
assert.match(receiver, /send\(\.stored, for: event\.id, through: session\)/);
assert.ok(receiver.indexOf("let receipt = try service.receiveWatch(userInfo)") < receiver.indexOf("send(.stored"),
  "Storage receipt must follow successful service persistence");
assert.match(receiver, /catch \{[\s\S]*send\(\.retry, for: event\.id, through: session\)/);
assert.match(model, /UIAccessibility\.post\(notification: \.announcement/);
assert.match(model, /observations = \[\][\s\S]*lastRemoved = nil[\s\S]*sensitiveStateGeneration/);
assert.match(model, /protectedDataWillBecomeUnavailableNotification/);
assert.match(model, /protectedDataDidBecomeAvailableNotification/);
assert.match(phone, /onChange\(of: model\.sensitiveStateGeneration\)[\s\S]*query = ""[\s\S]*editing = nil/);
assert.match(model, /Deletion is incomplete[\s\S]*No entries are shown/);
assert.match(phone, /Retry deletion/);
assert.match(phone, /backup files saved elsewhere/);
assert.match(phone, /device-only deletion timestamp remains/);
assert.match(phone, /flash storage is not physically overwritten/);
assert.match(service, /archive = ObservationArchive\(observations: \[\], processedSourceKeys: \[\]\)[\s\S]*deletionPending = true[\s\S]*try vault\.deleteAll\(\)/);
assert.match(service, /guard !deletionPending else \{ throw ObservationServiceError\.deletionInProgress \}/);
assert.match(receiver, /was not saved\. It was not acknowledged/);
assert.match(receiver, /predates deletion[\s\S]*sent a rejection response/);
assert.match(buildCopy, /Fictional-data build\. Do not enter real health information\./);
assert.match(buildCopy, /static let demoWarning: String\? = nil/);
assert.match(buildCopy, /static let talkDemoAvailable = false/);
assert.match(buildCopy, /static let watchDemoAvailable = false/);
assert.match(phone, /if NativeBuildCopy\.talkDemoAvailable \{\s*Button\("Try scripted Talk demo \(English\)"\)/,
  "The scripted Talk entry point is hidden when the synthetic demo is disabled");
assert.match(phone, /#if PD_BRIDGE_SYNTHETIC_BUILD\s*private struct ScriptedTalkDemoView[\s\S]*?#endif/,
  "The scripted Talk view is compiled only into the synthetic demo build");
assert.match(appDelegate, /#if PD_BRIDGE_SYNTHETIC_BUILD\s*diary\.startWatch\(\)\s*#endif/,
  "WatchConnectivity is not started by the V1 Release app");
assert.match(buildCopy, /Fall recorded manually\./);
assert.match(privacyManifest, /NSPrivacyAccessedAPICategoryUserDefaults/);
assert.match(privacyManifest, /CA92\.1/);
assert.match(phoneInfo, /PDBridgePrivacyPolicyURL/);
assert.match(projectYAML, /PRIVACY_POLICY_URL: "https:\/\/tanupunjani\.github\.io\/pd-bridge-case-study\/privacy\.html"/);
assert.match(phone, /Link\("Privacy Policy", destination: url\)/);
assert.match(phone, /url\.scheme == "https", url\.host != nil/);
assert.match(privacyManifest, /<key>NSPrivacyTracking<\/key>\s*<false\/>/);
assert.match(phone, /Include in appointment/);
assert.match(phone, /fileExporter\(/);
assert.match(phone, /fileImporter\(/);
assert.match(phone, /\.rightToLeft/);
assert.match(phone, /LazyVGrid\(columns:/);
assert.match(phone, /NoticeBanner\(message: notice, tone: model\.noticeTone\)/);
assert.match(phone, /Edited · original wording preserved/);
assert.match(phone, /onOpenHistory/);
assert.match(phone, /Nothing selected for this appointment yet/);
assert.match(phone, /Saved in History, not in this report/);
assert.match(phone, /Add to this appointment/);
assert.match(phone, /Set aside from this appointment/);
assert.match(phone, /Keeps this entry in History but removes it from this appointment report/);
assert.match(observation, /Recorded in PD Bridge:/);
assert.match(phone, /Importing an older backup may restore entries deleted on this iPhone/);
assert.match(phone, /AppointmentReport\.text\(/);
assert.match(observation, /enum AppointmentReport/);
assert.match(observation, /observations\.filter \{\s*\$0\.confirmation == \.userConfirmed && \$0\.includeInAppointment/);
assert.match(observation, /static func orderedEntries\(from observations: \[Observation\]\)/);
assert.match(phone, /Create encrypted backup\?/);
assert.match(phone, /Import and merge this backup\?/);
assert.match(phone, /accessibilityHint\("Shows the original wording/);
assert.match(phone, /accessibilityHint\(NativeBuildCopy\.quickEventHint\)/);
assert.match(phone, /accessibilityLabel\("Search history entries"\)/);
assert.match(phone, /accessibilityValue\(filter\.title/);
assert.match(phone, /dynamicTypeSize\.isAccessibilitySize/);
assert.match(phone, /Try scripted Talk demo \(English\)/);
assert.match(phone, /Stop without saving/);
assert.match(phone, /Review fictional note/);
assert.match(phone, /Save fictional note to History/);
assert.match(phone, /Original wording is preserved exactly as entered/);
assert.match(phone, /accessibilityAddTraits\(\.updatesFrequently\)/);
assert.match(phone, /accessibilityElement\(children: \.combine\)/);
assert.match(phone, /accessibilityLabel\(message\)/);
assert.match(phone, /minHeight: comfortMode \? 64 : 56/);
assert.match(phone, /private struct NativeBottomNavigation: View/);
assert.match(phone, /if dynamicTypeSize\.isAccessibilitySize \{[\s\S]*Text\(visibleTitle\)[\s\S]*\} else \{[\s\S]*Image\(systemName: destination\.symbol\)/,
  "Accessibility-size navigation keeps text labels and removes redundant icons");
assert.match(phone, /let visibleTitle = dynamicTypeSize\.isAccessibilitySize && destination\.title == "Appointment"[\s\S]*NativeStrings\.text\("Plan", languageCode: languageCode\)[\s\S]*\.accessibilityLabel\(title\)/,
  "The appointment tab uses a compact visible label at accessibility sizes and keeps its full screen-reader name");
assert.match(phone, /if !dynamicTypeSize\.isAccessibilitySize \{[\s\S]*NativeBuildCopy\.homeIntro/,
  "Home keeps its primary capture action visible by removing only secondary copy at accessibility sizes");
assert.match(phone, /ScrollViewReader \{ scrollProxy in[\s\S]*DemoBanner\(\)\.id\("home-top"\)[\s\S]*\.sheet\(item: \$activeSheet, onDismiss:[\s\S]*scrollProxy\.scrollTo\("home-top", anchor: \.top\)/,
  "Home returns to its start after note or Talk sheets are dismissed");
assert.doesNotMatch(phone, /TabView\(selection:/, "Core navigation must not use the floating translucent system tab bar");
assert.ok(phone.indexOf("NativeBottomNavigation(selectedTab:") > phone.indexOf("ZStack {"),
  "Navigation actions remain after main screen content in accessibility reading order");
assert.match(phone, /\.background\(Palette\.page\.ignoresSafeArea\(edges: \.bottom\)\)[\s\S]*\.overlay\(alignment: \.top\)/,
  "Bottom navigation extends only its page-colored background into the home-indicator area");
assert.match(phone, /\.toolbarBackground\(Palette\.page, for: \.navigationBar\)/);
assert.match(phone, /ToolbarItemGroup\(placement: \.keyboard\)[\s\S]*Hide keyboard[\s\S]*NativeStrings\.text\("Save"/);
assert.match(talk, /VStack\(spacing: 0\) \{[\s\S]*HStack[\s\S]*Button\("Stop without saving", action: onClose\)[\s\S]*ScrollViewReader[\s\S]*ScrollView \{/,
  "Talk controls sit in a fixed header outside the scrolling conversation content");
assert.match(talk, /Button\("Stop without saving", action: onClose\)[\s\S]*DemoBanner\(\)[\s\S]*ScrollView \{[\s\S]*Text\("Scripted Talk demonstration"\)/,
  "Fictional-data warning remains visible above the scrollable Talk content");
assert.match(talk, /onChange\(of: reviewing\)[\s\S]*scrollProxy\.scrollTo\("talk-review-top", anchor: \.top\)[\s\S]*Text\("Review the sample before saving"\)[\s\S]*id\("talk-review-top"\)/,
  "Talk final review opens at its heading rather than leaving it clipped above the viewport");
assert.match(talk, /\.toolbar\(\.hidden, for: \.navigationBar\)/,
  "Talk avoids translucent navigation content overlap");
assert.match(model, /func retryProtectedStorage\(\)/);
assert.match(model, /enum DiaryNoticeTone/);
assert.match(model, /class LocalMedicationReminderController/);
assert.match(model, /UNCalendarNotificationTrigger\(dateMatching: schedule\.dateComponents, repeats: true\)/);
assert.match(model, /A reminder you scheduled is ready\./);
assert.match(model, /Delivery depends on iOS notification settings and may be delayed or missed\./);
assert.match(model, /requestAuthorization\(options: \[\.alert, \.sound\]\)/,
  "Notifications are requested only after a user enables the reminder");
assert.match(phone, /Daily medication reminder/);
assert.match(phone, /does not give dosing advice or confirm a dose/);
assert.match(phone, /Button\("Call a caregiver"\)/);
assert.match(phone, /does not monitor emergencies[\s\S]*local emergency services directly/);
assert.match(phone, /TextField\("Caregiver name", text: \$caregiverName\)/);
assert.match(phone, /TextField\("Phone number", text: \$caregiverPhone\)/);
assert.match(phone, /Button\("Review call details"\)/);
assert.match(phone, /private struct HelpView: View[\s\S]*@Environment\(\\.dismiss\) private var dismiss[\s\S]*Button\("Done"\) \{ dismiss\(\) \}/,
  "The caregiver help sheet has an explicit accessible exit action");
assert.match(phone, /Button\("Open Phone"\)[\s\S]*openCaregiverCall\(\)/,
  "Opening the Phone handoff requires an explicit review-screen action");
assert.match(phone, /Button\("Cancel", role: \.cancel\)[\s\S]*clearCallDetails\(\)/,
  "Cancel leaves the call review without retaining the temporary details");
assert.match(phone, /components\.scheme = "tel"/);
assert.doesNotMatch(phone, /CNContactPickerViewController|CNContactStore/,
  "V1 uses the tested manual Help entry rather than the native contact picker");
assert.match(voiceCapture, /case \.undetermined:[\s\S]*AVAudioApplication\.requestRecordPermission/,
  "Microphone permission is requested only from the explicit Start action");
assert.match(model, /isExcludedFromBackup = true/);
assert.match(model, /FileProtectionType\.complete/);
assert.match(phone, /Save voice note/);
assert.match(phone, /VoiceNotePlayerView/);
assert.match(observation, /struct LocalReminderSchedule/);
assert.match(backup, /CCKeyDerivationPBKDF/);
assert.match(backup, /AES\.GCM\.seal/);
assert.match(backup, /AES\.GCM\.open/);
assert.match(strings, /draft, unreviewed/);
assert.match(strings, /drafts\[language\]\?\[key\] \?\? key/);
assert.match(strings, /struct NativeScriptedTalkDraft/);
assert.match(strings, /private\(set\) var eventIndex: Int\?/);
assert.match(strings, /Selected from fixed sample choices; no speech was captured, transcribed, or interpreted\./);
assert.match(watch, /accessibilityValue\(transfer\.status\)/);
assert.match(watch, /Pending fictional Watch events/);
assert.match(outbox, /Unsupported fictional outbox version/);
assert.match(outbox, /mutating func acknowledge/);
assert.match(outbox, /class FictionalWatchOutboxStore/);
assert.match(outbox, /\.completeFileProtectionUntilFirstUserAuthentication/);
assert.match(sender, /outboxStore\.save\(outbox\)/);
assert.doesNotMatch(sender, /UserDefaults\.standard/);
assert.match(fallAdapter, /PD_BRIDGE_FALL_DETECTION_ENTITLEMENT_GRANTED/);
assert.match(fallAdapter, /isAvailable/);
assert.doesNotMatch(project + fallAdapter.match(/#else[\s\S]*?#endif/)[0], /requestAuthorization/);
assert.doesNotMatch(phone + strings + model, /SFSpeechRecognizer|URLSession|SpeechTranscriber|AVAudioEngine/);
assert.doesNotMatch(sender + receiver, /AVAudioSession|AVAudioRecorder|requestRecordPermission/);
console.log("Native project and disabled-permission checks: passed");
