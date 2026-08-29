@testable import ExternalDisplayViewerCore
import XCTest

final class SmokeContractTests: XCTestCase {
    @MainActor
    func testInteractionConstantsMatchApprovedContract() {
        XCTAssertEqual(InteractionContract.escapeHoldDuration, .milliseconds(800))
        XCTAssertEqual(InteractionContract.controlHUDDuration, .milliseconds(1500))
        XCTAssertEqual(InteractionContract.returnHUDDuration, .milliseconds(1200))
        XCTAssertEqual(
            InteractionHUDMessages.control,
            "외부 디스플레이 제어 중 · 화면 경계 또는 ESC를 길게 눌러 돌아오기"
        )
        XCTAssertEqual(
            InteractionHUDMessages.returnToViewer,
            "Viewer로 돌아왔습니다"
        )
        XCTAssertEqual(
            TransitionHUDController.controlMessage,
            InteractionHUDMessages.control
        )
        XCTAssertEqual(
            TransitionHUDController.returnMessage,
            InteractionHUDMessages.returnToViewer
        )
    }

    func testPackagingUsesStableCodeSigningIdentity() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY"))
        XCTAssertTrue(script.contains("security find-identity"))
        XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
    }

    func testPackagingSignsOutsideSyncedWorkspaceAndLinksDurableApp() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("applicationSupportDirectory"))
        XCTAssertTrue(script.contains("STAGING_APP"))
        XCTAssertTrue(script.contains("ln -s"))
    }

    func testPackagingPreservesKnownGoodArchiveUntilReplacementIsVerified() throws {
        let script = try buildScript()

        XCTAssertTrue(script.contains("TEMP_ARCHIVE"))
        XCTAssertFalse(script.contains("rm -f \"$ARCHIVE\""))

        let verification = try XCTUnwrap(
            script.range(of: "codesign --verify --deep --strict \"$VERIFY_DIR/ExternalDisplayViewer.app\"")
        )
        let promotion = try XCTUnwrap(script.range(of: "mv -f \"$TEMP_ARCHIVE\" \"$ARCHIVE\""))
        XCTAssertLessThan(verification.lowerBound, promotion.lowerBound)
    }

    func testDistributionMetadataMatchesPublicReleaseContract() throws {
        let result = try runScript(named: "build-distribution.sh", arguments: ["--print-metadata"])

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertEqual(
            result.standardOutput.split(separator: "\n").map(String.init),
            [
                "app=ExternalDisplayViewer.app",
                "archive=ExternalDisplayViewer-v0.1.0-macOS-arm64.zip",
                "architecture=arm64",
                "bundle_id=io.github.realtake.ExternalDisplayViewer",
                "minimum_macos=15.0",
                "version=0.1.0",
            ]
        )
    }

    func testDistributionRejectsDevelopmentIdentityBeforeStartingBuild() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeBin = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let buildMarker = temporaryDirectory.appendingPathComponent("swift-was-invoked")
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fakeSwift = fakeBin.appendingPathComponent("swift")
        try "#!/bin/zsh\n: > \"$EXTERNAL_DISPLAY_VIEWER_TEST_MARKER\"\n".write(
            to: fakeSwift,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeSwift.path
        )

        let result = try runScript(
            named: "build-distribution.sh",
            environment: [
                "EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY": "Apple Development: Test",
                "EXTERNAL_DISPLAY_VIEWER_NOTARY_PROFILE": "test-profile",
                "EXTERNAL_DISPLAY_VIEWER_TEST_MARKER": buildMarker.path,
                "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            ]
        )

        XCTAssertEqual(result.terminationStatus, 64)
        XCTAssertFalse(FileManager.default.fileExists(atPath: buildMarker.path))
    }

    func testDistributionRequiresNotaryProfileBeforeStartingBuild() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeBin = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let buildMarker = temporaryDirectory.appendingPathComponent("swift-was-invoked")
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try writeExecutable(
            named: "swift",
            in: fakeBin,
            contents: "#!/bin/zsh\n: > \"$EXTERNAL_DISPLAY_VIEWER_TEST_MARKER\"\n"
        )

        let result = try runScript(
            named: "build-distribution.sh",
            environment: [
                "EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY": "Developer ID Application: Test",
                "EXTERNAL_DISPLAY_VIEWER_NOTARY_PROFILE": "",
                "EXTERNAL_DISPLAY_VIEWER_TEST_MARKER": buildMarker.path,
                "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            ]
        )

        XCTAssertEqual(result.terminationStatus, 64)
        XCTAssertFalse(FileManager.default.fileExists(atPath: buildMarker.path))
    }

    func testDistributionNotarizesAndStaplesBeforePublishingArchive() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeBin = temporaryDirectory.appendingPathComponent("bin", isDirectory: true)
        let swiftBin = temporaryDirectory.appendingPathComponent("swift-bin", isDirectory: true)
        let outputDirectory = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        let commandLog = temporaryDirectory.appendingPathComponent("commands.log")
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try writeExecutable(
            named: "swift",
            in: fakeBin,
            contents: """
            #!/bin/zsh
            print -r -- "swift $*" >> "$EXTERNAL_DISPLAY_VIEWER_TEST_LOG"
            if [[ "$*" == *"--show-bin-path"* ]]; then
              print -r -- "$EXTERNAL_DISPLAY_VIEWER_TEST_BIN_PATH"
              exit 0
            fi
            mkdir -p "$EXTERNAL_DISPLAY_VIEWER_TEST_BIN_PATH"
            print -r -- '#!/bin/zsh' > "$EXTERNAL_DISPLAY_VIEWER_TEST_BIN_PATH/ExternalDisplayViewer"
            chmod 755 "$EXTERNAL_DISPLAY_VIEWER_TEST_BIN_PATH/ExternalDisplayViewer"
            """
        )
        try writeExecutable(
            named: "security",
            in: fakeBin,
            contents: """
            #!/bin/zsh
            print -r -- "security $*" >> "$EXTERNAL_DISPLAY_VIEWER_TEST_LOG"
            print -r -- '1) TEST "Developer ID Application: Test"'
            """
        )
        try writeExecutable(
            named: "codesign",
            in: fakeBin,
            contents: "#!/bin/zsh\nprint -r -- \"codesign $*\" >> \"$EXTERNAL_DISPLAY_VIEWER_TEST_LOG\"\n"
        )
        try writeExecutable(
            named: "xcrun",
            in: fakeBin,
            contents: "#!/bin/zsh\nprint -r -- \"xcrun $*\" >> \"$EXTERNAL_DISPLAY_VIEWER_TEST_LOG\"\n"
        )
        try writeExecutable(
            named: "spctl",
            in: fakeBin,
            contents: "#!/bin/zsh\nprint -r -- \"spctl $*\" >> \"$EXTERNAL_DISPLAY_VIEWER_TEST_LOG\"\n"
        )

        let result = try runScript(
            named: "build-distribution.sh",
            arguments: ["--output-dir", outputDirectory.path],
            environment: [
                "EXTERNAL_DISPLAY_VIEWER_CODESIGN_IDENTITY": "Developer ID Application: Test",
                "EXTERNAL_DISPLAY_VIEWER_NOTARY_PROFILE": "test-profile",
                "EXTERNAL_DISPLAY_VIEWER_TEST_BIN_PATH": swiftBin.path,
                "EXTERNAL_DISPLAY_VIEWER_TEST_LOG": commandLog.path,
                "PATH": "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            ]
        )

        guard result.terminationStatus == 0 else {
            XCTFail(result.standardError)
            return
        }
        let commands = try String(contentsOf: commandLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let signing = try XCTUnwrap(commands.firstIndex { $0.contains("codesign --force") })
        let notarization = try XCTUnwrap(commands.firstIndex { $0.contains("xcrun notarytool submit") })
        let stapling = try XCTUnwrap(commands.firstIndex { $0.contains("xcrun stapler staple") })
        let assessment = try XCTUnwrap(commands.firstIndex { $0.contains("spctl --assess") })

        XCTAssertLessThan(signing, notarization)
        XCTAssertLessThan(notarization, stapling)
        XCTAssertLessThan(stapling, assessment)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: outputDirectory
                    .appendingPathComponent("ExternalDisplayViewer-v0.1.0-macOS-arm64.zip")
                    .path
            )
        )
    }

    func testDistributionTagMustMatchBundleVersion() throws {
        let matching = try runScript(
            named: "build-distribution.sh",
            arguments: ["--verify-tag", "v0.1.0"]
        )
        let mismatching = try runScript(
            named: "build-distribution.sh",
            arguments: ["--verify-tag", "v0.2.0"]
        )

        XCTAssertEqual(matching.terminationStatus, 0, matching.standardError)
        XCTAssertEqual(mismatching.terminationStatus, 65)
    }

    func testHomebrewCaskGeneratorUsesPublicReleaseContract() throws {
        let checksum = String(repeating: "a", count: 64)
        let result = try runScript(
            named: "render-homebrew-cask.sh",
            arguments: ["--sha256", checksum]
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertTrue(result.standardOutput.contains("cask \"external-display-viewer\" do"))
        XCTAssertTrue(result.standardOutput.contains("version \"0.1.0\""))
        XCTAssertTrue(result.standardOutput.contains("sha256 \"\(checksum)\""))
        XCTAssertTrue(
            result.standardOutput.contains(
                "https://github.com/RealTake/external-display-viewer/releases/download/"
                    + "v#{version}/ExternalDisplayViewer-v#{version}-macOS-arm64.zip"
            )
        )
        XCTAssertTrue(result.standardOutput.contains("depends_on arch: :arm64"))
        XCTAssertTrue(result.standardOutput.contains("depends_on macos: :sequoia"))
        XCTAssertTrue(result.standardOutput.contains("app \"ExternalDisplayViewer.app\""))
    }

    func testHomebrewCaskGeneratorRejectsInvalidChecksum() throws {
        let result = try runScript(
            named: "render-homebrew-cask.sh",
            arguments: ["--sha256", "not-a-checksum"]
        )

        XCTAssertEqual(result.terminationStatus, 64)
        XCTAssertTrue(result.standardError.contains("64 lowercase hexadecimal characters"))
    }

    func testVisualQACaptureScopesWindowLookupToNewlyLaunchedBundleProcess() throws {
        let captureScript = try script(named: "capture-visual-qa.sh")
        let windowLookup = try script(named: "window-id.swift")

        XCTAssertTrue(captureScript.contains("--bundle-pid \"$QA_APP\""))
        XCTAssertTrue(captureScript.contains("--owner-pid \"$app_pid\" \"$title\""))
        XCTAssertTrue(captureScript.contains("--activate \"$app_pid\""))
        XCTAssertTrue(captureScript.contains("screencapture -x -o -l \"$window_id\""))
        XCTAssertFalse(captureScript.contains("\"$WINDOW_LOOKUP_BINARY\" \"$title\""))
        XCTAssertTrue(windowLookup.contains("NSRunningApplication"))
        XCTAssertTrue(windowLookup.contains("NSRunningApplication(processIdentifier:"))
        XCTAssertTrue(windowLookup.contains("kCGWindowOwnerPID"))
    }

    func testSelectionAndVisualQAPreviewShareScreenRecordingGuidance() throws {
        let rootView = try source(named: "UI/RootView.swift")
        let preview = try source(named: "UI/VisualQAPreviewRoot.swift")

        XCTAssertEqual(PermissionGuidanceCopy.screenRecordingNote, "허용 후 앱 재시작 필요")
        XCTAssertEqual(
            PermissionGuidanceCopy.screenRecordingRestartGuidance,
            "Screen Recording을 허용한 뒤 앱을 완전히 종료하고 다시 실행하세요."
        )
        XCTAssertTrue(rootView.contains("PermissionGuidanceCopy.screenRecordingNote"))
        XCTAssertTrue(preview.contains("PermissionGuidanceCopy.screenRecordingNote"))
        XCTAssertTrue(rootView.contains("PermissionGuidanceCopy.screenRecordingRestartGuidance"))
        XCTAssertTrue(preview.contains("PermissionGuidanceCopy.screenRecordingRestartGuidance"))
    }

    private func buildScript() throws -> String {
        try script(named: "build-app.sh")
    }

    private func script(named name: String) throws -> String {
        let scriptURL = packageRoot.appendingPathComponent("Scripts/\(name)")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

    private func source(named name: String) throws -> String {
        let sourceURL = packageRoot.appendingPathComponent("Sources/ExternalDisplayViewerCore/\(name)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func runScript(
        named name: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [packageRoot.appendingPathComponent("Scripts/\(name)").path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
            override
        }

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            standardError: String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }

    private func writeExecutable(named name: String, in directory: URL, contents: String) throws {
        let executable = directory.appendingPathComponent(name)
        try contents.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CommandResult {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}
