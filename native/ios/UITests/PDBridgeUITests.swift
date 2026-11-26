import XCTest

final class PDBridgeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var uiTestRunID = UUID()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp()
        let start = app.buttons["welcome.getStarted"]
        if start.waitForExistence(timeout: 2) { start.tap() }
        XCTAssertTrue(app.buttons["Write a note"].waitForExistence(timeout: 15))
        attachScreen("home")
    }

    func testWelcomeAppearsOnlyUntilStarted() throws {
        app.terminate()
        app = launchApp(extraArguments: ["-pdbridge.welcomeCompleted.v1", "NO"])
        let start = app.buttons["welcome.getStarted"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome to PD Bridge"].exists)
        start.tap()
        XCTAssertTrue(app.buttons["Write a note"].waitForExistence(timeout: 5))
        app.terminate()
        app = launchApp()
        XCTAssertFalse(app.buttons["welcome.getStarted"].exists)
        XCTAssertTrue(app.buttons["Write a note"].waitForExistence(timeout: 5))
    }

    func testApprovedHybridDesignScreens() throws {
        app.terminate()
        app = launchApp(extraArguments: ["-pdbridge.welcomeCompleted.v1", "NO", "-pdbridge.comfortMode", "NO"])
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitForExistence(timeout: 5))
        attachScreen("hybrid-welcome")
        app.buttons["welcome.getStarted"].tap()
        XCTAssertTrue(app.buttons["home.quick.tremor"].waitForExistence(timeout: 5))
        attachScreen("hybrid-track")
        app.buttons["home.quick.tremor"].tap()
        openHistory()
        XCTAssertTrue(app.staticTexts["Tremor recorded manually."].waitForExistence(timeout: 5))
        attachScreen("hybrid-history")
        app.switches.matching(NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'")).firstMatch.tap()
        // Capture settled screens and verify the selection survives app restart.
        app.terminate()
        app = launchApp(extraArguments: ["-pdbridge.comfortMode", "NO"], testRunID: uiTestRunID)
        app.buttons["tab.Insights"].tap()
        XCTAssertTrue(app.buttons["insights.dateRange.week"].waitForExistence(timeout: 5))
        attachScreen("hybrid-insights-weekly")
        app.buttons["insights.dateRange.month"].tap()
        attachScreen("hybrid-insights-monthly")
        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.buttons["appointment.reviewReport"].waitForExistence(timeout: 5))
        attachScreen("hybrid-visits")
        app.buttons["appointment.reviewReport"].tap()
        XCTAssertTrue(app.staticTexts["Tremor recorded manually."].waitForExistence(timeout: 5))
        attachScreen("hybrid-report")
        openSettings()
        XCTAssertTrue(app.switches["Comfort Mode"].waitForExistence(timeout: 5))
        attachScreen("hybrid-settings")
    }

    func testHybridDarkComfortAndUrduLayouts() throws {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.appearance = previousAppearance == .unspecified ? .light : previousAppearance
        }
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app = launchApp(accessibilityTextSize: true)
        if app.buttons["welcome.getStarted"].waitForExistence(timeout: 2) {
            app.buttons["welcome.getStarted"].tap()
        }
        XCTAssertTrue(app.buttons["home.quick.tremor"].waitForExistence(timeout: 5))
        attachScreen("hybrid-dark-large-text")
        openSettings()
        let comfort = app.switches["Comfort Mode"]
        XCTAssertTrue(comfort.waitForExistence(timeout: 5))
        if comfort.value as? String == "Off" { comfort.tap() }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home.quick.otherSymptom"].waitForExistence(timeout: 5))
        attachScreen("hybrid-dark-comfort")

        XCUIDevice.shared.appearance = .light
        app.terminate()
        app = launchApp(languageCode: "ur", extraArguments: ["-pdbridge.comfortMode", "NO"])
        if app.buttons["welcome.getStarted"].waitForExistence(timeout: 2) {
            app.buttons["welcome.getStarted"].tap()
        }
        XCTAssertTrue(app.buttons["home.quick.tremor"].waitForExistence(timeout: 5))
        attachScreen("hybrid-urdu-rtl")
    }

    func testWelcomeThenManualEventReachesAppointment() throws {
        app.terminate()
        app = launchApp(extraArguments: ["-pdbridge.welcomeCompleted.v1", "NO"])
        let start = app.buttons["welcome.getStarted"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let fall = app.buttons["Fall"]
        scrollUntilHittable(fall, in: app.scrollViews.firstMatch)
        fall.tap()
        openHistory()
        let include = app.switches.matching(
            NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'")
        ).firstMatch
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        include.tap()
        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts["Selected entries: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fictional fall test event."].exists)
    }

    func testFictionalDiaryToAppointmentAndUndo() throws {
        let original = "Fictional: walking paused at the kitchen doorway."
        let correction = "Fictional correction: hallway doorway. "
        let corrected = correction + original

        app.buttons["Write a note"].tap()
        let editor = noteEditor()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(original)
        // Use the editor's main Save button, not its keyboard shortcut.
        app.scrollViews.buttons["Save"].firstMatch.tap()

        openHistory()
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        attachScreen("history")
        let search = app.textFields["Search history entries"]
        search.tap()
        search.typeText("kitchen doorway")
        XCTAssertTrue(app.staticTexts[original].exists)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "kitchen doorway".count))

        app.buttons["Edit"].firstMatch.tap()
        let correctionEditor = noteEditor()
        XCTAssertTrue(correctionEditor.waitForExistence(timeout: 5))
        correctionEditor.tap()
        correctionEditor.typeText(correction)
        app.scrollViews.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
        app.buttons["Original wording and corrections"].tap()
        XCTAssertTrue(app.staticTexts[original].exists)
        app.switches["Include in appointment"].tap()

        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
        attachScreen("appointment")
        XCTAssertTrue(app.staticTexts["Selected entries: 1"].waitForExistence(timeout: 5))
        app.buttons["Set aside from this appointment"].tap()
        XCTAssertTrue(app.staticTexts["Selected entries: 0"].waitForExistence(timeout: 5))
        app.buttons["Add to this appointment"].tap()
        app.buttons["Print or save report"].tap()
        XCTAssertTrue(app.staticTexts["Report options opened. Choose a destination; nothing is saved yet."].waitForExistence(timeout: 5),
                      "The app must confirm that the print/export interface opened without claiming the report was saved.")
        // Terminate and relaunch the isolated UI-test app to dismiss UIKit's
        // system print sheet without choosing a printer or exporting a file.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Selected entries: 1"].waitForExistence(timeout: 5))

        openHistory()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts[corrected].exists)
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Undo deletion' ")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
    }

    func testReleaseScreenshotSet() throws {
        // Run only with the Release configuration on a clean simulator. This
        // isolated test vault contains demonstration text, never user records.
        let demonstration = "Example: paused briefly while walking through a doorway."
        attachScreen("release-home")
        app.buttons["Write a note"].tap()
        let editor = app.textViews["Note text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(demonstration)
        app.scrollViews.buttons["Save"].firstMatch.tap()

        // The app deliberately keeps success feedback visible and accessible.
        // Relaunch the same isolated test vault before taking marketing images,
        // so screenshots show the app's steady state instead of a transient toast.
        app.terminate()
        app = launchApp(testRunID: uiTestRunID)
        openHistory()
        XCTAssertTrue(app.staticTexts[demonstration].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Note saved on this iPhone."].exists)
        attachScreen("release-history")
        app.switches["Include in appointment"].tap()

        app.terminate()
        app = launchApp(testRunID: uiTestRunID)
        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts["Selected entries: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[demonstration].exists)
        XCTAssertFalse(app.staticTexts["Added to appointment report."].exists)
        let appointmentScroll = app.scrollViews["appointment.scrollView"]
        XCTAssertTrue(appointmentScroll.waitForExistence(timeout: 5))
        let reportText = appointmentScroll.staticTexts[demonstration]
        let appointmentTab = app.buttons["tab.Visits"]
        scrollUntilFullyVisible(reportText, in: appointmentScroll, above: appointmentTab)
        appointmentScroll.swipeUp(velocity: .slow)
        XCTAssertTrue(reportText.isHittable)
        attachScreen("release-appointment")

        openSettings()
        let privacyLink = app.descendants(matching: .any)
            .matching(identifier: "settings.privacyPolicyLink").firstMatch
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 5))
        let settingsScroll = app.scrollViews["settings.scrollView"]
        XCTAssertTrue(settingsScroll.waitForExistence(timeout: 5))
        for _ in 0..<8 where !privacyLink.isHittable ||
            privacyLink.frame.minY < settingsScroll.frame.minY ||
            privacyLink.frame.maxY > settingsScroll.frame.maxY {
            settingsScroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(privacyLink.isHittable)
        XCTAssertGreaterThanOrEqual(privacyLink.frame.minY, settingsScroll.frame.minY)
        XCTAssertLessThanOrEqual(privacyLink.frame.maxY, settingsScroll.frame.maxY)
        attachScreen("release-settings")
    }

    func testPublishedPrivacyPolicyLink() throws {
        openSettings()
        let link = app.descendants(matching: .any)
            .matching(identifier: "settings.privacyPolicyLink").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        scrollUntilHittable(link, in: app.scrollViews.firstMatch)
        XCTAssertTrue(link.isHittable)
        link.tap()
        let browser = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(browser.wait(for: .runningForeground, timeout: 10),
                      "Privacy Policy should open the published HTTPS page in Safari.")
        XCTAssertTrue(browser.webViews.staticTexts["Privacy Policy"].waitForExistence(timeout: 15),
                      "Safari should render the public policy heading.")
    }

    func testManualFallNearFallAndFreezingEventsReachAppointment() throws {
        let home = app.scrollViews.firstMatch
        let navigation = app.buttons["tab.Track"]
        for kind in ["Fall", "Near-fall", "Freezing"] {
            let shortcut = app.buttons[kind]
            scrollUntilFullyVisible(shortcut, in: home, above: navigation)
            shortcut.tap()
        }

        openHistory()
        for event in [
            "Fictional fall test event.",
            "Fictional near-fall test event.",
            "Fictional freezing test event."
        ] {
            XCTAssertTrue(app.staticTexts[event].waitForExistence(timeout: 5))
        }
        let inclusionSwitches = app.switches.matching(identifier: "Include in appointment")
        XCTAssertEqual(inclusionSwitches.count, 3)
        let notIncluded = app.switches.matching(NSPredicate(
            format: "label == %@ AND value == %@", "Include in appointment", "Set aside from appointment"
        ))
        for _ in 0..<3 {
            let next = notIncluded.firstMatch
            guard next.exists else { break }
            scrollUntilFullyVisible(next, in: app.scrollViews.firstMatch, above: app.buttons["tab.Track"])
            next.tap()
        }
        for index in 0..<inclusionSwitches.count {
            XCTAssertEqual(inclusionSwitches.element(boundBy: index).value as? String,
                           "Included in appointment")
        }

        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts["Selected entries: 3"].waitForExistence(timeout: 5))
        for event in [
            "Fictional fall test event.",
            "Fictional near-fall test event.",
            "Fictional freezing test event."
        ] {
            XCTAssertTrue(app.staticTexts[event].waitForExistence(timeout: 5))
        }
        attachScreen("manual-events-in-appointment")
    }

    func testInsightsAndAppointmentPreviewUseSavedSelection() throws {
        let note = "Fictional report preview entry."
        app.buttons["home.writeNote"].tap()
        let editor = noteEditor()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(note)
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.scrollViews.buttons["Save"].firstMatch.tap()

        openHistory()
        let include = app.switches.matching(
            NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'")
        ).firstMatch
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        include.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "history.dateWindow").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "history.kindFilter").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "history.sourceFilter").firstMatch.exists)

        app.buttons["tab.Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved entries: 1"].waitForExistence(timeout: 5))
        attachScreen("insights-with-fictional-entry")

        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts["Selected entries: 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[note].exists)
        let preview = app.buttons["Preview printable report"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let report = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Recorded wording: \(note)")
        ).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains(note))
        attachScreen("appointment-shared-report-preview")
    }

    func testScrollableScreensAndVisibleControls() throws {
        attachScreen("home-before-scroll")
        let homeScroll = app.scrollViews.firstMatch
        let talk = app.buttons["home.talkDemo"]
        let help = app.buttons["home.help"]
        scrollUntilFullyVisible(talk, in: homeScroll, above: app.buttons["tab.Track"])
        scrollUntilFullyVisible(help, in: homeScroll, above: app.buttons["tab.Track"])
        XCTAssertTrue(talk.isHittable)
        attachScreen("home-bottom-controls")
        talk.tap()
        XCTAssertTrue(app.staticTexts["Scripted Talk demonstration"].waitForExistence(timeout: 5))
        attachScreen("talk-demo")
        XCTAssertTrue(app.buttons["Stop without saving"].isHittable)
        app.buttons["Stop without saving"].tap()
        XCTAssertFalse(app.buttons["Stop without saving"].waitForExistence(timeout: 2),
                       "Stopping the scripted demo must close its sheet before Home actions are available.")
        let writeNote = app.buttons["home.writeNote"]
        XCTAssertTrue(writeNote.waitForExistence(timeout: 5))
        XCTAssertTrue(writeNote.isHittable)

        // Add only fictional text to this run's isolated encrypted vault.
        writeNote.tap()
        let editor = noteEditor()
        editor.tap()
        editor.typeText("Fictional scroll check note.")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.buttons["Hide keyboard"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.scrollViews.buttons["Save"].firstMatch.tap()

        openHistory()
        let include = app.switches.matching(NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'" )).firstMatch
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        XCTAssertTrue(include.isHittable)
        XCTAssertEqual(include.value as? String, "Set aside from appointment")
        attachScreen("history-card-and-toggle")
        let delete = app.buttons["Delete"].firstMatch
        scrollUntilFullyVisible(delete, in: app.scrollViews.firstMatch, above: app.buttons["tab.Track"])
        attachScreen("history-bottom-controls")

        app.buttons["tab.Visits"].tap()
        let add = app.buttons["Add to this appointment"].firstMatch
        scrollUntilFullyVisible(add, in: app.scrollViews.firstMatch, above: app.buttons["tab.Track"])
        attachScreen("appointment-bottom-controls")

        openSettings()
        XCTAssertTrue(app.staticTexts["Encrypted backup"].waitForExistence(timeout: 5))
        let privacyNotice = app.staticTexts["settings.privacyNotice"]
        XCTAssertTrue(privacyNotice.exists)
        XCTAssertTrue(privacyNotice.label.contains("type a name and number in Help"))
        XCTAssertFalse(privacyNotice.label.contains("system contact picker"))
        let comfort = app.switches["Comfort Mode"]
        XCTAssertTrue(comfort.exists)
        XCTAssertTrue(comfort.isHittable)
        XCTAssertTrue(["On", "Off"].contains(comfort.value as? String ?? ""))
        let reminder = app.switches["Daily medication reminder"]
        XCTAssertTrue(reminder.exists)
        XCTAssertTrue(reminder.isHittable)
        XCTAssertTrue(["On", "Off"].contains(reminder.value as? String ?? ""))
        attachScreen("settings-toggle-controls")
        let deleteAll = app.buttons["Delete all observations"]
        scrollUntilFullyVisible(deleteAll, in: app.scrollViews.firstMatch, above: app.buttons["tab.Track"])
        attachScreen("settings-bottom-controls")
        app.buttons["Done"].tap()
    }

    func testAccessibilityTextSizeAndHomeNavigation() throws {
        let previousAppearance = XCUIDevice.shared.appearance
        // The system may report .unspecified for a user-selected Light Mode;
        // XCUITest cannot restore that sentinel, so restore the observed
        // pre-test appearance (Light) in that case.
        defer {
            XCUIDevice.shared.appearance = previousAppearance == .unspecified ? .light : previousAppearance
        }
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app = launchApp(accessibilityTextSize: true)
        XCTAssertTrue(app.buttons["Write a note"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["PD Bridge"].exists)
        attachScreen("dark-appearance-large-text-home")
        let talk = app.buttons["home.talkDemo"]
        let help = app.buttons["home.help"]
        let nav = app.buttons["tab.Track"]
        scrollUntilFullyVisible(talk, in: app.scrollViews.firstMatch, above: nav)
        scrollUntilFullyVisible(help, in: app.scrollViews.firstMatch, above: nav)
        attachScreen("dark-home-bottom-controls")
        let history = app.buttons["home.openHistory"]
        scrollUntilFullyVisible(history, in: app.scrollViews.firstMatch, above: app.buttons["tab.Track"])
        XCTAssertTrue(history.isHittable)
    }

    func testCaregiverHelpManualEntryOpensAndExits() throws {
        let home = app.scrollViews.firstMatch
        let help = app.buttons["home.help"]
        scrollUntilFullyVisible(help, in: home, above: app.buttons["tab.Track"])
        XCTAssertTrue(help.isHittable)
        help.tap()
        XCTAssertTrue(app.textFields["help.caregiverName"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["help.caregiverPhone"].exists)
        let review = app.buttons["help.reviewCallDetails"]
        XCTAssertTrue(review.exists)
        XCTAssertFalse(review.isEnabled)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home.help"].waitForExistence(timeout: 5))
    }

    func testCaregiverPhoneValidationRejectsTooFewDigits() throws {
        let home = app.scrollViews.firstMatch
        let help = app.buttons["home.help"]
        scrollUntilFullyVisible(help, in: home, above: app.buttons["tab.Track"])
        help.tap()
        let nameField = app.textFields["help.caregiverName"]
        let phoneField = app.textFields["help.caregiverPhone"]
        let review = app.buttons["help.reviewCallDetails"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Fictional QA Caregiver")
        phoneField.tap()
        phoneField.typeText("12")
        XCTAssertEqual(phoneField.value as? String, "12")
        let keyboardDone = app.buttons["help.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
        keyboardDone.tap()
        XCTAssertTrue(app.staticTexts["help.phoneValidationError"].waitForExistence(timeout: 5))
        XCTAssertFalse(review.isEnabled)
    }

    func testManualCaregiverReviewCanBeCancelledWithoutOpeningPhone() throws {
        let home = app.scrollViews.firstMatch
        let help = app.buttons["home.help"]
        scrollUntilFullyVisible(help, in: home, above: app.buttons["tab.Track"])
        help.tap()
        let nameField = app.textFields["help.caregiverName"]
        let phoneField = app.textFields["help.caregiverPhone"]
        let review = app.buttons["help.reviewCallDetails"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        XCTAssertFalse(review.isEnabled)
        nameField.tap()
        nameField.typeText("Fictional QA Caregiver")
        phoneField.tap()
        phoneField.typeText("2025550108")
        let keyboardDone = app.buttons["help.keyboardDone"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
        keyboardDone.tap()
        scrollUntilHittable(review, in: app.scrollViews.firstMatch)
        XCTAssertTrue(review.isEnabled)
        review.tap()

        XCTAssertTrue(app.staticTexts["Review call"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["help.reviewCaregiverName"].label, "Caregiver: Fictional QA Caregiver")
        XCTAssertEqual(app.staticTexts["help.reviewPhoneNumber"].label, "Phone number: 2025550108")
        XCTAssertTrue(app.buttons["help.openPhone"].exists)
        let cancel = app.buttons["help.cancelReview"]
        XCTAssertTrue(cancel.exists)
        cancel.tap()

        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(review.isEnabled, "Cancel should clear the transient name and number.")
        XCTAssertFalse(app.buttons["help.openPhone"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home.help"].waitForExistence(timeout: 5))
    }

    func testTalkDemoReviewSaveReturnsHomeAndStoresFictionalText() throws {
        app.buttons["home.talkDemo"].tap()
        XCTAssertTrue(app.staticTexts["Scripted Talk demonstration"].waitForExistence(timeout: 5))
        app.buttons["A fictional pause happened during a walk."].tap()
        app.buttons["Continue"].tap()
        app.buttons["Morning"].tap()
        app.buttons["Continue"].tap()
        app.buttons["The fictional person noticed it."].tap()
        app.buttons["Review fictional note"].tap()

        XCTAssertTrue(app.staticTexts["Review the sample before saving"].waitForExistence(timeout: 5))
        let save = app.buttons["Save fictional note to History"]
        XCTAssertTrue(save.isHittable)
        save.tap()

        let writeNote = app.buttons["home.writeNote"]
        XCTAssertTrue(writeNote.waitForExistence(timeout: 5))
        XCTAssertTrue(writeNote.isHittable)
        openHistory()
        let sample = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Fictional scripted demonstration. A fictional pause happened during a walk."
        )).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
    }

    func testGujaratiTextPreservesKeyboardEditAndAppointment() throws {
        try exerciseUnicodeNote("કાલ્પનિક નોંધ: ચાલ ધીમી હતી.", screenshotName: "gujarati")
    }

    func testHindiTextPreservesKeyboardEditAndAppointment() throws {
        try exerciseUnicodeNote("काल्पनिक नोट: चाल धीमी थी।", screenshotName: "hindi")
    }

    func testUrduTextPreservesKeyboardEditAndAppointment() throws {
        try exerciseUnicodeNote("فرضی نوٹ: چال دھیمی تھی۔", screenshotName: "urdu-mixed")
    }

    func testUrduNoteUsesRTLAndIsSearchable() throws {
        app.terminate()
        app = launchApp(languageCode: "ur")
        XCTAssertTrue(app.buttons["home.writeNote"].waitForExistence(timeout: 15))
        app.buttons["home.writeNote"].tap()
        let original = "فرضی نوٹ — چال دھیمی تھی۔"
        let editor = noteEditor()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(original)
        XCTAssertEqual(editor.value as? String, original)
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.buttons["محفوظ کریں"].tap()

        openHistory()
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        attachScreen("urdu-history")
        let search = app.textFields["Search history entries"]
        search.tap()
        search.typeText("دھیمی")
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "دھیمی".utf16.count))
        let include = app.switches.matching(NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'")).firstMatch
        if include.value as? String == "Set aside from appointment" { include.tap() }
        app.buttons["tab.Visits"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists,
                       "Switching away from History must dismiss the search keyboard.")
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        attachScreen("urdu-appointment")
    }

    private func exerciseUnicodeNote(_ original: String, screenshotName: String) throws {
        app.buttons["home.writeNote"].tap()
        let editor = noteEditor()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(original)
        XCTAssertEqual(editor.value as? String, original,
                       "The exact fictional Unicode string must be visible before saving.")

        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.scrollViews.buttons["Save"].firstMatch.tap()

        openHistory()
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        attachScreen("\(screenshotName)-history-original")
        let search = app.textFields["Search history entries"]
        search.tap()
        search.typeText(original)
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.utf16.count))

        app.buttons["Edit"].firstMatch.tap()
        let correctionEditor = noteEditor()
        correctionEditor.tap()
        correctionEditor.press(forDuration: 1.0)
        let correctionSelectAll = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Select All")
        ).firstMatch
        XCTAssertTrue(correctionSelectAll.waitForExistence(timeout: 5))
        correctionSelectAll.tap()
        let corrected = original + " corrected"
        correctionEditor.typeText(corrected)
        XCTAssertEqual(correctionEditor.value as? String, corrected,
                       "The complete corrected wording must be visible before saving.")
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        app.scrollViews.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
        app.buttons["Original wording and corrections"].tap()
        XCTAssertTrue(app.staticTexts[original].waitForExistence(timeout: 5))

        let include = app.switches.matching(NSPredicate(format: "identifier CONTAINS 'history.includeInAppointment'")).firstMatch
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        if include.value as? String == "Set aside from appointment" { include.tap() }

        app.terminate()
        app.launch()
        openHistory()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
        app.buttons["tab.Visits"].tap()
        XCTAssertTrue(app.staticTexts[corrected].waitForExistence(timeout: 5))
        attachScreen("\(screenshotName)-appointment")
    }

    private func launchApp(
        accessibilityTextSize: Bool = false,
        languageCode: String = "en",
        extraArguments: [String] = [],
        testRunID: UUID? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--pdbridge-uitest", "-pdbridge.language", languageCode] + extraArguments
        if accessibilityTextSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        uiTestRunID = testRunID ?? UUID()
        app.launchEnvironment["PDBRIDGE_UI_TEST_RUN_ID"] = uiTestRunID.uuidString
        app.launch()
        return app
    }

    private func openHistory() {
        app.buttons["tab.History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    private func openSettings() {
        app.buttons["tab.Track"].tap()
        app.buttons["home.openSettings"].tap()
        XCTAssertTrue(app.scrollViews["settings.scrollView"].waitForExistence(timeout: 5))
    }

    private func noteEditor() -> XCUIElement {
        app.textViews.matching(NSPredicate(
            format: "label == %@ OR label == %@", "Note text", "Fictional note text"
        )).firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { scroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "Expected control to be reachable by vertical scrolling: \(element)")
    }

    private func scrollUntilFullyVisible(_ element: XCUIElement, in scroll: XCUIElement, above navigation: XCUIElement) {
        for _ in 0..<8 where !element.isHittable || element.frame.maxY > navigation.frame.minY + 1 {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "Expected control to be hittable after scrolling: \(element)")
        XCTAssertLessThanOrEqual(element.frame.maxY, navigation.frame.minY + 1,
                                  "Bottom navigation overlaps the final interactive control.")
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
