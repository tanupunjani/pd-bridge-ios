import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum Palette {
    static let page = adaptive(light: UIColor(red: 0.949, green: 0.973, blue: 0.961, alpha: 1),
                               dark: UIColor(red: 0.055, green: 0.090, blue: 0.078, alpha: 1))
    static let surface = adaptive(light: .white,
                                  dark: UIColor(red: 0.105, green: 0.145, blue: 0.128, alpha: 1))
    static let ink = adaptive(light: UIColor(red: 0.110, green: 0.188, blue: 0.173, alpha: 1), dark: .white)
    // Use a lighter teal for text and controls in dark appearance; keep the
    // dark-green action fill fixed so white button labels remain high contrast.
    static let teal = adaptive(light: UIColor(red: 0.086, green: 0.373, blue: 0.333, alpha: 1),
                               dark: UIColor(red: 0.42, green: 0.78, blue: 0.67, alpha: 1))
    static let actionFill = Color(red: 0.086, green: 0.373, blue: 0.333)
    static let onAction = Color.white
    static let line = Color(uiColor: .separator)
    static let danger = adaptive(light: UIColor(red: 0.573, green: 0.204, blue: 0.169, alpha: 1),
                                 dark: UIColor(red: 1.0, green: 0.43, blue: 0.38, alpha: 1))

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct ActionStyle: ButtonStyle {
    @AppStorage("pdbridge.comfortMode") private var comfortMode = false
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(comfortMode
                ? .system(.title3, design: .default, weight: .semibold)
                : .body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: comfortMode ? 64 : 56)
            .padding(.horizontal, 12)
            .foregroundColor(prominent ? Palette.onAction : (destructive ? Palette.danger : Palette.teal))
            .background((prominent ? Palette.actionFill : Palette.surface)
                .opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: prominent ? 0 : 1))
    }
}

private struct DemoBanner: View {
    @EnvironmentObject private var model: DiaryModel
    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let warning = NativeBuildCopy.demoWarning {
                Text(warning)
            }
            if let error = model.storageError {
                Text(error).foregroundColor(Palette.danger)
                Button(model.isDeletionPending ? "Retry deletion" : "Retry local storage") {
                    if model.isDeletionPending { _ = model.deleteAll() }
                    else { model.retryProtectedStorage() }
                }
                .buttonStyle(ActionStyle(destructive: model.isDeletionPending))
                .disabled(!model.canRetryStorage)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        Group {
            if NativeBuildCopy.demoWarning != nil || model.storageError != nil {
                content
            }
        }
    }
}

private struct NoticeBanner: View {
    let message: String
    let tone: DiaryNoticeTone

    private var color: Color {
        switch tone {
        case .success: return Palette.teal
        case .info: return Palette.ink
        case .error: return Palette.danger
        }
    }

    private var symbol: String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
                Text("Welcome to PD Bridge")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("A private place to keep observations in your own words and prepare a factual list for an appointment.")
                    .font(.body)
                Text("Your saved diary stays encrypted on this iPhone. PD Bridge does not diagnose, detect falls automatically, or monitor emergencies.")
                    .font(.body)
                Button("Get started", action: onStart)
                    .buttonStyle(ActionStyle(prominent: true))
                    .accessibilityIdentifier("welcome.getStarted")
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .foregroundColor(Palette.ink)
        .background(Palette.page.ignoresSafeArea())
    }
}

struct MainTabs: View {
    @State private var showSettings = false
    @State private var selectedTab = 0
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: NativeLanguage { NativeLanguage(rawValue: languageCode) ?? .english }

    var body: some View {
        ZStack {
            NavigationStack {
                HomeView()
                    .toolbar { settingsToolbar }
            }
            .toolbarBackground(Palette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .opacity(selectedTab == 0 ? 1 : 0)
            .allowsHitTesting(selectedTab == 0)
            .accessibilityHidden(selectedTab != 0)

            NavigationStack {
                HistoryView()
                    .toolbar { settingsToolbar }
            }
            .toolbarBackground(Palette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .opacity(selectedTab == 1 ? 1 : 0)
            .allowsHitTesting(selectedTab == 1)
            .accessibilityHidden(selectedTab != 1)

            NavigationStack {
                AppointmentView(onOpenHistory: { selectedTab = 1 })
                    .toolbar { settingsToolbar }
            }
            .toolbarBackground(Palette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .opacity(selectedTab == 2 ? 1 : 0)
            .allowsHitTesting(selectedTab == 2)
            .accessibilityHidden(selectedTab != 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Palette.teal)
        .foregroundColor(Palette.ink)
        .onChange(of: selectedTab) { _, _ in
            // Each destination is kept alive in the shared ZStack. Resign the
            // active field when switching destinations so its keyboard cannot
            // remain over the newly selected screen.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomNavigation(selectedTab: $selectedTab, languageCode: languageCode)
        }
        .background(Palette.page.ignoresSafeArea())
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .environment(\.layoutDirection, language == .urdu ? .rightToLeft : .leftToRight)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .toolbarBackground(Palette.page, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .foregroundColor(Palette.ink)
                .tint(Palette.teal)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .environment(\.layoutDirection, language == .urdu ? .rightToLeft : .leftToRight)
        }
    }

    @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Label(NativeStrings.text("Settings", languageCode: languageCode), systemImage: "gearshape")
            }
            .accessibilityLabel(NativeStrings.text("Settings", languageCode: languageCode))
        }
    }
}

private struct NativeBottomNavigation: View {
    @Binding var selectedTab: Int
    let languageCode: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let destinations: [(title: String, symbol: String)] = [
        ("Home", "house"),
        ("History", "clock.arrow.circlepath"),
        ("Appointment", "doc.text")
    ]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 2) {
                    ForEach(destinations.indices, id: \.self) { destinationButton(at: $0) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(destinations.indices, id: \.self) { destinationButton(at: $0) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Palette.page.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line).frame(height: 1).accessibilityHidden(true)
        }
    }

