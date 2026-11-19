import Foundation
import Security

let now = Date(timeIntervalSince1970: 1_782_000_000)
let record = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    kind: .fall,
    originalText: "Fictional: પડ્યું اردو",
    savedText: "Fictional: પડ્યું اردو",
    occurredAt: now,
    recordedAt: now,
    origin: .appleHealth,
    sourceRecordID: "fictional-source-1",
    confirmation: .userConfirmed,
    previousWording: []
)
let candidate = ExternalEventCandidate(
    source: "appleHealth", sourceRecordID: "fictional-source-1",
    occurredAt: now, count: 1, sourceLabel: "Fictional historical source"
)
assert(ObservationDeduplication.isDuplicate(candidate, in: [record]))
assert(!ObservationDeduplication.isDuplicate(ExternalEventCandidate(
    source: "appleHealth", sourceRecordID: "fictional-source-2",
    occurredAt: now, count: 2, sourceLabel: "Fictional historical source"
), in: [record]))
let encoded = try JSONEncoder().encode([record])
let restored = try JSONDecoder().decode([Observation].self, from: encoded)
assert(restored == [record])
assert(restored[0].originalText == "Fictional: પડ્યું اردو")
assert(ObservationSearch.matches(record, query: "اردو", kindLabel: "fall", sourceLabel: "Fictional source"))
assert(ObservationSearch.matches(record, query: "fictional", kindLabel: "fall", sourceLabel: "Fictional source"))
assert(!ObservationSearch.matches(record, query: "not present", kindLabel: "fall", sourceLabel: "Fictional source"))
let fictionalAudio = Data([0x50, 0x44, 0x42, 0x52, 0x49, 0x44, 0x47, 0x45])
let voiceAttachment = try VoiceNoteAttachment(audioData: fictionalAudio, spokenLanguage: .kutchi, durationSeconds: 2.5)
let retaggedVoiceAttachment = try voiceAttachment.replacingSpokenLanguage(with: .gujarati)
assert(retaggedVoiceAttachment.spokenLanguage == .gujarati)
assert(retaggedVoiceAttachment.audioData == voiceAttachment.audioData)
assert(retaggedVoiceAttachment.durationSeconds == voiceAttachment.durationSeconds)
let voiceObservation = Observation(
    id: UUID(), kind: .note,
    originalText: "Voice note (original audio retained; not transcribed)",
    savedText: "Voice note (original audio retained; not transcribed)",
    occurredAt: now, recordedAt: now, origin: .manual,
    sourceRecordID: nil, confirmation: .userConfirmed, previousWording: [],
    includeInAppointment: true, voiceNote: voiceAttachment
)
let restoredVoice = try JSONDecoder().decode(Observation.self, from: JSONEncoder().encode(voiceObservation))
assert(restoredVoice.voiceNote == voiceAttachment)
assert(restoredVoice.voiceNote?.audioData == fictionalAudio)
assert(ObservationSearch.matches(restoredVoice, query: "Kutchi", kindLabel: "note", sourceLabel: "manual"))
do {
    _ = try VoiceNoteAttachment(audioData: Data(), spokenLanguage: .unspecified, durationSeconds: 1)
    preconditionFailure("Empty audio was accepted")
} catch ObservationServiceError.invalidVoiceNote {}
do {
    _ = try VoiceNoteAttachment(audioData: Data(repeating: 0, count: VoiceNoteAttachment.maximumAudioBytes + 1),
                                spokenLanguage: .english, durationSeconds: 1)
    preconditionFailure("Oversized audio was accepted")
} catch ObservationServiceError.invalidVoiceNote {}
let voiceReport = AppointmentReport.text(
    from: [restoredVoice], kindLabel: { $0.rawValue }, sourceLabel: { $0.rawValue },
    dateLabel: { _ in "fictional time" }
)
assert(voiceReport.contains("Original audio retained on this iPhone; not transcribed"))
assert(voiceReport.contains("not embedded in this printable report"))
let voiceBackupPassphrase = "fictional-voice-backup-2026"
let voiceBackup = try ObservationBackup.seal(
    ObservationArchive(observations: [restoredVoice], processedSourceKeys: []),
    passphrase: voiceBackupPassphrase
)
assert(String(data: voiceBackup, encoding: .utf8)?.contains("PDBRIDGE") != true,
       "Audio marker text must not appear in the encrypted backup")
