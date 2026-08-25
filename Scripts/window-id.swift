import AppKit
import CoreGraphics
import Foundation

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--bundle-pid" {
    let expectedBundleURL = URL(fileURLWithPath: CommandLine.arguments[2])
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let applications: [NSRunningApplication] = NSWorkspace.shared.runningApplications

    for application in applications where !application.isTerminated {
        guard let bundleURL = application.bundleURL?
            .resolvingSymlinksInPath()
            .standardizedFileURL else {
            continue
        }
        if bundleURL == expectedBundleURL {
            print(application.processIdentifier)
            exit(0)
        }
    }
    exit(1)
}

if
    CommandLine.arguments.count == 3,
    CommandLine.arguments[1] == "--activate",
    let processID = Int32(CommandLine.arguments[2]),
    let application = NSRunningApplication(processIdentifier: processID)
{
    exit(application.activate(options: [.activateAllWindows]) ? 0 : 1)
}

if
    CommandLine.arguments.count == 3,
    CommandLine.arguments[1] == "--owner-windows",
    let expectedOwnerPID = Int32(CommandLine.arguments[2])
{
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        exit(2)
    }

    for window in windows {
        guard
            let processID = window[kCGWindowOwnerPID as String] as? NSNumber,
            processID.int32Value == expectedOwnerPID
        else {
            continue
        }
        let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
        let title = window[kCGWindowName as String] as? String ?? ""
        print("\(number)\t\(layer)\t\(title)")
    }
    exit(0)
}

guard (2...4).contains(CommandLine.arguments.count) else {
    exit(64)
}

let printsOwnerPID = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--pid"
let filtersOwnerPID = CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--owner-pid"
let expectedOwnerPID = filtersOwnerPID ? Int32(CommandLine.arguments[2]) : nil
guard !filtersOwnerPID || expectedOwnerPID != nil else {
    exit(64)
}
let expectedTitle = printsOwnerPID
    ? CommandLine.arguments[2]
    : filtersOwnerPID ? CommandLine.arguments[3] : CommandLine.arguments[1]
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}

for window in windows {
    if expectedTitle == "--list" {
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let title = window[kCGWindowName as String] as? String ?? ""
        let number = window[kCGWindowNumber as String] as? NSNumber
        let layer = window[kCGWindowLayer as String] as? NSNumber
        print("\(number?.uint32Value ?? 0)\t\(layer?.intValue ?? -1)\t\(owner)\t\(title)")
        continue
    }

    guard
        window[kCGWindowName as String] as? String == expectedTitle,
        let number = window[kCGWindowNumber as String] as? NSNumber,
        let layer = window[kCGWindowLayer as String] as? NSNumber,
        layer.intValue == 0
    else {
        continue
    }
    if let expectedOwnerPID {
        guard
            let processID = window[kCGWindowOwnerPID as String] as? NSNumber,
            processID.int32Value == expectedOwnerPID
        else {
            continue
        }
    }

    if printsOwnerPID, let processID = window[kCGWindowOwnerPID as String] as? NSNumber {
        print(processID.int32Value)
    } else {
        print(number.uint32Value)
    }
    exit(0)
}

if expectedTitle == "--list" {
    exit(0)
}

exit(1)
