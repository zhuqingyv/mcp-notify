import Foundation
import AppKit
import UserNotifications

// ── Argument parsing ──────────────────────────────────────────────────────────

func parseArgs() -> [String: String] {
    var result: [String: String] = [:]
    let args = CommandLine.arguments.dropFirst()
    var i = args.startIndex
    while i < args.endIndex {
        let key = args[i]
        let nextIndex = args.index(after: i)
        if key.hasPrefix("--"), nextIndex < args.endIndex {
            result[String(key.dropFirst(2))] = args[nextIndex]
            i = args.index(after: nextIndex)
        } else {
            i = args.index(after: i)
        }
    }
    return result
}

// ── Notification delegate ─────────────────────────────────────────────────────

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var activateBundleId: String?

    // Allow notifications while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle click: activate the target terminal app
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let bundleId = activateBundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        }
        completionHandler()
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────

let args = parseArgs()

guard let message = args["message"], !message.isEmpty else {
    fputs("Error: --message is required\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

let delegate = NotificationDelegate()
delegate.activateBundleId = args["activate"]

let center = UNUserNotificationCenter.current()
center.delegate = delegate

// Request permission (non-blocking on subsequent runs if already granted)
let semAuth = DispatchSemaphore(value: 0)
var authGranted = false
center.requestAuthorization(options: [.alert, .sound]) { granted, error in
    authGranted = granted
    if let error = error {
        fputs("Auth error: \(error.localizedDescription)\n", stderr)
    }
    semAuth.signal()
}
semAuth.wait()

guard authGranted else {
    fputs("Error: notification permission denied. Enable in System Settings > Notifications.\n", stderr)
    exit(2)
}

// Build notification content
let content = UNMutableNotificationContent()
content.title = args["title"] ?? ""
content.body  = message
if let subtitle = args["subtitle"] { content.subtitle = subtitle }
content.sound = UNNotificationSound(named: UNNotificationSoundName(args["sound"] ?? "Glass"))

// Attach icon PNG as notification attachment (shows on right side)
if let iconPath = args["icon"] {
    let iconURL = URL(fileURLWithPath: iconPath)
    // Copy to a temp location with .png extension so UNNotificationAttachment accepts it
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".png")
    do {
        try FileManager.default.copyItem(at: iconURL, to: tmp)
        let attachment = try UNNotificationAttachment(
            identifier: "icon",
            url: tmp,
            options: [UNNotificationAttachmentOptionsThumbnailClippingRectKey:
                        CGRect(x: 0, y: 0, width: 1, height: 1) as AnyObject]
        )
        content.attachments = [attachment]
    } catch {
        fputs("Warning: could not attach icon: \(error.localizedDescription)\n", stderr)
    }
}

// Fire immediately
let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
let request = UNNotificationRequest(
    identifier: UUID().uuidString,
    content: content,
    trigger: trigger
)

let semSend = DispatchSemaphore(value: 0)
var sendError: Error?
center.add(request) { error in
    sendError = error
    semSend.signal()
}
semSend.wait()

if let error = sendError {
    fputs("Error sending notification: \(error.localizedDescription)\n", stderr)
    exit(3)
}

// Keep runloop alive briefly so the notification can fire and delegate callbacks work
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
    exit(0)
}
app.run()