let restoredVoiceBackup = try ObservationBackup.open(voiceBackup, passphrase: voiceBackupPassphrase)
assert(restoredVoiceBackup.observations.first?.voiceNote?.audioData == fictionalAudio)
let voiceMemoryVault = MemoryVault()
let voiceService = try ObservationService(vault: voiceMemoryVault)
let savedVoiceID = try voiceService.addVoiceNote(audioData: fictionalAudio, spokenLanguage: .kutchi, durationSeconds: 2.5)
assert(voiceService.observations.first?.id == savedVoiceID)
let deletedVoice = try voiceService.remove(savedVoiceID)
assert(voiceService.observations.isEmpty)
try voiceService.undoRemoval(deletedVoice)
assert(voiceService.observations.first?.voiceNote?.audioData == fictionalAudio)
let oldObservationJSON = """
{"id":"00000000-0000-0000-0000-000000000002","kind":"note","originalText":"old archive","savedText":"old archive","occurredAt":1782000000,"recordedAt":1782000000,"origin":"manual","sourceRecordID":null,"confirmation":"userConfirmed","previousWording":[],"includeInAppointment":false}
"""
let oldObservation = try JSONDecoder().decode(Observation.self, from: Data(oldObservationJSON.utf8))
assert(oldObservation.voiceNote == nil, "Archives created before voice notes must still open")
let reminderTime = LocalReminderSchedule(hour: 7, minute: 5)!
assert(reminderTime.dateComponents.hour == 7 && reminderTime.dateComponents.minute == 5)
assert(LocalReminderSchedule(hour: 23, minute: 59) != nil)
assert(LocalReminderSchedule(hour: 24, minute: 0) == nil)
assert(LocalReminderSchedule(hour: 8, minute: 60) == nil)
assert(NativeStrings.text("Unknown test label", languageCode: "gu") == "Unknown test label")
assert(NativeStrings.observationKindTitle(.fall, languageCode: "en") == "Fall")
assert(NativeStrings.observationKindTitle(.nearFall, languageCode: "en") == "Near-fall")
assert(NativeStrings.observationKindTitle(.movement, languageCode: "en") == "Movement / other")
var scriptedTalk = NativeScriptedTalkDraft()
assert(scriptedTalk.noteText == nil, "An empty scripted conversation must not create a note")
scriptedTalk.select(99, for: 0)
assert(scriptedTalk.noteText == nil, "Invalid fixed-choice indexes must be ignored")
scriptedTalk.select(1, for: 0)
scriptedTalk.select(2, for: 1)
scriptedTalk.select(0, for: 2)
assert(scriptedTalk.noteText == "Fictional scripted demonstration. A fictional near-fall happened while turning. Sample time: Evening. The fictional person noticed it. Selected from fixed sample choices; no speech was captured, transcribed, or interpreted.")
scriptedTalk.select(nil, for: 1)
let skippedTimeSample = scriptedTalk.noteText!
assert(!skippedTimeSample.contains("Sample time:"), "Skipped optional answers must not be filled in")
assert(skippedTimeSample.contains("A fictional near-fall happened while turning."))
print("Observation contract smoke: passed")

let receiptTestID = UUID()
for state in FictionalWatchReceiptState.allCases {
    let response = FictionalWatchReceipt(eventID: receiptTestID, state: state)
    let parsedResponse = try FictionalWatchReceipt.parse(response.message)
    assert(parsedResponse == response)
}
var invalidReceipt = FictionalWatchReceipt(eventID: receiptTestID, state: .stored).message
invalidReceipt["note"] = "not allowed"
do {
    _ = try FictionalWatchReceipt.parse(invalidReceipt)
    preconditionFailure("Watch response accepted unrestricted content")
} catch FictionalWatchEventError.invalidPayload {}

final class MemoryVault: ObservationVault {
    var archive = ObservationArchive(observations: [], processedSourceKeys: [])
    var failNextSave = false
    var failNextDelete = false
    var nextSaveError: Error?
    func loadArchive() throws -> ObservationArchive { archive }
    func saveArchive(_ candidate: ObservationArchive, intent: ObservationSaveIntent) throws {
        if let error = nextSaveError {
            nextSaveError = nil
            throw error
        }
        if failNextSave {
            failNextSave = false
            throw VaultErrorForTest.failed
        }
        archive = candidate
    }
    func deleteAll() throws {
        if failNextDelete {
            failNextDelete = false
            throw VaultErrorForTest.failed
        }
        archive = ObservationArchive(observations: [], processedSourceKeys: [])
    }
}

final class BlockingDeletionVault: ObservationVault {
    var archive = ObservationArchive(observations: [], processedSourceKeys: [])
    let deletionEntered = DispatchSemaphore(value: 0)
    let resumeDeletion = DispatchSemaphore(value: 0)
    func loadArchive() throws -> ObservationArchive { archive }
    func saveArchive(_ candidate: ObservationArchive, intent: ObservationSaveIntent) throws {
        archive = candidate
    }
    func deleteAll() throws {
        deletionEntered.signal()
        resumeDeletion.wait()
        archive = ObservationArchive(observations: [], processedSourceKeys: [])
    }
}
enum VaultErrorForTest: Error { case failed }