    private func destinationButton(at index: Int) -> some View {
        let destination = destinations[index]
        let title = NativeStrings.text(destination.title, languageCode: languageCode)
        let visibleTitle = dynamicTypeSize.isAccessibilitySize && destination.title == "Appointment"
            ? NativeStrings.text("Plan", languageCode: languageCode)
            : title
        let isSelected = selectedTab == index
        return Button { selectedTab = index } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(visibleTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: destination.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(visibleTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(nil)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundColor(isSelected ? Palette.teal : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 4)
            .background(isSelected ? Palette.teal.opacity(0.12) : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("tab.\(destination.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: DiaryModel
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @AppStorage("pdbridge.comfortMode") private var comfortMode = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeSheet: HomeSheet?

    private var usesSingleColumn: Bool { comfortMode || dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DemoBanner().id("home-top")
                    Text(NativeStrings.text("Keep what matters", languageCode: languageCode))
                        .font(.largeTitle.bold())
                        .foregroundColor(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(NativeBuildCopy.homeIntro)
                            .font(.body)
                    }
                    Button(NativeStrings.text("Write a note", languageCode: languageCode)) { activeSheet = .note }
                        .buttonStyle(ActionStyle(prominent: true))
                        .accessibilityIdentifier("home.writeNote")
                        .disabled(!model.canWrite)
                    Button("Record a voice note") { activeSheet = .voice }
                        .buttonStyle(ActionStyle())
                        .disabled(!model.canWrite)
                        .accessibilityHint("Record an optional clip up to two minutes. The original audio stays in the encrypted on-device vault and is not transcribed.")
                    if let notice = model.notice {
                        NoticeBanner(message: notice, tone: model.noticeTone)
                    }
                    Text(NativeStrings.text(NativeBuildCopy.quickEventsHeading, languageCode: languageCode))
                        .font(.title2.bold())
                    Text(NativeBuildCopy.quickEventsDescription)
                        .font(.callout)
                    LazyVGrid(columns: usesSingleColumn
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach([Observation.Kind.fall, .nearFall, .freezing, .movement], id: \.rawValue) { kind in
                            Button(kind.title(languageCode: languageCode)) { _ = model.addQuickEvent(kind) }
                                .buttonStyle(ActionStyle())
                                .disabled(!model.canWrite)
                                .accessibilityLabel(kind.title(languageCode: languageCode))
                                .accessibilityHint(NativeBuildCopy.quickEventHint)
                        }
                    }
                    if NativeBuildCopy.talkDemoAvailable {
                    Button("Try scripted Talk demo (English)") { activeSheet = .talk }
                        .buttonStyle(ActionStyle())
                        .accessibilityIdentifier("home.talkDemo")
                        .accessibilityHint("Optional local text-only demonstration using fixed fictional choices. No microphone or AI is used.")
                    }
                    Button("Call a caregiver") { activeSheet = .help }
                        .buttonStyle(ActionStyle())
                        .accessibilityIdentifier("home.help")
                        .accessibilityHint("Enter caregiver details, review them, then choose Open Phone yourself if you want to continue. PD Bridge does not monitor emergencies or call anyone automatically.")
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .foregroundColor(Palette.ink)
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 176 : 64)
            }
            .background(Palette.page)
            .navigationTitle("PD Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $activeSheet, onDismiss: {
                scrollProxy.scrollTo("home-top", anchor: .top)
            }) { destination in
                switch destination {
                case .note: NoteEditor(item: nil)
                case .talk:
#if PD_BRIDGE_SYNTHETIC_BUILD
                    ScriptedTalkDemoView(onClose: { activeSheet = nil })
#else
                    EmptyView()
#endif
                case .voice: VoiceNoteRecorderView()
                case .help: HelpView()
                }
            }
        }
    }
}

private enum HomeSheet: String, Identifiable {
    case note
    case talk
    case voice
    case help
    var id: String { rawValue }
}

private struct HistoryView: View {
    @EnvironmentObject private var model: DiaryModel
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing: Observation?
    @State private var query = ""
    @State private var filter = HistoryFilter.all

