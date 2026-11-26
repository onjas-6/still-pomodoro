import AppKit
import UserNotifications

extension AlertTone {
    var notificationSound: UNNotificationSound? {
        resourceName.map { UNNotificationSound(named: UNNotificationSoundName($0 + ".aiff")) }
    }

    func loadSound() -> NSSound? {
        guard let resourceName else { return NSSound(named: "Tink") }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "aiff") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }
}

final class AlertTonePlayer {
    private var current: NSSound?

    func play(_ tone: AlertTone) {
        current?.stop()
        current = tone.loadSound()
        if current?.play() != true { NSSound.beep() }
    }
}