let vault = MemoryVault()
let service = try ObservationService(vault: vault)
let watchEvent = FictionalWatchEvent(id: UUID(), occurredAt: now)
var message = watchEvent.message
message["note"] = "This must not cross the watch boundary"
do {
    _ = try service.receiveWatch(message, at: now)
    preconditionFailure("Unrestricted content was accepted")
} catch FictionalWatchEventError.invalidPayload {}

// A disconnected watch may deliver a queued event two hours after it occurred.
vault.failNextSave = true
do {
    _ = try service.receiveWatch(watchEvent.message, at: now.addingTimeInterval(7200))
    preconditionFailure("Storage failure was reported as success")
} catch VaultErrorForTest.failed {}
precondition(service.observations.isEmpty)
precondition(vault.archive.processedSourceKeys.isEmpty)

let arrival = try service.receiveWatch(watchEvent.message, at: now.addingTimeInterval(7200))
guard case .inserted(let receivedID) = arrival else { preconditionFailure("No watch event inserted") }
precondition(service.observations.count == 1)
precondition(service.observations[0].confirmation == .pendingReview)
precondition(service.observations[0].origin == .fictionalWatch)
precondition(service.observations[0].sourceRecordID == watchEvent.id.uuidString)
precondition(service.observations[0].occurredAt == now)
precondition(service.observations[0].recordedAt == now.addingTimeInterval(7200))
precondition(service.reportObservations.isEmpty)
do {
    try service.setIncluded(receivedID, included: true)
    preconditionFailure("An unconfirmed watch event entered the report")
} catch ObservationServiceError.pending {}
let repeated = try service.receiveWatch(watchEvent.message, at: now.addingTimeInterval(7200))
precondition(repeated == .duplicate)

// Simulate app restart from the same encrypted archive contract.
let restarted = try ObservationService(vault: vault)
precondition(restarted.observations.count == 1)
try restarted.confirm(receivedID)
try restarted.setIncluded(receivedID, included: true)
precondition(restarted.reportObservations.map(\.id) == [receivedID])
let removed = try restarted.remove(receivedID)
precondition(restarted.observations.isEmpty)
let repeatedAfterDelete = try restarted.receiveWatch(watchEvent.message, at: now.addingTimeInterval(7200))
precondition(repeatedAfterDelete == .duplicate)
try restarted.undoRemoval(removed)
precondition(restarted.reportObservations.count == 1)