    private var filteredEntries: [Observation] {
        model.observations.filter { item in
            let matchesFilter = filter == .all ||
                (filter == .needsReview && item.confirmation == .pendingReview) ||
                (filter == .confirmed && item.confirmation == .userConfirmed)
            let matchesQuery = ObservationSearch.matches(
                item,
                query: query,
                kindLabel: item.kind.title(languageCode: languageCode),
                sourceLabel: item.origin.sourceLabel
            )
            return matchesFilter && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoBanner()
                if let removed = model.lastRemoved {
                    Button {
                        model.undo()
                    } label: {
                        Label("Undo deletion of \(removed.kind.title(languageCode: languageCode))", systemImage: "arrow.uturn.backward")
                    }
                        .buttonStyle(ActionStyle())
                        .accessibilityHint("Restores the entry that was just deleted.")
                }
                if let notice = model.notice { NoticeBanner(message: notice, tone: model.noticeTone) }
                TextField(
                    NativeStrings.text("Search entries", languageCode: languageCode),
                    text: $query,
                    prompt: Text(NativeStrings.text("Search entries", languageCode: languageCode))
                        .foregroundColor(Palette.ink)
                )
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 56)
                    .accessibilityLabel("Search history entries")
                    .accessibilityHint("Searches current and earlier wording, event type, and source.")
                Picker("History filter", selection: $filter) {
                    ForEach(HistoryFilter.allCases, id: \.self) { option in
                        Text(option.title(languageCode: languageCode)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 56)
                .accessibilityLabel("Filter history")
                .accessibilityValue(filter.title(languageCode: languageCode))
                if model.observations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No entries yet", systemImage: "tray")
                            .font(.title3.bold())
                        Text(NativeBuildCopy.historyEmpty)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if filteredEntries.isEmpty {
                    Label("No entries match this search or filter.", systemImage: "magnifyingglass")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                ForEach(filteredEntries) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind.title(languageCode: languageCode)).font(.title3.bold())
                            Text(ObservationTimeLabels.primaryDisplay(for: item))
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            if let recorded = ObservationTimeLabels.secondaryRecordedDisplay(for: item) {
                                Text(recorded)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let voiceNote = item.voiceNote {
                            VoiceNotePlayerView(attachment: voiceNote)
                        } else {
                            Text(verbatim: item.savedText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(item.origin.sourceLabel)
                            .font(.footnote)
                        if item.savedText != item.originalText {
                            Label("Edited · original wording preserved", systemImage: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Palette.teal)
                        }
                        if item.origin == .fictionalWatch {
                            Text("Watch event ID: \(item.sourceRecordID ?? "Unavailable")")
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        if item.confirmation == .pendingReview {
                            Text("Needs your confirmation before appointment use")
                                .font(.footnote.weight(.bold))
                            Button(NativeStrings.text(NativeBuildCopy.confirmEventLabel, languageCode: languageCode)) { model.confirm(item.id) }
                                .buttonStyle(ActionStyle(prominent: true))
                                .disabled(!model.canWrite)
                            Button(NativeStrings.text("Discard event", languageCode: languageCode)) { model.remove(item.id) }
                                .buttonStyle(ActionStyle(destructive: true))
                                .disabled(!model.canWrite)
                        } else {
                            Toggle(NativeStrings.text("Include in appointment", languageCode: languageCode), isOn: Binding(
                                get: { model.observations.first(where: { $0.id == item.id })?.includeInAppointment ?? false },
                                set: { model.include(item.id, value: $0) }
                            ))
                            .tint(Palette.teal)
                            .frame(minHeight: 56)
                            .accessibilityIdentifier("history.includeInAppointment.\(item.id.uuidString)")
                            .accessibilityValue(item.includeInAppointment ? "Included in appointment" : "Set aside from appointment")
                            .disabled(!model.canWrite)
                        }
                        if item.savedText != item.originalText || !item.previousWording.isEmpty {
                            DisclosureGroup(NativeStrings.text("Original wording and corrections", languageCode: languageCode)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Originally recorded")
                                        .font(.caption.weight(.semibold))
                                    Text(verbatim: item.originalText)
                                    ForEach(item.priorCorrections.indices, id: \.self) { index in
                                        Text("Earlier wording \(index + 1)")
                                            .font(.caption.weight(.semibold))
                                        Text(verbatim: item.priorCorrections[index])
                                    }
                                }
                            }
                            .accessibilityHint("Shows the original wording and saved corrections")
                            .frame(minHeight: 56, alignment: .leading)
                        }
                        HStack(spacing: 10) {
                            if item.voiceNote == nil {
                                Button(NativeStrings.text("Edit", languageCode: languageCode)) { editing = item }
                                    .buttonStyle(ActionStyle())
                                    .disabled(!model.canWrite)
                            }
                            Button(NativeStrings.text("Delete", languageCode: languageCode)) { model.remove(item.id) }
                                .buttonStyle(ActionStyle(destructive: true))
                                .disabled(!model.canWrite)
                        }
                    }
                    .foregroundColor(Palette.ink)
                    .padding(16)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 176 : 64)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.page)
        .navigationTitle(NativeStrings.text("History", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.sensitiveStateGeneration) { _, _ in
            query = ""
            editing = nil
        }
        .sheet(item: $editing) { NoteEditor(item: $0) }
    }
}

private struct VoiceNotePlayerView: View {
    let attachment: VoiceNoteAttachment
    @StateObject private var playback = VoiceNotePlaybackController()

    private var durationLabel: String {
        let seconds = Int(attachment.durationSeconds.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Original voice note · not transcribed", systemImage: "waveform")
                .font(.body.weight(.semibold))
            Text("\(attachment.spokenLanguage.label) · \(durationLabel)")
                .font(.footnote)
            Button(playback.isPlaying ? "Stop playback" : "Play original audio") {
                playback.toggle(attachment)
            }
            .buttonStyle(ActionStyle())
            .accessibilityLabel(playback.isPlaying ? "Stop original voice note playback" : "Play original voice note")
            .accessibilityHint("Plays the saved recording on this iPhone. The recording has no transcript.")
            if !playback.status.isEmpty {
                Text(playback.status)
                    .font(.footnote)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.page)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDisappear { playback.stop() }
    }
}

private struct VoiceNoteRecorderView: View {
    @EnvironmentObject private var model: DiaryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var capture = LocalVoiceCapture()
    @State private var spokenLanguage = VoiceNoteAttachment.SpokenLanguage.unspecified
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DemoBanner()
                    Text("Voice note")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Record in any spoken language, including Gujarati, Hindi, or Kutchi. Transcription is not required. The original audio is saved in this iPhone’s encrypted vault and is not uploaded. The recording screen asks for microphone access only after you tap Start recording.")
                        .font(.body)
                    Picker("Spoken language (optional)", selection: $spokenLanguage) {
                        ForEach(VoiceNoteAttachment.SpokenLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 56)
                    .accessibilityLabel("Spoken language tag, optional. This does not translate or transcribe the recording.")

                    if capture.isRecording {
                        Text("Recording · \(capture.elapsedSeconds / 60):\(String(format: "%02d", capture.elapsedSeconds % 60))")
                            .font(.title2.bold())
                            .accessibilityLabel("Recording in progress, \(capture.elapsedSeconds) seconds")
                        Button("Stop and review") { capture.stopAndReview() }
                            .buttonStyle(ActionStyle(prominent: true))
                    } else if let recording = capture.reviewedRecording {
                        Label("Recording ready to review · not transcribed", systemImage: "waveform")
                            .font(.body.weight(.semibold))
                        Text("\(recording.spokenLanguage.label) · \(Int(recording.durationSeconds.rounded())) seconds")
                            .font(.footnote)
                        Button(capture.isPlaying ? "Stop playback" : "Play recording") {
                            capture.playReviewedRecording()
                        }
                        .buttonStyle(ActionStyle())
                        .accessibilityHint("Listen to the original recording before saving. No transcript is created.")
                        Button("Save voice note") {
                            guard model.addVoiceNote(recording) else { return }
                            saved = true
                            capture.discard()
                            dismiss()
                        }
                        .buttonStyle(ActionStyle(prominent: true))
                        .disabled(!model.canWrite)
                    } else {
                        Button(capture.isStarting ? "Waiting for permission…" : "Start recording") {
                            capture.start(language: spokenLanguage)
                        }
                        .buttonStyle(ActionStyle(prominent: true))
                        .disabled(!model.canWrite || capture.isStarting)
                    }

                    Text(capture.status)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)

                    Button("Discard recording and close", role: .cancel) {
                        capture.discard()
                        dismiss()
                    }
                    .buttonStyle(ActionStyle())
                }
                .foregroundColor(Palette.ink)
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
            .background(Palette.page)
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        capture.discard()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                if !saved { capture.discard() }
            }
            .onChange(of: spokenLanguage) { _, language in
                capture.updateSpokenLanguage(language)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && capture.isRecording {
                    capture.stopAndReview()
                }
            }
        }
    }
}

private struct HelpView: View {
    @EnvironmentObject private var model: DiaryModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: InputField?
    @State private var showCallReview = false
    @State private var caregiverName = ""
    @State private var caregiverPhone = ""

