import Foundation

/// Build-specific copy keeps the local synthetic demo distinct from the V1
/// distribution build without changing the underlying capture workflows.
enum NativeBuildCopy {
#if PD_BRIDGE_SYNTHETIC_BUILD
    static let demoWarning: String? = "Fictional-data build. Do not enter real health information."
    static let homeIntro = "A simple place for fictional observations before an appointment."
    static let quickEventsHeading = "Fictional quick events"
    static let quickEventsDescription = "Each shortcut saves one clearly marked fictional entry on this iPhone."
    static let quickEventHint = "Saves one fixed fictional event on this iPhone"
    static let quickEventSavedNotice = "Fictional event saved on this iPhone."
    static let historyEmpty = "Write a note on Home or save one of the fictional quick events. Your entries stay on this iPhone."
    static let appointmentPreparationHint = "Review entries in History and confirm any fictional Watch event before preparing an appointment list."
    static let appointmentDisclaimer = "This is a factual list of selected fictional entries, not a clinical summary."
    static let noteTitle = "Fictional note"
    static let noteAccessibilityLabel = "Fictional note text"
    static let emptyNoteError = "Enter a fictional note before saving."
    static let confirmEventLabel = "Confirm fictional event"
    static let talkDemoAvailable = true
    static let watchDemoAvailable = true
    static let watchEventSavedNotice: String? = "Fictional watch event saved on this iPhone. Review it in History."
    static let privacyNotice = "This synthetic build is for fictional data only. Observations and voice recordings stay in this app’s encrypted on-device vault. Voice recordings are not transcribed or uploaded; a short protected temporary file is removed after review, and abandoned staging files are cleaned up on the next app start. Reminder preferences are stored locally; no medication names or doses are collected. There are no accounts, cloud sync, analytics, HealthKit access, network requests, or third-party services. Encrypted backups include saved audio notes, but not reminder settings. For a caregiver call, you type a name and number in Help, review them in PD Bridge, then tap Open Phone yourself. Those details stay only temporarily in the Help screen and are not saved by PD Bridge; Phone may ask for another confirmation. PD Bridge does not call anyone automatically, share location, or monitor emergencies. The fictional Watch demonstration sends only its fixed test event ID and time through Apple WatchConnectivity. A device-only deletion timestamp remains after clearing entries so older queued Watch events cannot restore them."
#else
    static let demoWarning: String? = nil
    static let homeIntro = "A simple place to keep observations for an appointment."
    static let quickEventsHeading = "Quick events"
    static let quickEventsDescription = "Save a manual event with one tap. PD Bridge does not detect events automatically."
    static let quickEventHint = "Records this event manually. It does not detect falls or movement."
    static let quickEventSavedNotice = "Manual event saved on this iPhone."
    static let historyEmpty = "Write a note on Home or record a manual event. Your entries stay on this iPhone."
    static let appointmentPreparationHint = "Review entries in History before preparing an appointment list."
    static let appointmentDisclaimer = "This list shows entries you selected. It is not a clinical summary."
    static let noteTitle = "Write a note"
    static let noteAccessibilityLabel = "Note text"
    static let emptyNoteError = "Enter a note before saving."
    static let confirmEventLabel = "Confirm event"
    static let talkDemoAvailable = false
    static let watchDemoAvailable = false
    static let watchEventSavedNotice: String? = nil
    static let privacyNotice = "Your saved observations and optional voice recordings are stored in encrypted files in PD Bridge’s private on-device vault. The vault files are excluded from iPhone and iCloud device backups. Its encryption key is kept in this iPhone’s device-only Keychain and is available only while the device is unlocked. If the iPhone is lost or erased and you do not have a usable encrypted export, the diary cannot be recovered. Voice notes are recorded only after you start recording; audio is not transcribed or uploaded. Temporary audio is protected and removed after review or on a later app start if abandoned. App preferences such as interface language, Comfort Mode, and the generic reminder time are stored separately in iOS app settings and may be included in a device backup. Reminders contain no medication name or dose; delivery can be delayed or missed. PD Bridge has no account, hosted diary, analytics, advertising, external AI, HealthKit access, or automatic fall detection. Encrypted exports are created only when you choose Export and are saved through the Files provider you select; that provider may sync the encrypted file. PD Bridge cannot remove exported copies. Delete one entry in History, or delete the local diary in Settings. Local deletion does not promise physical overwriting of flash storage. Help details are entered temporarily, are not saved by PD Bridge, and open Phone only after you tap Open Phone. PD Bridge does not share location, call automatically, monitor emergencies, diagnose, or recommend treatment."
#endif