var watchOutbox = FictionalWatchOutbox()
let queuedEvent = PendingFictionalEvent(id: watchEvent.id, occurredAt: watchEvent.occurredAt)
watchOutbox.enqueue(queuedEvent)
watchOutbox.enqueue(queuedEvent)
precondition(watchOutbox.events == [queuedEvent])
let queuedRoundTrip = try JSONDecoder().decode(FictionalWatchOutbox.self, from: JSONEncoder().encode(watchOutbox))
precondition(queuedRoundTrip == watchOutbox)
let queueDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("pdbridge-watch-outbox-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: queueDirectory) }
let queueStore = FictionalWatchOutboxStore(directoryURL: queueDirectory)
try queueStore.save(watchOutbox)
var restartedWatchOutbox = try queueStore.load()
precondition(restartedWatchOutbox == watchOutbox)
precondition(restartedWatchOutbox.acknowledge(queuedEvent.id))
try queueStore.save(restartedWatchOutbox)
let acknowledgedQueue = try queueStore.load()
precondition(acknowledgedQueue.events.isEmpty)
precondition(!watchOutbox.acknowledge(UUID()))
precondition(watchOutbox.acknowledge(queuedEvent.id))
precondition(watchOutbox.events.isEmpty)
precondition(watchOutbox.lastResult == .stored)
precondition(watchOutbox.lastResultEventID == queuedEvent.id)
let terminalOutboxData = try JSONEncoder().encode(watchOutbox)
let terminalOutbox = try JSONDecoder().decode(FictionalWatchOutbox.self, from: terminalOutboxData)
precondition(terminalOutbox == watchOutbox)
let legacyQueue = Data("{\"version\":1,\"events\":[]}".utf8)
let decodedLegacyQueue = try JSONDecoder().decode(FictionalWatchOutbox.self, from: legacyQueue)
precondition(decodedLegacyQueue.events.isEmpty)

var rejectedOutbox = FictionalWatchOutbox()
precondition(rejectedOutbox.enqueue(PendingFictionalEvent(id: receiptTestID, occurredAt: now)))
precondition(rejectedOutbox.complete(receiptTestID, with: .rejectedStale))
precondition(rejectedOutbox.events.isEmpty)
precondition(rejectedOutbox.lastResult == .rejectedStale)
let rejectedOutboxAfterRestart = try JSONDecoder().decode(
    FictionalWatchOutbox.self,
    from: JSONEncoder().encode(rejectedOutbox)
)
precondition(rejectedOutboxAfterRestart.lastResult == .rejectedStale)
precondition(rejectedOutboxAfterRestart.lastResultEventID == receiptTestID)
precondition(!FictionalWatchReceiptState.diaryNotStarted.isTerminal)

let transferJourneyVault = MemoryVault()
let transferJourney = try ObservationService(vault: transferJourneyVault)
let transferJourneyEvent = FictionalWatchEvent(id: UUID(), occurredAt: now)
var transferJourneyQueue = FictionalWatchOutbox()
precondition(transferJourneyQueue.enqueue(PendingFictionalEvent(
    id: transferJourneyEvent.id, occurredAt: transferJourneyEvent.occurredAt
)))
let receivedState = FictionalWatchReceipt(eventID: transferJourneyEvent.id, state: .received)
let parsedReceivedState = try FictionalWatchReceipt.parse(receivedState.message)
precondition(parsedReceivedState.state == .received)
transferJourneyVault.failNextSave = true
do {
    _ = try transferJourney.receiveWatch(transferJourneyEvent.message, at: now.addingTimeInterval(2))
    preconditionFailure("Simulated failed save did not fail")
} catch VaultErrorForTest.failed {}
let retryState = FictionalWatchReceipt(eventID: transferJourneyEvent.id, state: .retry)
let parsedRetryState = try FictionalWatchReceipt.parse(retryState.message)
precondition(parsedRetryState.state == .retry)
precondition(transferJourneyQueue.events.count == 1)
let transferReceipt = try transferJourney.receiveWatch(transferJourneyEvent.message, at: now.addingTimeInterval(2))
guard case .inserted = transferReceipt else { preconditionFailure("Retry did not persist Watch event") }
let storedState = FictionalWatchReceipt(eventID: transferJourneyEvent.id, state: .stored)
precondition(transferJourneyQueue.complete(transferJourneyEvent.id, with: storedState.state))
precondition(transferJourneyQueue.events.isEmpty)
precondition(transferJourneyQueue.lastResult == .stored)
precondition(!transferJourneyQueue.complete(transferJourneyEvent.id, with: .retry))
let duplicateAfterStored = try transferJourney.receiveWatch(transferJourneyEvent.message, at: now.addingTimeInterval(2))
precondition(duplicateAfterStored == .duplicate)
let outboxFile = queueDirectory.appendingPathComponent("fictional-outbox-v1.json")
let corruptQueue = Data("corrupt fictional queue".utf8)
try corruptQueue.write(to: outboxFile, options: .atomic)
do {
    _ = try queueStore.load()
    preconditionFailure("Corrupt watch outbox was accepted")
} catch FictionalWatchOutboxStoreError.invalidOutbox {}
let retainedCorruptQueue = try Data(contentsOf: outboxFile)
precondition(retainedCorruptQueue == corruptQueue)

var cappedQueue = FictionalWatchOutbox(events: (0..<FictionalWatchOutbox.maximumPendingEvents).map { _ in
    PendingFictionalEvent(id: UUID(), occurredAt: now)
})
precondition(!cappedQueue.enqueue(queuedEvent))

precondition(NativeStrings.text("Home", languageCode: "en") == "Home")
precondition(NativeStrings.text("Home", languageCode: "gu") == "ઘર")
precondition(NativeStrings.text("Home", languageCode: "hi") == "होम")
precondition(NativeStrings.text("Home", languageCode: "ur") == "ہوم")
precondition(NativeStrings.text("Plan", languageCode: "en") == "Plan")
precondition(NativeStrings.text("Plan", languageCode: "gu") == "યોજના")
precondition(NativeStrings.text("Plan", languageCode: "hi") == "योजना")
precondition(NativeStrings.text("Plan", languageCode: "ur") == "منصوبہ")
precondition(NativeStrings.text("Untranslated future string", languageCode: "ur") == "Untranslated future string")
precondition(NativeStrings.text("Home", languageCode: "invalid") == "Home")
precondition(NativeLanguage.gujarati.pickerTitle.contains("draft, unreviewed"))
precondition(NativeLanguage.urdu.localeIdentifier == "ur-PK")

let backupPassphrase = "fictional-test-passphrase-2026"
let backupSourceKey = Observation.sourceKey(origin: record.origin, recordID: record.sourceRecordID!)
let backupArchive = ObservationArchive(observations: [record], processedSourceKeys: [backupSourceKey])
let backupData = try ObservationBackup.seal(backupArchive, passphrase: backupPassphrase)
precondition(String(data: backupData, encoding: .utf8)?.contains(record.originalText) != true)
let openedBackup = try ObservationBackup.open(backupData, passphrase: backupPassphrase)
precondition(openedBackup == backupArchive)
do {
    _ = try ObservationBackup.open(backupData, passphrase: "different-fictional-passphrase")
    preconditionFailure("Wrong backup passphrase was accepted")
} catch ObservationBackupError.malformedFile {}
let emptyArchive = ObservationArchive(observations: [], processedSourceKeys: [])
let mergedBackup = try ObservationBackup.merge(openedBackup, into: emptyArchive)
precondition(mergedBackup == openedBackup)
var conflictingRecord = openedBackup.observations[0]
conflictingRecord.savedText += " changed in conflicting backup"
let idCollision = ObservationArchive(
    observations: [conflictingRecord],
    processedSourceKeys: openedBackup.processedSourceKeys
)
do {
    _ = try ObservationBackup.merge(idCollision, into: openedBackup)
    preconditionFailure("Conflicting backup record ID was silently overwritten")
} catch ObservationBackupError.recordConflict {}
do {
    _ = try ObservationBackup.seal(emptyArchive, passphrase: "short")
    preconditionFailure("Weak passphrase was accepted")
} catch ObservationBackupError.weakPassphrase {}

let importVault = MemoryVault()
let importService = try ObservationService(vault: importVault)
try importService.importEncryptedBackup(backupData, passphrase: backupPassphrase)
try importService.importEncryptedBackup(backupData, passphrase: backupPassphrase)
precondition(importService.observations == [record])
do {
    try importService.importEncryptedBackup(backupData, passphrase: "wrong-fictional-passphrase")
    preconditionFailure("Failed backup password changed the imported archive")
} catch ObservationBackupError.malformedFile {}
precondition(importService.observations == [record])

// End-to-end platform-neutral user journey: create a note, find its earlier
// wording in History search, correct it, then select it for Appointment.
let noteJourneyVault = MemoryVault()
let noteJourney = try ObservationService(vault: noteJourneyVault)
let noteOriginal = "Fictional: Gujarati ગુજરાતી, Hindi हिन्दी and Urdu اردو note"
let journeyNoteID = try noteJourney.addManual(kind: .note, text: noteOriginal, at: now)
let createdNote = noteJourney.observations.first(where: { $0.id == journeyNoteID })!
precondition(ObservationSearch.matches(createdNote, query: "ગુજરાતી", kindLabel: "note", sourceLabel: "Entered here"))
let noteCorrection = noteOriginal + " corrected in English"
try noteJourney.edit(journeyNoteID, text: noteCorrection)
let correctedNote = noteJourney.observations.first(where: { $0.id == journeyNoteID })!
precondition(correctedNote.savedText == noteCorrection)
precondition(correctedNote.originalText == noteOriginal)
precondition(correctedNote.previousWording == [noteOriginal])
precondition(correctedNote.priorCorrections.isEmpty)
let finalNoteCorrection = noteCorrection + " corrected again"
try noteJourney.edit(journeyNoteID, text: finalNoteCorrection)
let twiceCorrectedNote = noteJourney.observations.first(where: { $0.id == journeyNoteID })!
precondition(twiceCorrectedNote.originalText == noteOriginal)
precondition(twiceCorrectedNote.previousWording == [noteOriginal, noteCorrection])
precondition(twiceCorrectedNote.priorCorrections == [noteCorrection])
precondition(ObservationSearch.matches(twiceCorrectedNote, query: "corrected in English", kindLabel: "note", sourceLabel: "Entered here"))
var reportSelectedMultilingualNote = twiceCorrectedNote
reportSelectedMultilingualNote.includeInAppointment = true
let multilingualReport = AppointmentReport.text(
    from: [reportSelectedMultilingualNote],
    kindLabel: { $0.rawValue },
    sourceLabel: { $0.rawValue },
    dateLabel: { _ in "fictional time" }
)
for script in ["ગુજરાતી", "हिन्दी", "اردو"] {
    precondition(multilingualReport.contains(script), "Appointment report changed original Unicode text: \(script)")
}
try noteJourney.setIncluded(journeyNoteID, included: true)
precondition(noteJourney.reportObservations.map(\.savedText) == [finalNoteCorrection])
let excludedNoteID = try noteJourney.addManual(kind: .note, text: "Fictional reminder kept out of this report", at: now.addingTimeInterval(60))
precondition(noteJourney.observations.contains { $0.id == excludedNoteID })
precondition(!noteJourney.reportObservations.contains { $0.id == excludedNoteID })
try noteJourney.setIncluded(journeyNoteID, included: false)
precondition(noteJourney.reportObservations.isEmpty, "Setting an entry aside must not delete it or leave it in the appointment report")
precondition(noteJourney.observations.count == 2)
try noteJourney.setIncluded(journeyNoteID, included: true)
let journeyBackup = try noteJourney.encryptedBackup(passphrase: backupPassphrase)
let recoveredJourneyVault = MemoryVault()
let recoveredJourney = try ObservationService(vault: recoveredJourneyVault)
try recoveredJourney.importEncryptedBackup(journeyBackup, passphrase: backupPassphrase)
let recoveredCorrectedNote = recoveredJourney.observations.first { $0.id == journeyNoteID }!
precondition(recoveredCorrectedNote.originalText == noteOriginal)
precondition(recoveredCorrectedNote.savedText == finalNoteCorrection)
precondition(recoveredCorrectedNote.previousWording == [noteOriginal, noteCorrection])
precondition(recoveredCorrectedNote.includeInAppointment)
precondition(recoveredJourney.observations.first { $0.id == excludedNoteID }?.includeInAppointment == false)
precondition(recoveredJourney.reportObservations.map(\.id) == [journeyNoteID], "Backup recovery must restore report inclusion without adding set-aside entries")

// One canonical report selection is used for factual counts and printed output.
let delayedWatchEntry = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
    kind: .fall,
    originalText: "Fictional original wording",
    savedText: "Fictional corrected wording",
    occurredAt: now,
    recordedAt: now.addingTimeInterval(3600),
    origin: .fictionalWatch,
    sourceRecordID: "fictional-watch-source-11",
    confirmation: .userConfirmed,
    previousWording: ["Fictional original wording", "Fictional first correction"],
    includeInAppointment: true
)
let selectedNote = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
    kind: .note,
    originalText: "Fictional selected note",
    savedText: "Fictional selected note",
    occurredAt: now.addingTimeInterval(60),
    recordedAt: now.addingTimeInterval(60),
    origin: .manual,
    sourceRecordID: nil,
    confirmation: .userConfirmed,
    previousWording: [],
    includeInAppointment: true
)
let sameTimeLaterReceivedNote = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
    kind: .note,
    originalText: "Fictional same-time note",
    savedText: "Fictional same-time note",
    occurredAt: selectedNote.occurredAt,
    recordedAt: selectedNote.recordedAt.addingTimeInterval(60),
    origin: .manual,
    sourceRecordID: nil,
    confirmation: .userConfirmed,
    previousWording: [],
    includeInAppointment: true
)
let setAsideNote = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
    kind: .note,
    originalText: "Fictional set-aside note",
    savedText: "Fictional set-aside note",
    occurredAt: now,
    recordedAt: now,
    origin: .manual,
    sourceRecordID: nil,
    confirmation: .userConfirmed,
    previousWording: [],
    includeInAppointment: false
)
let pendingWatchEntry = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
    kind: .fall,
    originalText: "Fictional pending watch event",
    savedText: "Fictional pending watch event",
    occurredAt: now,
    recordedAt: now.addingTimeInterval(120),
    origin: .fictionalWatch,
    sourceRecordID: "fictional-pending-watch-source-14",
    confirmation: .pendingReview,
    previousWording: [],
    includeInAppointment: true
)
let reportInput = [delayedWatchEntry, setAsideNote, pendingWatchEntry, selectedNote, sameTimeLaterReceivedNote]
let selectedReportEntries = AppointmentReport.selectedEntries(from: reportInput)
precondition(selectedReportEntries.map(\.id) == [sameTimeLaterReceivedNote.id, selectedNote.id, delayedWatchEntry.id])
let factualReport = AppointmentReport.text(
    from: reportInput,
    kindLabel: { $0.rawValue },
    sourceLabel: { $0.rawValue },
    dateLabel: { "t\(Int($0.timeIntervalSince1970))" }
)
precondition(factualReport.contains("fall: 1") && factualReport.contains("note: 2"))
precondition(!factualReport.contains("nearFall:") && !factualReport.contains("pendingReview"))
precondition(factualReport.contains("Occurred: t\(Int(now.timeIntervalSince1970)) · fall · fictionalWatch"))
precondition(factualReport.contains("Recorded in PD Bridge: t\(Int(now.addingTimeInterval(3600).timeIntervalSince1970))"))
precondition(factualReport.contains("Source reference: fictional-watch-source-11"))
precondition(factualReport.contains("Recorded wording: Fictional corrected wording"))
precondition(factualReport.contains("Originally recorded: Fictional original wording"))
precondition(factualReport.contains("Earlier wording 1: Fictional first correction"))
precondition(!factualReport.contains("Earlier wording 2:"), "Initial wording must not be repeated as an earlier correction")
precondition(!factualReport.contains("Fictional set-aside note"))