    private enum InputField: Hashable {
        case caregiverName
        case caregiverPhone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DemoBanner()
                    Text("Help")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("PD Bridge does not monitor emergencies, contact anyone automatically, or provide emergency response. If someone is in immediate danger, contact local emergency services directly.")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Palette.danger)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Enter caregiver details only when you want to place a call. PD Bridge does not save them, request or share your location, or place calls automatically. Review the details before choosing the separate Phone action.")
                        .font(.body)
                    TextField("Caregiver name", text: $caregiverName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 56)
                        .focused($focusedField, equals: .caregiverName)
                        .accessibilityLabel("Caregiver name")
                        .accessibilityHint("Used only for this call review. It is not saved.")
                        .accessibilityIdentifier("help.caregiverName")
                    TextField("Phone number", text: $caregiverPhone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 56)
                        .focused($focusedField, equals: .caregiverPhone)
                        .accessibilityLabel("Phone number")
                        .accessibilityHint("Enter at least three digits. The number is not saved.")
                        .accessibilityIdentifier("help.caregiverPhone")
                    if !caregiverPhone.isEmpty && !isValidPhone(caregiverPhone) {
                        Text("Enter 3–20 digits. Spaces, parentheses, periods, and hyphens are okay.")
                            .font(.callout)
                            .foregroundColor(Palette.danger)
                            .accessibilityLabel("Invalid phone number. Enter 3 to 20 digits.")
                            .accessibilityIdentifier("help.phoneValidationError")
                    }
                    Button("Review call details") {
                        focusedField = nil
                        showCallReview = true
                    }
                    .disabled(!canReviewCall)
                    .buttonStyle(ActionStyle(prominent: true))
                    .accessibilityHint("Shows the name and number before opening Phone. No call is placed by PD Bridge.")
                    .accessibilityIdentifier("help.reviewCallDetails")
                    Text("Name and number stay temporarily in this screen and are cleared when you leave Help.")
                        .font(.footnote)
                    if let notice = model.notice { NoticeBanner(message: notice, tone: model.noticeTone) }
                }
                .foregroundColor(Palette.ink)
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
            .background(Palette.page)
            .foregroundColor(Palette.ink)
            .tint(Palette.teal)
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityHint("Returns to Home without placing a call.")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("help.keyboardDone")
                }
            }
            .sheet(isPresented: $showCallReview) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Review call")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Caregiver: \(caregiverName.trimmingCharacters(in: .whitespacesAndNewlines))")
                            .accessibilityLabel("Caregiver: \(caregiverName.trimmingCharacters(in: .whitespacesAndNewlines))")
                            .accessibilityIdentifier("help.reviewCaregiverName")
                        Text("Phone number: \(normalizedPhone)")
                            .monospacedDigit()
                            .accessibilityLabel("Phone number: \(normalizedPhone)")
                            .accessibilityIdentifier("help.reviewPhoneNumber")
                        Text("PD Bridge will not call automatically. Open Phone only if these details are correct; the Phone app may show another confirmation.")
                            .font(.body)
                        Spacer(minLength: 12)
                        Button("Open Phone") {
                            showCallReview = false
                            openCaregiverCall()
                        }
                        .buttonStyle(ActionStyle(prominent: true))
                        .accessibilityIdentifier("help.openPhone")
                        Button("Cancel", role: .cancel) {
                            showCallReview = false
                            clearCallDetails()
                        }
                        .buttonStyle(ActionStyle())
                        .accessibilityIdentifier("help.cancelReview")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.page)
                    .foregroundColor(Palette.ink)
                    .navigationTitle("Review call")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .onDisappear {
                clearCallDetails()
            }
        }
    }

    private var normalizedPhone: String {
        let allowed = CharacterSet(charactersIn: "+0123456789*#,;")
        return String(caregiverPhone.unicodeScalars.filter { allowed.contains($0) })
    }

    private var canReviewCall: Bool {
        !caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidPhone(caregiverPhone)
    }

    private func isValidPhone(_ phone: String) -> Bool {
        let acceptedInput = CharacterSet(charactersIn: "+0123456789*#,;()- .")
        guard phone.unicodeScalars.allSatisfy({ acceptedInput.contains($0) }) else { return false }
        let normalized = Self.normalizedPhone(phone)
        let digits = normalized.unicodeScalars.filter { 48...57 ~= $0.value }.count
        let plusCount = normalized.filter { $0 == "+" }.count
        return (3...20).contains(digits)
            && plusCount <= 1
            && (plusCount == 0 || normalized.first == "+")
    }

    private static func normalizedPhone(_ phone: String) -> String {
        let allowed = CharacterSet(charactersIn: "+0123456789*#,;")
        return String(phone.unicodeScalars.filter { allowed.contains($0) })
    }

    private func clearCallDetails() {
        caregiverName = ""
        caregiverPhone = ""
    }

    private func openCaregiverCall() {
        let number = normalizedPhone
        guard canReviewCall else {
            model.showNotice("Enter a caregiver name and a valid phone number before reviewing.", tone: .error)
            return
        }
        var components = URLComponents()
        components.scheme = "tel"
        components.path = number
        guard let url = components.url else {
            model.showNotice("A call could not be opened. No call was placed.", tone: .error)
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            DispatchQueue.main.async {
                self.model.showNotice(
                    opened
                        ? "Phone opened. Review its call confirmation before calling."
                        : "This device cannot open a phone call. No call was placed.",
                    tone: opened ? .info : .error
                )
            }
        }
    }
}

