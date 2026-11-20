#if os(iOS)
import AppIntents
import Foundation

struct BreeWidgetPlayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play BreeMusic"
    static let description = IntentDescription("Resume the current BreeMusic track.")

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("BreeMusic.Widget.Play"), object: nil)
        return .result()
    }
}

struct BreeWidgetPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause BreeMusic"
    static let description = IntentDescription("Pause the current BreeMusic track.")

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("BreeMusic.Widget.Pause"), object: nil)
        return .result()
    }
}

struct BreeWidgetNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next BreeMusic track"
    static let description = IntentDescription("Play the next track in BreeMusic.")

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("BreeMusic.Widget.Next"), object: nil)
        return .result()
    }
}

struct BreeWidgetPreviousIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous BreeMusic track"
    static let description = IntentDescription("Play the previous track in BreeMusic.")

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("BreeMusic.Widget.Previous"), object: nil)
        return .result()
    }
}
#endif

