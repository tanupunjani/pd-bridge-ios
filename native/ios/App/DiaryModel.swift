import Foundation
import SwiftUI
import UIKit
@preconcurrency import AVFoundation
@preconcurrency import UserNotifications

enum DiaryNoticeTone {
    case success
    case info
    case error
}

final class DiaryModel: ObservableObject {
    @Published private(set) var observations: [Observation] = []
    @Published private(set) var storageError: String?
    @Published var notice: String?
    @Published private(set) var noticeTone: DiaryNoticeTone = .info
    @Published var lastRemoved: Observation?
    @Published private(set) var sensitiveStateGeneration = 0

    private var service: ObservationService?
    private var watchInbox: WatchInbox?
    private var protectedDataObservers: [NSObjectProtocol] = []
    // UI automation uses a per-run vault and Keychain identity. It cannot open
    // or mutate the normal diary, even when tests run on the founder's iPhone.
    private let uiTestRunID: UUID? = {
        guard ProcessInfo.processInfo.arguments.contains("--pdbridge-uitest"),
              let value = ProcessInfo.processInfo.environment["PDBRIDGE_UI_TEST_RUN_ID"] else { return nil }
        return UUID(uuidString: value)
    }()

    init() {
        if uiTestRunID == nil { VoiceNoteStaging.removeOrphanedFiles() }
        loadService()
        observeProtectedData()
    }

    deinit { protectedDataObservers.forEach(NotificationCenter.default.removeObserver) }

    var canWrite: Bool {
        service != nil && storageError == nil && service?.isProtectedDataAvailable == true && service?.isDeletionPending == false
    }
    var canRetryDeletion: Bool { service?.isProtectedDataAvailable == true }
    var isDeletionPending: Bool { service?.isDeletionPending ?? false }