private struct CountTile: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(count)")
                .font(.title2.bold())
            Text(title).font(.footnote.weight(.semibold))
        }
        .foregroundColor(Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count)")
    }
}

private struct AppointmentView: View {
    @EnvironmentObject private var model: DiaryModel
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @AppStorage("pdbridge.comfortMode") private var comfortMode = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onOpenHistory: () -> Void

    private var usesSingleColumn: Bool { comfortMode || dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DemoBanner()
                if let notice = model.notice { NoticeBanner(message: notice, tone: model.noticeTone) }
                let confirmedEntries = model.observations.filter { $0.confirmation == .userConfirmed }
                let entries = AppointmentReport.selectedEntries(from: model.observations)
                let availableEntries = confirmedEntries.filter { !$0.includeInAppointment }
                Text("Appointment preparation")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Button {
                    printFactualReport(entries, languageCode: languageCode)
                } label: {
                    Label(NativeStrings.text("Print or save report", languageCode: languageCode), systemImage: "printer")
                }
                .buttonStyle(ActionStyle(prominent: true))
                .disabled(entries.isEmpty || model.storageError != nil)

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(confirmedEntries.isEmpty ? "No confirmed entries yet" : "Nothing selected for this appointment yet",
                              systemImage: "doc.text.magnifyingglass")
                            .font(.title3.bold())
                        Text(confirmedEntries.isEmpty
                             ? NativeBuildCopy.appointmentPreparationHint
                             : "Your confirmed entries are still saved in History. Add only the items you want in this appointment list below.")
                            .font(.body)
                        if confirmedEntries.isEmpty {
                            Button("Review entries in History", action: onOpenHistory)
                                .buttonStyle(ActionStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text("Selected entry counts")
                    .font(.title2.bold())
                LazyVGrid(columns: usesSingleColumn
                    ? [GridItem(.flexible())]
                    : [GridItem(.adaptive(minimum: 126), spacing: 12)], spacing: 12) {
                    CountTile(title: "Selected entries", count: entries.count)
                    ForEach([Observation.Kind.fall, .nearFall, .freezing, .movement, .note], id: \.rawValue) { kind in
                        CountTile(title: kind.title(languageCode: languageCode), count: entries.filter { $0.kind == kind }.count)
                    }
                }
                ForEach(entries) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.kind.title(languageCode: languageCode)).font(.headline)
                        if let voiceNote = item.voiceNote {
                            VoiceNotePlayerView(attachment: voiceNote)
                        } else {
                            Text(verbatim: item.savedText)
                        }
                        Text("\(ObservationTimeLabels.primaryDisplay(for: item)) · \(item.origin.sourceLabel)")
                            .font(.footnote)
                        if let recorded = ObservationTimeLabels.secondaryRecordedDisplay(for: item) {
                            Text(recorded)
                                .font(.footnote)
                        }
                        if let sourceRecordID = item.sourceRecordID {
                            Text("Source reference: \(sourceRecordID)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if item.savedText != item.originalText {
                            Label("Edited in History; original wording is preserved there.", systemImage: "pencil")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Palette.teal)
                        }
                        Button("Set aside from this appointment") {
                            model.include(item.id, value: false)
                        }
                        .buttonStyle(ActionStyle())
                        .accessibilityHint("Keeps this entry in History but removes it from this appointment report.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !availableEntries.isEmpty {
                    Text("Saved in History, not in this report")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("These confirmed entries remain saved. Add one only if it belongs in this appointment list.")
                        .font(.callout)
                    ForEach(availableEntries) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.kind.title(languageCode: languageCode)).font(.headline)
                        if let voiceNote = item.voiceNote {
                            VoiceNotePlayerView(attachment: voiceNote)
                        } else {
                            Text(verbatim: item.savedText)
                        }
                            Text("\(ObservationTimeLabels.primaryDisplay(for: item)) · \(item.origin.sourceLabel)")
                                .font(.footnote)
                            if let recorded = ObservationTimeLabels.secondaryRecordedDisplay(for: item) {
                                Text(recorded)
                                    .font(.footnote)
                            }
                            if let sourceRecordID = item.sourceRecordID {
                                Text("Source reference: \(sourceRecordID)")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            Button("Add to this appointment") {
                                model.include(item.id, value: true)
                            }
                            .buttonStyle(ActionStyle(prominent: true))
                            .accessibilityHint("Includes this saved entry in the appointment report. It remains in History.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                Text(NativeBuildCopy.appointmentDisclaimer)
                    .font(.footnote)
            }
            .foregroundColor(Palette.ink)
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 176 : 64)
        }
        .background(Palette.page)
        .navigationTitle(NativeStrings.text("Appointment", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func printFactualReport(_ entries: [Observation], languageCode: String) {
        let text = AppointmentReport.text(
            from: entries,
            kindLabel: { $0.title(languageCode: languageCode) },
            sourceLabel: { $0.sourceLabel },
            dateLabel: { $0.formatted(date: .abbreviated, time: .shortened) }
        )
        guard !text.isEmpty else { return }
        let formatter = UISimpleTextPrintFormatter(text: text)
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "PD Bridge selected observations"
        info.outputType = .general
        controller.printInfo = info
        controller.printFormatter = formatter
        let presented = controller.present(animated: true) { _, completed, error in
            DispatchQueue.main.async {
                if error != nil {
                    model.showNotice(
                        "Print or export did not complete. Check the destination; no saved file is confirmed.",
                        tone: .error
                    )
                } else if completed {
                    model.showNotice(
                        "Print or export finished. Check the destination you chose for the report.",
                        tone: .success
                    )
                } else {
                    model.showNotice(
                        "Print or export closed before completion. The report may not have been saved.",
                        tone: .info
                    )
                }
            }
        }
        if presented {
            model.showNotice("Report options opened. Choose a destination; nothing is saved yet.")
        } else {
            model.showNotice(
                "The report print/export options could not be opened. Nothing was exported.",
                tone: .error
            )
        }
    }
}

private enum HistoryFilter: String, CaseIterable {
    case all
    case needsReview
    case confirmed

    func title(languageCode: String) -> String {
        switch self {
        case .all: return NativeStrings.text("All", languageCode: languageCode)
        case .needsReview: return NativeStrings.text("Needs review", languageCode: languageCode)
        case .confirmed: return NativeStrings.text("Confirmed", languageCode: languageCode)
        }
    }
}

private struct EncryptedBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: DiaryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pdbridge.comfortMode") private var comfortMode = false
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @State private var exportPassphrase = ""
    @State private var exportConfirmation = ""
    @State private var importPassphrase = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showExportConfirmation = false
    @State private var showImportConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var backupDocument = EncryptedBackupDocument(data: Data())
    @State private var importedBackup: Data?
    @StateObject private var medicationReminder = LocalMedicationReminderController()

    private var publishedPrivacyPolicyURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "PDBridgePrivacyPolicyURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DemoBanner()
                if let notice = model.notice { NoticeBanner(message: notice, tone: model.noticeTone) }
                Picker("Interface language", selection: $languageCode) {
                    ForEach(NativeLanguage.allCases) { language in
                        Text(language.pickerTitle).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Interface language. Gujarati, Hindi and Urdu are unreviewed drafts.")
                Text("Gujarati, Hindi and Urdu interface text is draft content and has not received fluent-speaker review. This changes interface labels only; it does not translate notes or change their wording.")
                    .font(.footnote)
                Toggle("Comfort Mode", isOn: $comfortMode)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 56)
                    .tint(Palette.teal)
                    .accessibilityValue(comfortMode ? "On" : "Off")
                    .accessibilityHint("Uses larger action labels and a single-column layout for grouped controls.")
                Text("Comfort Mode uses larger action labels and taller buttons. Text also follows the iPhone’s Dynamic Type setting. The interface has no decorative motion.")
                    .font(.callout)
                Text("Local medication reminder")
                    .font(.title2.bold())
                DatePicker("Reminder time", selection: Binding(
                    get: { medicationReminder.selectedTime },
                    set: { medicationReminder.setTime($0) }
                ), displayedComponents: .hourAndMinute)
                    .frame(minHeight: 56)
                Toggle("Daily medication reminder", isOn: Binding(
                    get: { medicationReminder.isEnabled },
                    set: { enabled in enabled ? medicationReminder.enable() : medicationReminder.disable() }
                ))
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 56)
                    .tint(Palette.teal)
                    .accessibilityValue(medicationReminder.isEnabled ? "On" : "Off")
                    .accessibilityHint("Turning this on asks iOS for permission. The reminder is local and does not confirm that medication was taken.")
                Text(medicationReminder.status)
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.updatesFrequently)
                Text("The reminder contains no medication name or dose. It does not give dosing advice or confirm a dose. iOS notification settings, Focus, device state, or system delivery can delay or prevent a notification.")
                    .font(.footnote)
                Text("Privacy notice")
                    .font(.title2.bold())
                if let url = publishedPrivacyPolicyURL {
                    Link("Privacy Policy", destination: url)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 56)
                        .accessibilityHint("Opens the published PD Bridge privacy policy")
                        .accessibilityIdentifier("settings.privacyPolicyLink")
                }
                Text(NativeBuildCopy.privacyNotice)
                    .font(.body)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("settings.privacyNotice")

