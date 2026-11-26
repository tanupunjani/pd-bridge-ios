import Foundation

/// A local, user-selected wall-clock reminder time. This contains no medication
/// name or dosage and is validated before it is scheduled with iOS.
struct LocalReminderSchedule: Equatable {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    static func from(_ date: Date, calendar: Calendar = .current) -> LocalReminderSchedule? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return LocalReminderSchedule(hour: hour, minute: minute)
    }
}

struct VoiceNoteAttachment: Codable, Equatable {
    enum SpokenLanguage: String, Codable, CaseIterable, Identifiable {
        case unspecified, english, gujarati, hindi, urdu, kutchi

        var id: String { rawValue }
        var label: String {
            switch self {
            case .unspecified: return "Not specified"
            case .english: return "English"
            case .gujarati: return "Gujarati"
            case .hindi: return "Hindi"
            case .urdu: return "Urdu"
            case .kutchi: return "Kutchi"
            }
        }
    }

    static let maximumDuration: TimeInterval = 120
    static let maximumAudioBytes = 512 * 1024

    let audioData: Data
    let spokenLanguage: SpokenLanguage
    let durationSeconds: TimeInterval

    init(audioData: Data, spokenLanguage: SpokenLanguage, durationSeconds: TimeInterval) throws {
        guard !audioData.isEmpty,
              audioData.count <= Self.maximumAudioBytes,
              durationSeconds.isFinite,
              durationSeconds > 0,
              durationSeconds <= Self.maximumDuration else {
            throw ObservationServiceError.invalidVoiceNote
        }
        self.audioData = audioData
        self.spokenLanguage = spokenLanguage
        self.durationSeconds = durationSeconds
    }

    func replacingSpokenLanguage(with language: SpokenLanguage) throws -> VoiceNoteAttachment {
        try VoiceNoteAttachment(audioData: audioData,
                                spokenLanguage: language,
                                durationSeconds: durationSeconds)
    }

    var isValid: Bool {
        !audioData.isEmpty && audioData.count <= Self.maximumAudioBytes &&
        durationSeconds.isFinite && durationSeconds > 0 && durationSeconds <= Self.maximumDuration
    }
}

enum VaultError: Error {
    case keyUnavailable(Int32)
    case invalidArchive
    case deletionIntentUnavailable
    case deletionPending
    case deletedVaultRequiresUserAction
    case staleWatchEvent
}

// Platform-neutral record. External input remains pending until the person confirms it.
struct Observation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case note, fall, nearFall, freezing, tremor, movement, otherSymptom }
    enum Origin: String, Codable, CaseIterable { case manual, appleHealth, fictionalWatch }
    enum Confirmation: String, Codable { case pendingReview, userConfirmed }

    let id: UUID
    let kind: Kind
    let originalText: String
    var savedText: String
    let occurredAt: Date
    let recordedAt: Date
    let origin: Origin
    let sourceRecordID: String?
    var confirmation: Confirmation
    var previousWording: [String]
    var includeInAppointment: Bool
    var voiceNote: VoiceNoteAttachment?

    init(id: UUID, kind: Kind, originalText: String, savedText: String,
         occurredAt: Date, recordedAt: Date, origin: Origin,
         sourceRecordID: String?, confirmation: Confirmation,
         previousWording: [String], includeInAppointment: Bool = false,
         voiceNote: VoiceNoteAttachment? = nil) {
        self.id = id
        self.kind = kind
        self.originalText = originalText
        self.savedText = savedText
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.origin = origin
        self.sourceRecordID = sourceRecordID
        self.confirmation = confirmation
        self.previousWording = previousWording
        self.includeInAppointment = includeInAppointment
        self.voiceNote = voiceNote
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, originalText, savedText, occurredAt, recordedAt
        case origin, sourceRecordID, confirmation, previousWording, includeInAppointment, voiceNote
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        originalText = try values.decode(String.self, forKey: .originalText)
        savedText = try values.decode(String.self, forKey: .savedText)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        origin = try values.decode(Origin.self, forKey: .origin)
        sourceRecordID = try values.decodeIfPresent(String.self, forKey: .sourceRecordID)
        confirmation = try values.decode(Confirmation.self, forKey: .confirmation)
        previousWording = try values.decode([String].self, forKey: .previousWording)
        includeInAppointment = try values.decodeIfPresent(Bool.self, forKey: .includeInAppointment) ?? false
        voiceNote = try values.decodeIfPresent(VoiceNoteAttachment.self, forKey: .voiceNote)
    }

    var hasValidVoiceNote: Bool {
        guard let voiceNote else { return true }
        return kind == .note && voiceNote.isValid
    }

    static func sourceKey(origin: Origin, recordID: String) -> String {
        return origin.rawValue + ":" + recordID
    }

    /// The initial wording is already shown separately. Older archives also
    /// store it as the first prior value after the first edit, so omit that one
    /// duplicate here while retaining every later correction in order.
    var priorCorrections: [String] {
        guard previousWording.first == originalText else { return previousWording }
        return Array(previousWording.dropFirst())
    }
}