    func startWatch() {
        guard NativeBuildCopy.watchDemoAvailable else { return }
        guard uiTestRunID == nil else { return }
        guard watchInbox == nil, let service = service else { return }
        watchInbox = WatchInbox(service: service, onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
                if let message = NativeBuildCopy.watchEventSavedNotice {
                    self?.publishNotice(message, tone: .success)
                }
            }
        }, onFailure: { [weak self] message in
            DispatchQueue.main.async {
                self?.publishNotice(message, tone: .error)
            }
        })
        watchInbox?.start()
    }

    private func loadService() {
        guard UIApplication.shared.isProtectedDataAvailable else {
            service = nil
            observations = []
            storageError = "This iPhone is locked. Protected entries remain hidden until it is unlocked."
            return
        }
        do {
            let vault: ProtectedObservationVault
            if let uiTestRunID {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("PD Bridge UI Tests", isDirectory: true)
                    .appendingPathComponent(uiTestRunID.uuidString, isDirectory: true)
                vault = ProtectedObservationVault(directoryURL: directory,
                    keyService: "PD Bridge UI Tests", keyAccount: uiTestRunID.uuidString)
            } else {
                vault = ProtectedObservationVault()
            }
            let loaded = try ObservationService(vault: vault)
            service = loaded
            observations = loaded.observations
            if loaded.isDeletionPending {
                storageError = "Deletion is still in progress. No entries are shown. Keep this iPhone unlocked and retry deletion."
                publishNotice(storageError ?? "Deletion is still in progress.", tone: .error)
            } else {
                storageError = nil
            }
        } catch {
            service = nil
            observations = []
            storageError = "Protected storage is unavailable. Entries have not been loaded or changed. Unlock this iPhone and reopen the app."
        }
    }

    private func observeProtectedData() {
        let center = NotificationCenter.default
        protectedDataObservers.append(center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.protectedDataWillBecomeUnavailable() })
        protectedDataObservers.append(center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.protectedDataDidBecomeAvailable() })
    }

    private func protectedDataWillBecomeUnavailable() {
        service?.protectedDataWillBecomeUnavailable()
        observations = []
        lastRemoved = nil
        sensitiveStateGeneration &+= 1
        let message = "This iPhone is locked. Protected entries are hidden until it is unlocked. Watch events are not acknowledged until they can be saved."
        storageError = message
        publishNotice(message, tone: .error)
    }

    private func protectedDataDidBecomeAvailable() {
        if let service {
            do {
                try service.protectedDataDidBecomeAvailable()
                observations = service.observations
                if service.isDeletionPending {
                    storageError = "Deletion is still in progress. No entries are shown. Keep this iPhone unlocked and retry deletion."
                } else {
                    storageError = nil
                }
            } catch {
                observations = []
                if service.isDeletionPending {
                    storageError = "Deletion is incomplete. No entries are shown. Retry deletion while this iPhone is unlocked."
                } else {
                    storageError = "Protected storage is still unavailable. No entries were loaded or changed. Retry after unlock."
                }
            }
        } else {
            loadService()
        }
        sensitiveStateGeneration &+= 1
        if let storageError { publishNotice(storageError, tone: .error) }
        else { publishNotice("Protected storage is available. Local entries were reloaded.", tone: .success) }
        startWatch()
    }

    var canRetryStorage: Bool { UIApplication.shared.isProtectedDataAvailable }

    func retryProtectedStorage() {
        guard canRetryStorage else {
            publishNotice("Unlock this iPhone before retrying protected storage.", tone: .error)
            return
        }
        if let service {
            do {
                try service.protectedDataDidBecomeAvailable()
                observations = service.observations
                if service.isDeletionPending {
                    storageError = "Deletion is incomplete. No entries are shown. Retry deletion while this iPhone is unlocked."
                    publishNotice(storageError ?? "Deletion is incomplete.", tone: .error)
                } else {
                    storageError = nil
                    publishNotice("Protected storage reopened. Local entries were reloaded.", tone: .success)
                }
            } catch {
                observations = []
                storageError = service.isDeletionPending
                    ? "Deletion is incomplete. No entries are shown. Retry deletion while this iPhone is unlocked."
                    : "Protected storage remains unavailable. No entries were changed. Try again while this iPhone is unlocked."
                publishNotice(storageError ?? "Protected storage remains unavailable.", tone: .error)
            }
        } else {
            loadService()
            if let storageError {
                publishNotice(storageError, tone: .error)
            } else {
                publishNotice("Protected storage reopened. Local entries were loaded.", tone: .success)
            }
        }
        startWatch()
    }

    func showNotice(_ message: String, tone: DiaryNoticeTone = .info) {
        publishNotice(message, tone: tone)
    }

    func addNote(_ text: String) -> Bool {
        return perform("Note saved on this iPhone.") { _ = try $0.addManual(kind: .note, text: text) }
    }

    func addVoiceNote(_ attachment: VoiceNoteAttachment) -> Bool {
        return perform("Voice note saved in the encrypted on-device vault. No transcript was created.") {
            _ = try $0.addVoiceNote(audioData: attachment.audioData,
                                    spokenLanguage: attachment.spokenLanguage,
                                    durationSeconds: attachment.durationSeconds)
        }
    }

    func addQuickEvent(_ kind: Observation.Kind) -> Bool {
        guard let text = NativeBuildCopy.quickEventText(for: kind) else { return false }
        return perform(NativeBuildCopy.quickEventSavedNotice) {
            _ = try $0.addManual(kind: kind, text: text)
        }
    }

    func confirm(_ id: UUID) { _ = perform("Event confirmed.") { try $0.confirm(id) } }
    func include(_ id: UUID, value: Bool) {
        _ = perform(value ? "Added to appointment report." : "Removed from appointment report.") {
            try $0.setIncluded(id, included: value)
        }
    }
    func edit(_ id: UUID, text: String) -> Bool {
        return perform("Correction saved.") { try $0.edit(id, text: text) }
    }
    func remove(_ id: UUID) {
        guard let service = service, storageError == nil else {
            publishNotice(storageError ?? "Protected storage is not ready. Retry local storage before deleting.", tone: .error)
            return
        }
        do {
            lastRemoved = try service.remove(id)
            refresh()
            publishNotice("Entry deleted. Undo is available in History.", tone: .success)
        } catch { storageFailure() }
    }
    func undo() {
        guard let service = service, let item = lastRemoved else { return }
        do {
            try service.undoRemoval(item)
            lastRemoved = nil
            refresh()
            publishNotice("Entry restored.", tone: .success)
        } catch { storageFailure() }
    }

    func createEncryptedBackup(passphrase: String) -> Data? {
        guard let service = service, storageError == nil else {
            publishNotice(storageError ?? "Protected storage is not ready. Retry local storage before exporting.", tone: .error)
            return nil
        }
        do {
            let data = try service.encryptedBackup(passphrase: passphrase)
            publishNotice("Encrypted backup prepared. Choose a trusted destination.", tone: .success)
            return data
        } catch ObservationBackupError.weakPassphrase {
            publishNotice("Use a backup passphrase with at least 12 characters.", tone: .error)
        } catch {
            storageFailure()
        }
        return nil
    }

    func importEncryptedBackup(_ data: Data, passphrase: String) -> Bool {
        guard let service = service, storageError == nil else {
            publishNotice(storageError ?? "Protected storage is not ready. Retry local storage before importing.", tone: .error)
            return false
        }
        do {
            try service.importEncryptedBackup(data, passphrase: passphrase)
            lastRemoved = nil
            refresh()
            publishNotice("Backup imported. Existing entries were preserved.", tone: .success)
            return true
        } catch ObservationBackupError.weakPassphrase {
            publishNotice("Use the passphrase that was set when this backup was created.", tone: .error)
        } catch {
            publishNotice("Backup could not be opened or merged. No entries were changed.", tone: .error)
        }
        return false
    }

    func deleteAll() -> Bool {
        guard let service = service else {
            publishNotice(storageError ?? "Protected storage is not available. No deletion was reported.", tone: .error)
            return false
        }
        // Clear app-owned references before the durable deletion starts.
        observations = []
        lastRemoved = nil
        sensitiveStateGeneration &+= 1
        publishNotice("Deleting local observations. No success will be reported until cleanup finishes.", tone: .info)
        do {
            try service.deleteAll()
            refresh()
            storageError = nil
            publishNotice("Local observations and their encryption key were deleted. A device-only deletion timestamp remains to reject older queued Watch events. Encrypted backup files saved elsewhere are not affected.", tone: .success)
            return true
        } catch VaultError.deletionIntentUnavailable {
            storageError = "Deletion could not start because its protected request could not be saved. No records were deleted. Retry while this iPhone is unlocked."
            publishNotice(storageError ?? "Deletion could not start.", tone: .error)
            return false
        } catch {
            storageError = "Deletion is incomplete. No entries are shown, and deletion will resume when the app opens. Keep this iPhone unlocked and retry."
            publishNotice(storageError ?? "Deletion is incomplete.", tone: .error)
            return false
        }
    }

    func refresh() { observations = service?.observations ?? [] }

    var reportObservations: [Observation] {
        AppointmentReport.selectedEntries(from: observations)
    }

    private func perform(_ success: String, _ work: (ObservationService) throws -> Void) -> Bool {
        guard let service = service, storageError == nil else {
            publishNotice(storageError ?? "Protected storage is not ready. Retry local storage before saving.", tone: .error)
            return false
        }
        do {
            try work(service)
            refresh()
            publishNotice(success, tone: .success)
            return true
        } catch ObservationServiceError.emptyText {
            publishNotice(NativeBuildCopy.emptyNoteError, tone: .error)
        } catch ObservationServiceError.invalidVoiceNote {
            publishNotice("This recording could not be saved. Record a new clip under two minutes.", tone: .error)
        } catch {
            storageFailure()
        }
        return false
    }

    private func storageFailure() {
        storageError = "Protected storage could not save this change. No success was recorded. Unlock this iPhone and retry local storage."
        publishNotice(storageError ?? "Protected storage unavailable.", tone: .error)
    }

    private func publishNotice(_ message: String, tone: DiaryNoticeTone = .info) {
        notice = message
        noticeTone = tone
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Temporary recorder output is kept in the excluded Caches directory with
/// complete file protection, then immediately removed after review. The saved
/// attachment is written only inside the AES-GCM encrypted observation vault.
enum VoiceNoteStaging {
    private static let folderName = "PD Bridge Voice Staging"
    private static let filePrefix = "voice-staging-"

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete],
                                  ofItemAtPath: directory.path)
    }

    static func newFileURL() throws -> URL {
        try prepare()
        return directory.appendingPathComponent(filePrefix + UUID().uuidString + ".m4a")
    }

    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent() == directory,
              url.lastPathComponent.hasPrefix(filePrefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeOrphanedFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix(filePrefix) && file.pathExtension == "m4a" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor
final class LocalVoiceCapture: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var reviewedRecording: VoiceNoteAttachment?
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "Microphone has not been requested."

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var temporaryURL: URL?
    private var timer: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var selectedLanguage: VoiceNoteAttachment.SpokenLanguage = .unspecified
    private var sessionOpen = true

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  typeValue == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.handleInterruption() }
        }
    }

    deinit {
        timer?.invalidate()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        recorder?.stop()
        player?.stop()
        VoiceNoteStaging.remove(temporaryURL)
    }

    func start(language: VoiceNoteAttachment.SpokenLanguage) {
        guard !isRecording, !isStarting, reviewedRecording == nil else { return }
        sessionOpen = true
        selectedLanguage = language
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startRecorder()
        case .denied:
            status = "Microphone access is off. Enable it in Settings to record; nothing was recorded."
        case .undetermined:
            isStarting = true
            status = "Waiting for microphone permission."
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.sessionOpen else { return }
                    self.isStarting = false
                    if allowed { self.startRecorder() }
                    else { self.status = "Microphone access was not allowed. Nothing was recorded." }
                }
            }
        @unknown default:
            status = "Microphone permission could not be checked. Nothing was recorded."
        }
    }

    func updateSpokenLanguage(_ language: VoiceNoteAttachment.SpokenLanguage) {
        selectedLanguage = language
        guard let reviewedRecording else { return }
        do {
            self.reviewedRecording = try reviewedRecording.replacingSpokenLanguage(with: language)
        } catch {
            status = "The language tag could not be updated. The original recording is unchanged."
        }
    }

    func stopAndReview() {
        guard isRecording, let recorder, let temporaryURL else { return }
        elapsedSeconds = min(Int(recorder.currentTime.rounded(.down)), Int(VoiceNoteAttachment.maximumDuration))
        timer?.invalidate()
        timer = nil
        recorder.stop()
        self.recorder = nil
        isRecording = false
        deactivateAudioSession()

        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                                  ofItemAtPath: temporaryURL.path)
            let size = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= VoiceNoteAttachment.maximumAudioBytes else {
                throw ObservationServiceError.invalidVoiceNote
            }
            let data = try Data(contentsOf: temporaryURL)
            let validationPlayer = try AVAudioPlayer(data: data)
            guard validationPlayer.duration > 0 else {
                throw ObservationServiceError.invalidVoiceNote
            }
            let duration = min(validationPlayer.duration, VoiceNoteAttachment.maximumDuration)
            let attachment = try VoiceNoteAttachment(audioData: data,
                                                     spokenLanguage: selectedLanguage,
                                                     durationSeconds: duration)
            reviewedRecording = attachment
            status = "Recording ready to review. Play it if you choose. It is not saved until you tap Save."
        } catch {
            reviewedRecording = nil
            status = "Recording could not be prepared. Nothing was saved; please record again."
        }
        VoiceNoteStaging.remove(temporaryURL)
        self.temporaryURL = nil
    }

    func playReviewedRecording() {
        guard let reviewedRecording else { return }
        if isPlaying {
            player?.stop()
            player = nil
            isPlaying = false
            status = "Playback stopped."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let newPlayer = try AVAudioPlayer(data: reviewedRecording.audioData)
            guard newPlayer.prepareToPlay(), newPlayer.play() else {
                deactivateAudioSession()
                status = "Playback could not start. The saved recording was not changed."
                return
            }
            player = newPlayer
            isPlaying = true
            status = "Playing the original recording."
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.player else { return }
                    if !player.isPlaying {
                        self.timer?.invalidate()
                        self.timer = nil
                        self.isPlaying = false
                        self.player = nil
                        self.status = "Playback finished."
                    }
                }
            }
        } catch {
            deactivateAudioSession()
            status = "Playback could not start. The saved recording was not changed."
        }
    }

    func discard() {
        sessionOpen = false
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        isRecording = false
        isStarting = false
        isPlaying = false
        reviewedRecording = nil
        elapsedSeconds = 0
        VoiceNoteStaging.remove(temporaryURL)
        temporaryURL = nil
        deactivateAudioSession()
        status = "Recording discarded. No voice note was saved."
    }

    private func startRecorder() {
        do {
            let url = try VoiceNoteStaging.newFileURL()
            try Data().write(to: url, options: [.atomic, .completeFileProtection])
            temporaryURL = url
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            guard newRecorder.record() else {
                throw ObservationServiceError.invalidVoiceNote
            }
            recorder = newRecorder
            isRecording = true
            status = "Recording. Tap Stop and review; nothing is saved yet. Maximum two minutes."
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let recorder = self.recorder else { return }
                    self.elapsedSeconds = min(Int(recorder.currentTime.rounded(.down)),
                                              Int(VoiceNoteAttachment.maximumDuration))
                    if recorder.currentTime >= VoiceNoteAttachment.maximumDuration {
                        self.stopAndReview()
                    }
                }
            }
        } catch {
            recorder = nil
            isRecording = false
            temporaryURL.map(VoiceNoteStaging.remove)
            temporaryURL = nil
            deactivateAudioSession()
            status = "Recording could not start. Check microphone access and try again."
        }
    }

    private func handleInterruption() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        VoiceNoteStaging.remove(temporaryURL)
        temporaryURL = nil
        deactivateAudioSession()
        status = "Recording was interrupted. Nothing was saved; start again if you wish."
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in handleInterruption() }
    }
}