    static func quickEventText(for kind: Observation.Kind) -> String? {
#if PD_BRIDGE_SYNTHETIC_BUILD
        let entries: [Observation.Kind: String] = [
            .fall: "Fictional fall test event.",
            .nearFall: "Fictional near-fall test event.",
            .freezing: "Fictional freezing test event.",
            .movement: "Fictional movement test event."
        ]
#else
        let entries: [Observation.Kind: String] = [
            .fall: "Fall recorded manually.",
            .nearFall: "Near-fall recorded manually.",
            .freezing: "Freezing recorded manually.",
            .movement: "Movement observation recorded manually."
        ]
#endif
        return entries[kind]
    }
}

enum NativeLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case gujarati = "gu"
    case hindi = "hi"
    case urdu = "ur"

    var id: String { rawValue }
    var localeIdentifier: String {
        switch self {
        case .english: return "en-CA"
        case .gujarati: return "gu-IN"
        case .hindi: return "hi-IN"
        case .urdu: return "ur-PK"
        }
    }

    var pickerTitle: String {
        switch self {
        case .english: return "English"
        case .gujarati: return "Gujarati — draft, unreviewed"
        case .hindi: return "Hindi — draft, unreviewed"
        case .urdu: return "Urdu — draft, unreviewed"
        }
    }
}

/// Small maintainable string table for the native fictional demonstration.
/// English is the fallback; Gujarati, Hindi, and Urdu values are drafts only.
enum NativeStrings {
    private static let drafts: [NativeLanguage: [String: String]] = [
        .gujarati: [
            "Home": "ઘર", "History": "ઇતિહાસ", "Appointment": "મુલાકાતની તૈયારી", "Plan": "યોજના",
            "Settings": "સેટિંગ્સ", "Write a note": "નોંધ લખો", "Fictional quick events": "કાલ્પનિક ઝડપી ઘટનાઓ", "Quick events": "ઝડપી ઘટનાઓ",
            "fall": "પડવું", "nearFall": "પડતાં બચવું", "freezing": "ચાલવામાં અટકાવ", "movement": "હલનચલન", "note": "નોંધ",
            "Search entries": "નોંધો શોધો", "All": "બધું", "Needs review": "સમીક્ષા જરૂરી", "Confirmed": "પુષ્ટિ કરેલ",
            "Include in appointment": "મુલાકાતની તૈયારીમાં ઉમેરો", "Edit": "સંપાદિત કરો", "Delete": "કાઢી નાખો",
            "Confirm fictional event": "કાલ્પનિક ઘટનાની પુષ્ટિ કરો", "Discard event": "ઘટના કાઢી નાખો",
            "Original wording and corrections": "મૂળ શબ્દો અને સુધારા", "Print or save report": "રિપોર્ટ છાપો અથવા સાચવો",
            "Comfort Mode": "આરામદાયક મોડ", "Done": "થઈ ગયું", "Save": "સાચવો", "Cancel": "રદ કરો",
            "Create encrypted backup": "એન્ક્રિપ્ટેડ બેકઅપ બનાવો", "Choose encrypted backup file": "એન્ક્રિપ્ટેડ બેકઅપ ફાઇલ પસંદ કરો",
            "Import and merge": "આયાત કરો અને જોડો", "Delete all observations": "બધી નોંધો કાઢી નાખો"
        ],
        .hindi: [
            "Home": "होम", "History": "इतिहास", "Appointment": "मुलाक़ात की तैयारी", "Plan": "योजना",
            "Settings": "सेटिंग्स", "Write a note": "नोट लिखें", "Fictional quick events": "काल्पनिक त्वरित घटनाएँ", "Quick events": "त्वरित घटनाएँ",
            "fall": "गिरना", "nearFall": "लगभग गिरना", "freezing": "चलने में रुकावट", "movement": "गतिविधि", "note": "नोट",
            "Search entries": "प्रविष्टियाँ खोजें", "All": "सभी", "Needs review": "समीक्षा ज़रूरी", "Confirmed": "पुष्टि की गई",
            "Include in appointment": "मुलाक़ात की तैयारी में जोड़ें", "Edit": "बदलें", "Delete": "हटाएँ",
            "Confirm fictional event": "काल्पनिक घटना की पुष्टि करें", "Discard event": "घटना हटाएँ",
            "Original wording and corrections": "मूल शब्द और सुधार", "Print or save report": "रिपोर्ट प्रिंट या सेव करें",
            "Comfort Mode": "आराम मोड", "Done": "हो गया", "Save": "सेव करें", "Cancel": "रद्द करें",
            "Create encrypted backup": "एन्क्रिप्टेड बैकअप बनाएँ", "Choose encrypted backup file": "एन्क्रिप्टेड बैकअप फ़ाइल चुनें",
            "Import and merge": "इम्पोर्ट और मिलाएँ", "Delete all observations": "सभी प्रविष्टियाँ हटाएँ"
        ],
        .urdu: [
            "Home": "ہوم", "History": "تاریخ", "Appointment": "ملاقات کی تیاری", "Plan": "منصوبہ",
            "Settings": "ترتیبات", "Write a note": "نوٹ لکھیں", "Fictional quick events": "فرضی فوری واقعات", "Quick events": "فوری واقعات",
            "fall": "گرنا", "nearFall": "قریب الوقوع گرنا", "freezing": "چلنے میں جمود", "movement": "حرکت", "note": "نوٹ",
            "Search entries": "اندراجات تلاش کریں", "All": "سب", "Needs review": "جائزہ درکار", "Confirmed": "تصدیق شدہ",
            "Include in appointment": "ملاقات کی تیاری میں شامل کریں", "Edit": "ترمیم", "Delete": "حذف کریں",
            "Confirm fictional event": "فرضی واقعے کی تصدیق کریں", "Discard event": "واقعہ حذف کریں",
            "Original wording and corrections": "اصل الفاظ اور اصلاحات", "Print or save report": "رپورٹ پرنٹ یا محفوظ کریں",
            "Comfort Mode": "آرام دہ موڈ", "Done": "مکمل", "Save": "محفوظ کریں", "Cancel": "منسوخ",
            "Create encrypted backup": "خفیہ کردہ بیک اپ بنائیں", "Choose encrypted backup file": "خفیہ کردہ بیک اپ فائل منتخب کریں",
            "Import and merge": "درآمد اور ضم کریں", "Delete all observations": "تمام اندراجات حذف کریں"
        ]
    ]