let manualRecordedAt = now.addingTimeInterval(7200)
let manualNote = Observation(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
    kind: .note,
    originalText: "Fictional event described as having happened yesterday.",
    savedText: "Fictional event described as having happened yesterday.",
    occurredAt: manualRecordedAt,
    recordedAt: manualRecordedAt,
    origin: .manual,
    sourceRecordID: nil,
    confirmation: .userConfirmed,
    previousWording: [],
    includeInAppointment: true
)
let manualReport = AppointmentReport.text(
    from: [manualNote],
    kindLabel: { $0.rawValue },
    sourceLabel: { $0.rawValue },
    dateLabel: { "t\(Int($0.timeIntervalSince1970))" }
)
precondition(manualReport.contains("Recorded in PD Bridge: t\(Int(manualRecordedAt.timeIntervalSince1970)) · note · manual"))
precondition(!manualReport.contains("Occurred:"), "A manual note's save timestamp must not be presented as a verified event time")
precondition(ObservationTimeLabels.secondaryRecorded(for: manualNote, dateLabel: { _ in "unused" }) == nil)

let revertedService = try ObservationService(vault: MemoryVault())
let revertedNoteID = try revertedService.addManual(kind: .note, text: "Fictional reverted original", at: now)
try revertedService.edit(revertedNoteID, text: "Fictional interim correction")
try revertedService.edit(revertedNoteID, text: "Fictional second correction")
try revertedService.edit(revertedNoteID, text: "Fictional reverted original")
try revertedService.setIncluded(revertedNoteID, included: true)
let revertedNote = revertedService.observations.first { $0.id == revertedNoteID }!
precondition(revertedNote.originalText == "Fictional reverted original")
precondition(revertedNote.savedText == "Fictional reverted original")
precondition(revertedNote.priorCorrections == ["Fictional interim correction", "Fictional second correction"])
let revertedReport = AppointmentReport.text(
    from: revertedService.observations,
    kindLabel: { $0.rawValue },
    sourceLabel: { $0.rawValue },
    dateLabel: { "t\(Int($0.timeIntervalSince1970))" }
)
precondition(revertedReport.contains("Originally recorded: Fictional reverted original"))
precondition(revertedReport.contains("Earlier wording 1: Fictional interim correction"),
             "A correction history must remain visible when wording is later restored to the original")

