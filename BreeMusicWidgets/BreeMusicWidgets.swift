import AppIntents
import SwiftUI
import WidgetKit

private struct BreeMusicWidgetEntry: TimelineEntry {
    let date: Date
}
private struct BreeMusicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BreeMusicWidgetEntry {
        BreeMusicWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (BreeMusicWidgetEntry) -> Void) {
        completion(BreeMusicWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BreeMusicWidgetEntry>) -> Void) {
        let entry = BreeMusicWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct BreeMusicWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BreeMusic", systemImage: "waveform")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 0) {
                control("backward.end.fill", label: "Previous track", intent: BreeWidgetPreviousIntent())
                Spacer(minLength: 2)
                control("play.fill", label: "Play", intent: BreeWidgetPlayIntent())
                Spacer(minLength: 2)
                control("pause.fill", label: "Pause", intent: BreeWidgetPauseIntent())
                Spacer(minLength: 2)
                control("forward.end.fill", label: "Next track", intent: BreeWidgetNextIntent())
            }
            .tint(.cyan)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            Color(red: 0.035, green: 0.075, blue: 0.16)
        }
    }

    private func control<I: AppIntent>(_ symbol: String, label: String, intent: I) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct BreeMusicWidget: Widget {
    let kind = "BreeMusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreeMusicWidgetProvider()) { _ in
            BreeMusicWidgetView()
        }
        .configurationDisplayName("BreeMusic Controls")
        .description("Play, pause, or skip the current BreeMusic queue.")
        .supportedFamilies([.systemSmall])
    }
}