    static func text(_ key: String, languageCode: String) -> String {
        guard let language = NativeLanguage(rawValue: languageCode), language != .english else { return key }
        return drafts[language]?[key] ?? key
    }

    static func observationKindTitle(_ kind: Observation.Kind, languageCode: String) -> String {
        let key = kind.rawValue
        let localized = text(key, languageCode: languageCode)
        if localized != key { return localized }
        switch kind {
        case .fall: return "Fall"
        case .nearFall: return "Near-fall"
        case .freezing: return "Freezing"
        case .movement: return "Movement / other"
        case .note: return "Note"
        }
    }
}

/// Safe sample content for the optional scripted Talk demonstration.
/// State contains only fixed-choice indexes; it cannot carry arbitrary user text.
struct NativeScriptedTalkDraft: Equatable {
    static let eventOptions = [
        "A fictional pause happened during a walk.",
        "A fictional near-fall happened while turning.",
        "A fictional change in hand movement was noticed."
    ]
    static let timeOptions = ["Morning", "Afternoon", "Evening"]
    static let reporterOptions = ["The fictional person noticed it.", "A fictional care partner noticed it."]

    private(set) var eventIndex: Int?
    private(set) var timeIndex: Int?
    private(set) var reporterIndex: Int?

    func question(for step: Int) -> String {
        switch step {
        case 0: return "Which fixed fictional example should this sample describe?"
        case 1: return "When in the fictional sample did it happen?"
        default: return "Who noticed it in the fictional sample?"
        }
    }

    func options(for step: Int) -> [String] {
        switch step {
        case 0: return Self.eventOptions
        case 1: return Self.timeOptions
        default: return Self.reporterOptions
        }
    }

    func selection(for step: Int) -> Int? {
        switch step {
        case 0: return eventIndex
        case 1: return timeIndex
        default: return reporterIndex
        }
    }

    mutating func select(_ index: Int?, for step: Int) {
        let validIndex = index.flatMap { options(for: step).indices.contains($0) ? $0 : nil }
        switch step {
        case 0: eventIndex = validIndex
        case 1: timeIndex = validIndex
        default: reporterIndex = validIndex
        }
    }

    var noteText: String? {
        guard let eventIndex, Self.eventOptions.indices.contains(eventIndex) else { return nil }
        var sentences = ["Fictional scripted demonstration.", Self.eventOptions[eventIndex]]
        if let timeIndex, Self.timeOptions.indices.contains(timeIndex) {
            sentences.append("Sample time: \(Self.timeOptions[timeIndex]).")
        }
        if let reporterIndex, Self.reporterOptions.indices.contains(reporterIndex) {
            sentences.append(Self.reporterOptions[reporterIndex])
        }
        sentences.append("Selected from fixed sample choices; no speech was captured, transcribed, or interpreted.")
        return sentences.joined(separator: " ")
    }
}