let removedNote = try noteJourney.remove(journeyNoteID)
precondition(noteJourney.reportObservations.isEmpty)
precondition(noteJourney.observations.contains { $0.id == excludedNoteID }, "Removing a report item must not remove unrelated set-aside notes")
precondition(!AppointmentReport.selectedEntries(from: noteJourney.observations).contains { $0.id == journeyNoteID })
try noteJourney.undoRemoval(removedNote)
precondition(noteJourney.reportObservations.map(\.savedText) == [finalNoteCorrection])
let removedAgain = try noteJourney.remove(journeyNoteID)
precondition(noteJourney.reportObservations.isEmpty)
precondition(removedAgain.id == journeyNoteID)
// A deliberate import of an older external backup can restore a previously
// deleted local item and its prior appointment selection.
try noteJourney.importEncryptedBackup(journeyBackup, passphrase: backupPassphrase)
precondition(noteJourney.reportObservations.map(\.id) == [journeyNoteID])
precondition(noteJourney.observations.first { $0.id == excludedNoteID }?.includeInAppointment == false)
let restoredReport = AppointmentReport.text(
    from: noteJourney.observations,
    kindLabel: { $0.rawValue },
    sourceLabel: { $0.rawValue },
    dateLabel: { "t\(Int($0.timeIntervalSince1970))" }
)
precondition(restoredReport.contains("note: 1"))
precondition(!restoredReport.contains("Fictional reminder kept out of this report"))