                Text("Encrypted backup")
                    .font(.title2.bold())
                Text("A backup is encrypted with a passphrase that PD Bridge does not keep. Saved voice recordings are included in the encrypted backup. If you forget the passphrase, the file cannot be recovered. You choose where the encrypted file is saved; a cloud location is outside this app’s device-only storage.")
                    .font(.callout)
                SecureField(
                    "Backup passphrase (12+ characters)",
                    text: $exportPassphrase,
                    prompt: Text("Backup passphrase (12+ characters)").foregroundColor(Palette.ink)
                )
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(
                    "Confirm backup passphrase",
                    text: $exportConfirmation,
                    prompt: Text("Confirm backup passphrase").foregroundColor(Palette.ink)
                )
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(NativeStrings.text("Create encrypted backup", languageCode: languageCode)) {
                    guard exportPassphrase == exportConfirmation else {
                        model.showNotice("The passphrases do not match. No backup was created.", tone: .error)
                        return
                    }
                    showExportConfirmation = true
                }
                .buttonStyle(ActionStyle(prominent: true))
                .disabled(!model.canWrite)

                Text("Import and merge backup")
                    .font(.title2.bold())
                Text("Import preserves existing entries. A duplicate source event is not added again. Conflicting record identifiers are rejected without changing the vault.")
                    .font(.callout)
                Button(NativeStrings.text("Choose encrypted backup file", languageCode: languageCode)) { showImporter = true }
                    .buttonStyle(ActionStyle())
                    .disabled(!model.canWrite)
                if importedBackup != nil {
                    SecureField(
                        "Backup passphrase",
                        text: $importPassphrase,
                        prompt: Text("Backup passphrase").foregroundColor(Palette.ink)
                    )
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(NativeStrings.text("Import and merge", languageCode: languageCode)) {
                        showImportConfirmation = true
                    }
                    .buttonStyle(ActionStyle(prominent: true))
                    .disabled(!model.canWrite || importPassphrase.isEmpty)
                }