@MainActor
final class VoiceNotePlaybackController: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var status = ""
    private var player: AVAudioPlayer?

    func toggle(_ attachment: VoiceNoteAttachment) {
        if isPlaying {
            stop()
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(data: attachment.audioData)
            newPlayer.delegate = self
            guard newPlayer.prepareToPlay(), newPlayer.play() else {
                status = "Playback could not start. The saved recording is unchanged."
                return
            }
            player = newPlayer
            isPlaying = true
            status = "Playing original audio, not transcribed."
        } catch {
            status = "Playback could not start. The saved recording is unchanged."
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        deactivateAudioSession()
        status = "Playback stopped."
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            isPlaying = false
            deactivateAudioSession()
            status = flag ? "Playback finished." : "Playback stopped before completion."
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.player = nil
            isPlaying = false
            deactivateAudioSession()
            status = "This recording could not be played."
        }
    }
}

/// One optional daily local reminder. Permission is requested only after the
/// person explicitly enables it in Settings. The notification contains no
/// medication name, dose, or health-entry content.
@MainActor
final class LocalMedicationReminderController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var selectedTime: Date
    @Published private(set) var status = "No reminder is scheduled."

    private static let enabledKey = "pdbridge.medicationReminder.enabled"
    private static let hourKey = "pdbridge.medicationReminder.hour"
    private static let minuteKey = "pdbridge.medicationReminder.minute"
    private static let requestID = "org.pdbridge.local-medication-reminder.daily"

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        let hour = defaults.object(forKey: Self.hourKey) as? Int ?? 8
        let minute = defaults.object(forKey: Self.minuteKey) as? Int ?? 0
        let schedule = LocalReminderSchedule(hour: hour, minute: minute) ??
            LocalReminderSchedule(hour: 8, minute: 0)!
        selectedTime = Calendar.current.date(from: schedule.dateComponents) ?? Date()
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        Task { await restoreExistingPreference() }
    }

    func setTime(_ date: Date) {
        guard let schedule = LocalReminderSchedule.from(date) else {
            status = "That time could not be saved. The current reminder was not changed."
            return
        }
        selectedTime = date
        defaults.set(schedule.hour, forKey: Self.hourKey)
        defaults.set(schedule.minute, forKey: Self.minuteKey)
        guard isEnabled else {
            status = "Reminder time saved on this iPhone. It is not scheduled until you enable the reminder."
            return
        }
        Task { await scheduleReminder(schedule) }
    }

    func enable() {
        status = "Requesting notification permission from iOS."
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.isEnabled = false
                    self.defaults.set(false, forKey: Self.enabledKey)
                    self.status = "iOS could not enable notifications. No reminder is scheduled."
                    _ = error
                    return
                }
                guard granted else {
                    self.isEnabled = false
                    self.defaults.set(false, forKey: Self.enabledKey)
                    self.status = "Notifications are not allowed. No reminder is scheduled; you can change this in iPhone Settings."
                    return
                }
                let components = Calendar.current.dateComponents([.hour, .minute], from: self.selectedTime)
                guard let schedule = LocalReminderSchedule(hour: components.hour ?? -1,
                                                           minute: components.minute ?? -1) else {
                    self.status = "Reminder time is invalid. No reminder is scheduled."
                    return
                }
                await self.scheduleReminder(schedule)
            }
        }
    }

    func disable() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
        status = "Daily reminder turned off on this iPhone."
    }

    private func restoreExistingPreference() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            guard isEnabled else { return }
            let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
            guard let schedule = LocalReminderSchedule(hour: components.hour ?? -1,
                                                       minute: components.minute ?? -1) else {
                isEnabled = false
                defaults.set(false, forKey: Self.enabledKey)
                status = "Saved reminder time is invalid. No reminder is scheduled."
                return
            }
            await scheduleReminder(schedule)
        case .denied:
            if isEnabled {
                isEnabled = false
                defaults.set(false, forKey: Self.enabledKey)
            }
            status = "Notifications are off in iPhone Settings. No reminder is scheduled."
        case .notDetermined:
            status = "Choose Enable to ask iOS for notification permission."
        @unknown default:
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            status = "Notification status is unavailable. No reminder is scheduled."
        }
    }

    private func scheduleReminder(_ schedule: LocalReminderSchedule) async {
        let content = UNMutableNotificationContent()
        content.title = "PD Bridge reminder"
        content.body = "A reminder you scheduled is ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: schedule.dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger)
        do {
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            try await center.add(request)
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            let time = Calendar.current.date(from: schedule.dateComponents)?.formatted(date: .omitted, time: .shortened)
                ?? "the selected time"
            status = "Daily reminder scheduled for \(time) on this iPhone. Delivery depends on iOS notification settings and may be delayed or missed."
        } catch {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            status = "iOS did not schedule the reminder. No reminder is active; try again later."
        }
    }
}