let deletionFailureVault = MemoryVault()
let deletionFailureService = try ObservationService(vault: deletionFailureVault)
_ = try deletionFailureService.addManual(kind: .note, text: "Fictional delete failure")
deletionFailureVault.failNextDelete = true
do {
    try deletionFailureService.deleteAll()
    preconditionFailure("Failed deletion was reported as successful")
} catch VaultErrorForTest.failed {}
precondition(deletionFailureService.observations.isEmpty)
precondition(deletionFailureService.isDeletionPending)
do {
    _ = try deletionFailureService.addManual(kind: .note, text: "Must remain blocked")
    preconditionFailure("Write was accepted while deletion was pending")
} catch ObservationServiceError.deletionInProgress {}
do {
    try deletionFailureService.importEncryptedBackup(backupData, passphrase: backupPassphrase)
    preconditionFailure("Backup import was accepted while deletion was pending")
} catch ObservationServiceError.deletionInProgress {}
do {
    _ = try deletionFailureService.receiveWatch(watchEvent.message, at: now.addingTimeInterval(7200))
    preconditionFailure("Watch delivery was accepted while deletion was pending")
} catch ObservationServiceError.deletionInProgress {}
try deletionFailureService.deleteAll()
precondition(deletionFailureService.observations.isEmpty)
precondition(!deletionFailureService.isDeletionPending)