                Button(model.isDeletionPending ? "Retry deletion" : NativeStrings.text("Delete all observations", languageCode: languageCode), role: .destructive) {
                    if model.isDeletionPending { beginDelete() }
                    else { showDeleteConfirmation = true }
                }
                .buttonStyle(ActionStyle(destructive: true))
                .disabled(!model.canRetryDeletion)
                Text("Deleting removes the local encryption key and observation file. A device-only deletion timestamp remains to reject older queued Watch events. This does not securely overwrite flash storage or delete encrypted backup files saved elsewhere.")
                    .font(.footnote)
            }
            .foregroundColor(Palette.ink)
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.page)
        .navigationTitle(NativeStrings.text("Settings", languageCode: languageCode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NativeStrings.text("Done", languageCode: languageCode)) { dismiss() } } }
        .fileExporter(isPresented: $showExporter, document: backupDocument,
                      contentType: .data, defaultFilename: "PD-Bridge-Encrypted-Backup.pdbridgebackup") { result in
            exportPassphrase = ""
            exportConfirmation = ""
            switch result {
            case .success: model.showNotice("Encrypted backup saved to the selected location.", tone: .success)
            case .failure: model.showNotice("Backup export did not complete. The local vault was unchanged.", tone: .error)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let hasScope = url.startAccessingSecurityScopedResource()
                defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? Int.max) <= 32 * 1024 * 1024 else {
                        model.showNotice("Backup file is too large to import. No entries were changed.", tone: .error)
                        return
                    }
                    importedBackup = try Data(contentsOf: url)
                    model.showNotice("Backup file selected. Enter its passphrase to validate and merge it.")
                } catch {
                    model.showNotice("Backup file could not be read. No entries were changed.", tone: .error)
                }
            case .failure:
                model.showNotice("Backup file selection was closed or failed. No entries were changed.")
            }
        }
        .confirmationDialog("Create encrypted backup?", isPresented: $showExportConfirmation) {
            Button("Create encrypted backup") { prepareExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PD Bridge will create an encrypted copy using your passphrase. You choose its destination; a saved copy is outside this iPhone's local deletion controls.")
        }
        .confirmationDialog("Import and merge this backup?", isPresented: $showImportConfirmation) {
            Button("Import and merge") { performImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing entries are preserved. Identical source events are skipped, and conflicting record IDs are rejected without overwriting current entries. Importing an older backup may restore entries deleted on this iPhone after that backup was created.")
        }
        .confirmationDialog("Delete all observations from this iPhone?", isPresented: $showDeleteConfirmation) {
            Button(NativeStrings.text("Delete all observations", languageCode: languageCode), role: .destructive) { beginDelete() }
            Button(NativeStrings.text("Cancel", languageCode: languageCode), role: .cancel) {}
        } message: {
            Text("PD Bridge will remove the local encryption key, observation file, and locally stored voice notes. If interrupted, deletion stays pending and resumes when the app opens. A small device-only deletion timestamp remains to reject older queued Watch events. Encrypted backup files saved elsewhere are unaffected, and flash storage is not physically overwritten.")
        }
        .onChange(of: model.sensitiveStateGeneration) { _, _ in
            exportPassphrase = ""
            exportConfirmation = ""
            importPassphrase = ""
            importedBackup = nil
            backupDocument = EncryptedBackupDocument(data: Data())
            showExporter = false
            showImporter = false
        }
        .onDisappear {
            exportPassphrase = ""
            exportConfirmation = ""
            importPassphrase = ""
            importedBackup = nil
        }
    }

    private func beginDelete() {
        exportPassphrase = ""
        exportConfirmation = ""
        importPassphrase = ""
        importedBackup = nil
        backupDocument = EncryptedBackupDocument(data: Data())
        showExporter = false
        showImporter = false
        _ = model.deleteAll()
    }

    private func prepareExport() {
        guard let data = model.createEncryptedBackup(passphrase: exportPassphrase) else { return }
        backupDocument = EncryptedBackupDocument(data: data)
        showExporter = true
    }

    private func performImport() {
        guard let data = importedBackup else { return }
        if model.importEncryptedBackup(data, passphrase: importPassphrase) {
            importedBackup = nil
            importPassphrase = ""
        }
    }
}