enum ObservationSearch {
    static func matches(_ observation: Observation, query: String,
                        kindLabel: String, sourceLabel: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let searchable = [observation.savedText, observation.originalText,
                          observation.voiceNote?.spokenLanguage.label ?? ""] + observation.previousWording +
            [kindLabel, sourceLabel]
        return searchable.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

enum ObservationTimeLabels {
    /// Manual notes do not have a separate event-time field, so the diary's
    /// timestamp is the time it was recorded. External events can carry a
    /// source occurrence time and a later receipt time.
    static func primary(for observation: Observation, dateLabel: (Date) -> String) -> String {
        if observation.origin == .manual {
            return "Recorded in PD Bridge: \(dateLabel(observation.recordedAt))"
        }
        return "Occurred: \(dateLabel(observation.occurredAt))"
    }

    static func secondaryRecorded(for observation: Observation,
                                  dateLabel: (Date) -> String) -> String? {
        guard observation.origin != .manual,
              observation.recordedAt != observation.occurredAt else { return nil }
        return "Recorded in PD Bridge: \(dateLabel(observation.recordedAt))"
    }

    static func primaryDisplay(for observation: Observation) -> String {
        primary(for: observation) { $0.formatted(date: .abbreviated, time: .shortened) }
    }

    static func secondaryRecordedDisplay(for observation: Observation) -> String? {
        secondaryRecorded(for: observation) { $0.formatted(date: .abbreviated, time: .shortened) }
    }
}

/// The Appointment screen and print/export output use the same eligibility and
/// ordering rules so displayed counts cannot drift from the generated report.
enum AppointmentReport {
    private static let kinds: [Observation.Kind] = [.fall, .nearFall, .freezing, .tremor, .movement, .otherSymptom, .note]

    static func orderedEntries(from observations: [Observation]) -> [Observation] {
        observations.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt > rhs.recordedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func selectedEntries(from observations: [Observation]) -> [Observation] {
        orderedEntries(from: observations.filter {
            $0.confirmation == .userConfirmed && $0.includeInAppointment
        })
    }

    /// Builds a factual text report from the same selected entries used by the
    /// UI. A delayed external event records both when it occurred and when this
    /// diary received it; unchanged manual entries avoid a redundant second time.
    static func text(from observations: [Observation],
                     kindLabel: (Observation.Kind) -> String,
                     sourceLabel: (Observation.Origin) -> String,
                     dateLabel: (Date) -> String) -> String {
        let entries = selectedEntries(from: observations)
        guard !entries.isEmpty else { return "" }

        let totals = kinds.compactMap { kind -> String? in
            let count = entries.filter { $0.kind == kind }.count
            return count > 0 ? "\(kindLabel(kind)): \(count)" : nil
        }
        let lines = entries.map { item in
            var parts = [
                "\(ObservationTimeLabels.primary(for: item, dateLabel: dateLabel)) · \(kindLabel(item.kind)) · \(sourceLabel(item.origin))",
                "Recorded wording: \(item.savedText)"
            ]
            if let recorded = ObservationTimeLabels.secondaryRecorded(for: item, dateLabel: dateLabel) {
                parts.append(recorded)
            }
            if let sourceRecordID = item.sourceRecordID {
                parts.append("Source reference: \(sourceRecordID)")
            }
            if let voiceNote = item.voiceNote {
                parts.append("Original audio retained on this iPhone; not transcribed. Spoken language tag: \(voiceNote.spokenLanguage.label). Audio is not embedded in this printable report.")
            }
            if item.savedText != item.originalText || !item.priorCorrections.isEmpty {
                parts.append("Originally recorded: \(item.originalText)")
                parts += item.priorCorrections.enumerated().map {
                    "Earlier wording \($0.offset + 1): \($0.element)"
                }
            }
            return parts.joined(separator: "\n")
        }
        return (["PD Bridge — selected observations", "Factual list for appointment preparation", ""] +
                totals + [""] + lines).joined(separator: "\n\n")
    }
}

struct ObservationArchive: Equatable {
    var observations: [Observation]
    // A deleted watch event's opaque source key remains so delayed repeat delivery
    // cannot silently resurrect it. No note text is retained in this tombstone.
    var processedSourceKeys: Set<String>
}

enum ObservationSaveIntent {
    case ordinary
    case explicitUserAction
    case watchDelivery(occurredAt: Date)
}

protocol ObservationVault {
    func loadArchive() throws -> ObservationArchive
    func saveArchive(_ archive: ObservationArchive, intent: ObservationSaveIntent) throws
    func deleteAll() throws
}

struct ExternalEventCandidate: Equatable {
    let source: String
    let sourceRecordID: String
    let occurredAt: Date
    let count: Int
    let sourceLabel: String
}

protocol ExternalEventSource {
    var sourceID: String { get }
    func historicalCandidates() throws -> [ExternalEventCandidate]
}

enum ObservationDeduplication {
    static func isDuplicate(_ candidate: ExternalEventCandidate, in observations: [Observation]) -> Bool {
        return observations.contains { item in
            item.origin.rawValue == candidate.source && item.sourceRecordID == candidate.sourceRecordID
        }
    }
}