// Calls that arrive during deletion must fail, not wait and then recreate the
// diary after cleanup has completed.
let blockingVault = BlockingDeletionVault()
let blockingService = try ObservationService(vault: blockingVault)
_ = try blockingService.addManual(kind: .note, text: "Fictional concurrent deletion")
let deleteReturned = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    try? blockingService.deleteAll()
    deleteReturned.signal()
}
precondition(blockingVault.deletionEntered.wait(timeout: .now() + 3) == .success)
do {
    _ = try blockingService.addManual(kind: .note, text: "Must not wait behind deletion")
    preconditionFailure("A write that began during deletion was accepted")
} catch ObservationServiceError.deletionInProgress {}
do {
    try blockingService.importEncryptedBackup(backupData, passphrase: backupPassphrase)
    preconditionFailure("An import that began during deletion was accepted")
} catch ObservationServiceError.deletionInProgress {}
do {
    try blockingService.deleteAll()
    preconditionFailure("A second concurrent delete was accepted")
} catch ObservationServiceError.deletionInProgress {}
blockingVault.resumeDeletion.signal()
precondition(deleteReturned.wait(timeout: .now() + 3) == .success)
precondition(blockingService.observations.isEmpty)

// Simulate iOS protected-data notifications and the Keychain's locked-device
// interaction error. No event is reported as stored until a retry persists it.
let lockedVault = MemoryVault()
let lockedService = try ObservationService(vault: lockedVault)
_ = try lockedService.addManual(kind: .note, text: "Fictional lock-state record")
let queuedDuringLock = FictionalWatchEvent(id: UUID(), occurredAt: Date())
let lockedDeliveryDate = queuedDuringLock.occurredAt.addingTimeInterval(1)
lockedService.protectedDataWillBecomeUnavailable()
precondition(lockedService.observations.isEmpty)
do {
    _ = try lockedService.receiveWatch(queuedDuringLock.message, at: lockedDeliveryDate)
    preconditionFailure("Watch event was accepted while protected data was unavailable")
} catch ObservationServiceError.protectedDataUnavailable {}
do {
    _ = try lockedService.addManual(kind: .note, text: "Must wait for unlock")
    preconditionFailure("Write was accepted while protected data was unavailable")
} catch ObservationServiceError.protectedDataUnavailable {}
try lockedService.protectedDataDidBecomeAvailable()
precondition(lockedService.observations.count == 1)

lockedVault.nextSaveError = VaultError.keyUnavailable(errSecInteractionNotAllowed)
do {
    _ = try lockedService.receiveWatch(queuedDuringLock.message, at: lockedDeliveryDate)
    preconditionFailure("Watch event was acknowledged after a simulated locked-Keychain failure")
} catch VaultError.keyUnavailable(let status) {
    precondition(status == errSecInteractionNotAllowed)
}
precondition(lockedService.observations.count == 1)
let retriedAfterUnlock = try lockedService.receiveWatch(queuedDuringLock.message, at: lockedDeliveryDate)
guard case .inserted = retriedAfterUnlock else { preconditionFailure("Event did not retry after unlock") }
precondition(lockedService.observations.count == 2)
let repeatedAfterLockedRetry = try lockedService.receiveWatch(queuedDuringLock.message, at: lockedDeliveryDate)
precondition(repeatedAfterLockedRetry == .duplicate)

try importService.deleteAll()
precondition(importService.observations.isEmpty)

let original = "Fictional: અમદાવાદ اردو हिन्दी"
let noteID = try restarted.addManual(kind: .note, text: original, at: now)
try restarted.edit(noteID, text: original + " corrected")
let corrected = restarted.observations.first(where: { $0.id == noteID })!
precondition(corrected.originalText == original)
precondition(corrected.previousWording == [original])
precondition(corrected.savedText == original + " corrected")
print("Fictional watch delivery, file-backed queue restart/deduplication/acknowledgment/corruption, failure recovery, encrypted backup/merge, and report contracts: passed")