private struct NoteEditor: View {
    @EnvironmentObject private var model: DiaryModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pdbridge.language") private var languageCode = NativeLanguage.english.rawValue
    @FocusState private var editorFocused: Bool
    let item: Observation?
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(NativeStrings.text("Cancel", languageCode: languageCode)) { dismiss() }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 56, minHeight: 56)
                        .padding(.horizontal, 8)
                        .background(Palette.surface)
                        .clipShape(Capsule())
                    Spacer(minLength: 8)
                    Text(NativeStrings.text(item == nil ? "Write a note" : "Edit entry", languageCode: languageCode))
                        .font(.title2.bold())
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.page)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoBanner()
                        Text(NativeStrings.text(item == nil ? NativeBuildCopy.noteTitle : "Correct wording", languageCode: languageCode))
                            .font(.headline)
                        TextEditor(text: $text)
                            .font(.body)
                            .frame(minHeight: 180)
                            .focused($editorFocused)
                            .padding(8)
                            .background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(NativeBuildCopy.noteAccessibilityLabel)
                            .accessibilityHint("Original wording is preserved exactly as entered.")
                        Button(NativeStrings.text("Save", languageCode: languageCode)) {
                            saveNote()
                        }
                        .buttonStyle(ActionStyle(prominent: true))
                        .disabled(!canSave)
                    }
                    .padding(20)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Palette.page)
            }
            .background(Palette.page)
            .toolbar(.hidden, for: .navigationBar)
            .foregroundColor(Palette.ink)
            .tint(Palette.teal)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Hide keyboard") { editorFocused = false }
                    Spacer()
                    Button(NativeStrings.text("Save", languageCode: languageCode)) { saveNote() }
                        .disabled(!canSave)
                }
            }
            .onAppear { text = item?.savedText ?? "" }
            .onChange(of: model.sensitiveStateGeneration) { _, _ in text = "" }
        }
    }

    private var canSave: Bool {
        model.canWrite && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveNote() {
        guard canSave else { return }
        let saved = item.map { model.edit($0.id, text: text) } ?? model.addNote(text)
        if saved { dismiss() }
    }
}

/// Fixed-choice, local-only conversation sample. It never requests audio or accepts free text.
#if PD_BRIDGE_SYNTHETIC_BUILD
private struct ScriptedTalkDemoView: View {
    @EnvironmentObject private var model: DiaryModel
    let onClose: () -> Void
    @State private var draft = NativeScriptedTalkDraft()
    @State private var step = 0
    @State private var reviewing = false

    private var choices: [String] { draft.options(for: step) }
    private var selectedIndex: Int? { draft.selection(for: step) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("Stop without saving", action: onClose)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 56, minHeight: 56)
                        .padding(.horizontal, 8)
                        .background(Palette.surface)
                        .clipShape(Capsule())
                    Spacer(minLength: 8)
                    Text("Talk demo")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.page)
                DemoBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if reviewing {
                                reviewContent
                            } else {
                                Text("Scripted Talk demonstration")
                                    .font(.largeTitle.bold())
                                    .accessibilityAddTraits(.isHeader)
                                Text("English text and fixed fictional choices only. This is not speech recognition or AI. No microphone, audio, network request, or free-text response is used.")
                                    .font(.body)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                ProgressView(value: Double(step + 1), total: 3)
                                    .accessibilityLabel("Scripted demo progress")
                                    .accessibilityValue("Question \(step + 1) of 3")
                                Text("Question \(step + 1) of 3")
                                    .font(.headline)
                                Text(draft.question(for: step))
                                    .font(.title3.weight(.semibold))
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(choices.indices, id: \.self) { index in
                                    let isSelected = selectedIndex == index
                                    Button {
                                        draft.select(index, for: step)
                                    } label: {
                                        HStack(alignment: .center, spacing: 10) {
                                            Text(choices[index])
                                            Spacer(minLength: 4)
                                            if isSelected { Image(systemName: "checkmark.circle.fill") }
                                        }
                                    }
                                    .buttonStyle(ActionStyle(prominent: isSelected))
                                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                                }
                                if step > 0 {
                                    Button("Skip this question") { advance(skipping: true) }
                                        .buttonStyle(ActionStyle())
                                }
                                HStack(spacing: 10) {
                                    if step > 0 {
                                        Button("Back") { step -= 1 }
                                            .buttonStyle(ActionStyle())
                                    }
                                    Button(step == 2 ? "Review fictional note" : "Continue") { advance(skipping: false) }
                                        .buttonStyle(ActionStyle(prominent: true))
                                        .disabled(step == 0 && selectedIndex == nil)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 40)
                    }
                    .background(Palette.page)
                    .onChange(of: reviewing) { _, isReviewing in
                        if isReviewing { scrollProxy.scrollTo("talk-review-top", anchor: .top) }
                    }
                }
            }
            .background(Palette.page)
            .toolbar(.hidden, for: .navigationBar)
            .foregroundColor(Palette.ink)
            .tint(Palette.teal)
        }
    }

    @ViewBuilder private var reviewContent: some View {
        Text("Review the sample before saving")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            .id("talk-review-top")
        Text("Fixed fictional choices only. No speech was captured or AI used.")
            .font(.callout)
        Text(verbatim: draft.noteText ?? "Choose a fictional event to create a sample.")
            .font(.body)
            .textSelection(.enabled)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        Button("Save fictional note to History") {
            guard let note = draft.noteText, model.addNote(note) else { return }
            onClose()
        }
        .buttonStyle(ActionStyle(prominent: true))
        .disabled(!model.canWrite || draft.noteText == nil)
        Button("Back to questions") { reviewing = false; step = 2 }
            .buttonStyle(ActionStyle())
        Button("Start over") { draft = NativeScriptedTalkDraft(); step = 0; reviewing = false }
            .buttonStyle(ActionStyle())
    }

    private func advance(skipping: Bool) {
        if skipping { draft.select(nil, for: step) }
        if step < 2 { step += 1 }
        else { reviewing = true }
    }
}
#endif

private extension Observation.Kind {
    func title(languageCode: String = NativeLanguage.english.rawValue) -> String {
        NativeStrings.observationKindTitle(self, languageCode: languageCode)
    }
}

private extension Observation.Origin {
    var sourceLabel: String {
        switch self {
        case .manual: return "Entered on this iPhone"
        case .appleHealth: return "Apple Health historical record"
        case .fictionalWatch: return "Fictional Apple Watch test"
        }
    }
}
