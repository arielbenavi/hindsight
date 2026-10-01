import SwiftUI

/// A small looping "what to tap in WhatsApp" animation: a mock phone screen
/// that steps through a flow, highlighting the next tap. Generic chat-app
/// look (no WhatsApp branding), built from plain SwiftUI shapes.
struct WhatsAppGuide: View {
    enum Flow { case addBot, export, exportToBot }

    let flow: Flow
    @State private var step = 0

    private var steps: [(caption: String, screen: Screen)] {
        switch flow {
        case .addBot:
            [("Open your notes chat, tap its name", .chat),
             ("Tap “Add members”", .info(highlight: "Add members")),
             ("Pick hindsight", .contacts),
             ("Share the last 100 messages", .shareHistory)]
        case .export:
            [("Open your notes chat, tap its name", .chat),
             ("Scroll down, tap “Export chat”", .info(highlight: "Export chat")),
             ("Choose “Without media”", .exportOptions),
             ("Pick hindsight", .shareSheet)]
        case .exportToBot:
            [("Open your old notes chat, tap its name", .chat),
             ("Scroll down, tap “Export chat”", .info(highlight: "Export chat")),
             ("Choose “Without media”", .exportOptions),
             ("Share to WhatsApp", .shareSheetWhatsApp),
             ("Send it to hindsight", .contacts)]
        }
    }

    enum Screen: Equatable {
        case chat, info(highlight: String), contacts, shareHistory, exportOptions, shareSheet, shareSheetWhatsApp
    }

    var body: some View {
        VStack(spacing: 10) {
            phone(steps[step].screen)
                .id(step)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            HStack(spacing: 8) {
                Text("\(step + 1)")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(OnboardingStyle.onAccent)
                    .frame(width: 20, height: 20)
                    .background(OnboardingStyle.accent, in: .circle)
                Text(steps[step].caption)
                    .font(OnboardingStyle.caption)
                    .contentTransition(.opacity)
            }
            .id("caption-\(step)")
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                step = (step + 1) % steps.count
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.map(\.caption).joined(separator: ", then "))
    }

    // MARK: - Mock screens

    private let chatGreen = Color(red: 0.15, green: 0.68, blue: 0.38)

    private func phone(_ screen: Screen) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.07))
            RoundedRectangle(cornerRadius: 26).stroke(OnboardingStyle.stroke, lineWidth: 2)
            VStack(spacing: 0) {
                switch screen {
                case .chat: chatScreen
                case .info(let highlight): infoScreen(highlight)
                case .contacts: listScreen(title: "Add members", rows: ["Mom", "hindsight", "Reut"], highlight: "hindsight", check: true)
                case .shareHistory: listScreen(title: "Share recent messages?", rows: ["Don't share", "Last 25", "Last 100"], highlight: "Last 100", check: true)
                case .exportOptions: exportOptions
                case .shareSheet: shareSheet
                case .shareSheetWhatsApp: shareSheetWhatsApp
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 210, height: 205)
    }

    private var chatScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(chatGreen).frame(width: 26, height: 26)
                    .overlay(Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(.white))
                Text("Notes").font(.system(size: 13, weight: .bold))
                Spacer()
            }
            .padding(6)
            .background(highlightBox)
            ForEach(["call mom", "instagram.com/reel/…", "groceries: eggs, oat milk"], id: \.self) { text in
                Text(text)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(chatGreen.opacity(0.35), in: .rect(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func infoScreen(_ highlight: String) -> some View {
        listScreen(title: "Notes", rows: ["Media, links and docs", "Starred messages", "Add members", "Export chat"],
                   highlight: highlight, check: false)
    }

    private func listScreen(title: String, rows: [String], highlight: String, check: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .bold)).padding(.bottom, 4)
            ForEach(rows, id: \.self) { row in
                HStack {
                    Text(row).font(.system(size: 11, weight: row == highlight ? .bold : .regular))
                    Spacer()
                    if check && row == highlight {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(chatGreen)
                    }
                }
                .padding(7)
                .background(row == highlight ? AnyShapeStyle(highlightBox) : AnyShapeStyle(Color(white: 0.13)),
                            in: .rect(cornerRadius: 8))
            }
        }
    }

    private var exportOptions: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 30)
            Text("Export chat").font(.system(size: 12, weight: .bold))
            ForEach(["Attach media", "Without media"], id: \.self) { option in
                Text(option)
                    .font(.system(size: 12, weight: option == "Without media" ? .bold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(option == "Without media" ? AnyShapeStyle(highlightBox) : AnyShapeStyle(Color(white: 0.13)),
                                in: .rect(cornerRadius: 10))
            }
        }
    }

    private var shareSheet: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 40)
            HStack(spacing: 10) {
                appIcon("Messages", Color.green, highlighted: false)
                appIcon("Mail", Color.blue, highlighted: false)
                appIcon("hindsight", OnboardingStyle.accent, highlighted: true)
            }
            .padding(10)
            .background(Color(white: 0.13), in: .rect(cornerRadius: 14))
        }
    }

    private var shareSheetWhatsApp: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 40)
            HStack(spacing: 10) {
                appIcon("Messages", Color.green, highlighted: false)
                appIcon("Mail", Color.blue, highlighted: false)
                appIcon("WhatsApp", chatGreen, highlighted: true, symbol: "phone.bubble.fill")
            }
            .padding(10)
            .background(Color(white: 0.13), in: .rect(cornerRadius: 14))
        }
    }

    private func appIcon(_ name: String, _ color: Color, highlighted: Bool, symbol: String? = nil) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 9).fill(color).frame(width: 36, height: 36)
                .overlay {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.white)
                    } else if highlighted {
                        Text("h.").font(.system(size: 13, weight: .black)).foregroundStyle(.black)
                    }
                }
                .overlay(highlighted ? RoundedRectangle(cornerRadius: 11).stroke(OnboardingStyle.accent, lineWidth: 2).padding(-3) : nil)
            Text(name).font(.system(size: 9, weight: highlighted ? .bold : .regular))
        }
    }

    /// The pulsing "tap here" highlight.
    private var highlightBox: some ShapeStyle {
        OnboardingStyle.accent.opacity(0.28)
    }
}

#Preview {
    HStack(spacing: 20) {
        WhatsAppGuide(flow: .addBot)
        WhatsAppGuide(flow: .exportToBot)
    }
    .padding()
    .background(.black)
    .preferredColorScheme(.dark)
}
