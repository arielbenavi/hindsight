import SwiftUI

// Looping "what to tap" animations: a small phone that steps through the real
// screens of another app, with a pulsing marker on the next tap. Drawn from plain
// SwiftUI shapes to look like the real thing (dark mode, same layout and wording),
// without any logos.

// MARK: - Shared phone + stepper

/// One step of a guide: what to do, and the screen it happens on.
struct GuideStep {
    let caption: String
    let screen: AnyView
    init(_ caption: String, @ViewBuilder _ screen: () -> some View) {
        self.caption = caption
        self.screen = AnyView(screen())
    }
}

struct PhoneGuide: View {
    let steps: [GuideStep]
    var interval: Double = 2.4
    @State private var index = 0

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 30).fill(.black)
                steps[index].screen
                    .frame(width: 214, height: 384)
                    .clipShape(.rect(cornerRadius: 24))
                    .id(index)
                    .transition(.opacity)
                RoundedRectangle(cornerRadius: 30).stroke(Color(white: 0.22), lineWidth: 3)
            }
            .frame(width: 226, height: 396)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(OnboardingStyle.onAccent)
                    .frame(width: 20, height: 20)
                    .background(OnboardingStyle.accent, in: .circle)
                Text(steps[index].caption)
                    .font(OnboardingStyle.caption)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }
            .frame(minHeight: 40, alignment: .top)
            .id("caption-\(index)")
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i == index ? OnboardingStyle.accent : Color(white: 0.25))
                        .frame(width: i == index ? 14 : 5, height: 5)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: index)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                index = (index + 1) % steps.count
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.map(\.caption).joined(separator: ", then "))
    }
}

/// The pulsing "tap here" marker.
private struct TapMarker: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.35)).frame(width: 26, height: 26)
            Circle().stroke(.white.opacity(0.8), lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse ? 0 : 1)
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

extension View {
    /// Marks the element the user should tap next.
    func tapHere(_ active: Bool = true, alignment: Alignment = .center) -> some View {
        overlay(alignment: alignment) { if active { TapMarker() } }
    }
}

// MARK: - WhatsApp (dark mode)

private enum WA {
    static let bg = Color(red: 0.04, green: 0.08, blue: 0.10)
    static let bar = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let green = Color(red: 0.13, green: 0.75, blue: 0.39)
    static let bubble = Color(red: 0.08, green: 0.30, blue: 0.22)
    static let row = Color(white: 0.11)
    static let muted = Color(white: 0.55)
    static let sheet = Color(white: 0.14)
}

struct WhatsAppGuide: View {
    enum Flow { case addBot, export, exportToBot }
    let flow: Flow

    var body: some View { PhoneGuide(steps: steps) }

    var steps: [GuideStep] {
        switch flow {
        case .addBot:
            [
                GuideStep("Open your notes group, tap its name at the top") { chat(tapTitle: true) },
                GuideStep("Scroll to the members, tap “Add members”") { info(target: "Add members") },
                GuideStep("Pick hindsight, then tap Add") { picker(title: "Add members", action: "Add") },
                GuideStep("If asked, share the last 100 messages") { shareHistory },
            ]
        case .export:
            [
                GuideStep("Open your notes chat, tap its name at the top") { chat(tapTitle: true) },
                GuideStep("Scroll down, tap “Export chat”") { info(target: "Export chat") },
                GuideStep("Choose “Without Media”") { exportSheet },
                GuideStep("Tap “Save to Files”, then pick that file in hindsight") { shareSheet(target: .files) },
            ]
        case .exportToBot:
            [
                GuideStep("Open your old notes chat, tap its name at the top") { chat(tapTitle: true) },
                GuideStep("Scroll down, tap “Export chat”") { info(target: "Export chat") },
                GuideStep("Choose “Without Media”") { exportSheet },
                GuideStep("In the share sheet, tap WhatsApp") { shareSheet(target: .whatsApp) },
                GuideStep("Pick hindsight and send") { picker(title: "Send to", action: "send") },
                GuideStep("hindsight replies with what it imported") { botReply },
            ]
        }
    }

    // Screens

    private func navBar(title: String, subtitle: String?, tapTitle: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(WA.green)
            Circle().fill(Color(white: 0.3)).frame(width: 26, height: 26)
                .overlay(Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 8)).foregroundStyle(WA.muted) }
            }
            .tapHere(tapTitle, alignment: .leading)
            Spacer()
            Image(systemName: "video").font(.system(size: 12)).foregroundStyle(WA.green)
            Image(systemName: "phone").font(.system(size: 11)).foregroundStyle(WA.green)
        }
        .padding(.horizontal, 10).padding(.top, 28).padding(.bottom, 8)
        .background(WA.bar)
    }

    private func bubble(_ text: String, time: String = "9:41", incoming: Bool = false) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(text).font(.system(size: 10))
            Text(time).font(.system(size: 7)).foregroundStyle(.white.opacity(0.55))
            if !incoming {
                Image(systemName: "checkmark").font(.system(size: 6, weight: .bold)).foregroundStyle(.cyan)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(incoming ? Color(white: 0.15) : WA.bubble, in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
    }

    private func chat(tapTitle: Bool) -> some View {
        VStack(spacing: 0) {
            navBar(title: "Notes", subtitle: "tap here for group info", tapTitle: tapTitle)
            VStack(spacing: 5) {
                Spacer()
                Text("Today").font(.system(size: 8, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(white: 0.16), in: .capsule)
                bubble("call mom")
                bubble("instagram.com/reel/DdyvE…")
                bubble("groceries: eggs, oat milk")
                bubble("book on habits?")
            }
            .padding(8)
            inputBar
        }
        .background(WA.bg)
    }

    private var inputBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(WA.green)
            Capsule().fill(Color(white: 0.17)).frame(height: 22)
            Image(systemName: "camera").font(.system(size: 11)).foregroundStyle(WA.green)
            Image(systemName: "mic").font(.system(size: 11)).foregroundStyle(WA.green)
        }
        .padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 16)
        .background(WA.bar)
    }

    private func info(target: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(WA.green)
                Spacer()
                Text("Edit").font(.system(size: 10)).foregroundStyle(WA.green)
            }
            .padding(.horizontal, 10).padding(.top, 28)
            Circle().fill(Color(white: 0.3)).frame(width: 46, height: 46)
                .overlay(Image(systemName: "note.text").font(.system(size: 18)).foregroundStyle(.white))
            VStack(spacing: 1) {
                Text("Notes").font(.system(size: 14, weight: .semibold))
                Text("Group · 2 members").font(.system(size: 8)).foregroundStyle(WA.muted)
            }
            HStack(spacing: 6) {
                ForEach(["phone", "video", "person.badge.plus", "magnifyingglass"], id: \.self) { symbol in
                    RoundedRectangle(cornerRadius: 7).fill(WA.row).frame(height: 30)
                        .overlay(Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(WA.green))
                }
            }
            .padding(.horizontal, 10)
            group(["Media, links and docs", "Starred"])
            if target == "Add members" {
                group(["Add members", "You", "Reut"], green: "Add members", target: target)
            } else {
                group(["Export chat", "Clear chat"], red: "Clear chat", target: target)
            }
            Spacer(minLength: 0)
        }
        .background(Color.black)
    }

    private func group(_ rows: [String], green: String? = nil, red: String? = nil, target: String? = nil) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 7) {
                    if row == green {
                        Image(systemName: "plus.circle.fill").font(.system(size: 13)).foregroundStyle(WA.green)
                    }
                    Text(row).font(.system(size: 10))
                        .foregroundStyle(row == green ? WA.green : row == red ? .red : .white)
                    Spacer()
                    if row != green && row != red && row != "Export chat" {
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(WA.muted)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .tapHere(row == target)
                if row != rows.last { Divider().overlay(Color(white: 0.2)).padding(.leading, 9) }
            }
        }
        .background(WA.row, in: .rect(cornerRadius: 9))
        .padding(.horizontal, 10)
    }

    private var exportSheet: some View {
        ZStack(alignment: .bottom) {
            info(target: "").overlay(Color.black.opacity(0.5))
            VStack(spacing: 6) {
                VStack(spacing: 0) {
                    Text("Attaching media will generate a larger chat archive.")
                        .font(.system(size: 8)).foregroundStyle(WA.muted).multilineTextAlignment(.center)
                        .padding(8)
                    Divider().overlay(Color(white: 0.25))
                    Text("Attach Media").font(.system(size: 12)).foregroundStyle(WA.green).padding(9)
                    Divider().overlay(Color(white: 0.25))
                    Text("Without Media").font(.system(size: 12)).foregroundStyle(WA.green).padding(9).tapHere()
                }
                .frame(maxWidth: .infinity)
                .background(WA.sheet, in: .rect(cornerRadius: 12))
                Text("Cancel").font(.system(size: 12, weight: .semibold)).foregroundStyle(WA.green)
                    .frame(maxWidth: .infinity).padding(9)
                    .background(WA.sheet, in: .rect(cornerRadius: 12))
            }
            .padding(8).padding(.bottom, 8)
        }
    }

    private enum ShareTarget { case files, whatsApp }

    private func shareSheet(target: ShareTarget) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.25)).frame(width: 26, height: 30)
                        .overlay(Image(systemName: "doc.zipper").font(.system(size: 11)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WhatsApp Chat - Notes").font(.system(size: 9, weight: .semibold))
                        Text("ZIP Archive · 12 KB").font(.system(size: 7)).foregroundStyle(WA.muted)
                    }
                    Spacer()
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color(white: 0.35))
                }
                HStack(spacing: 9) {
                    ForEach(Array(zip(["AirDrop", "Messages", "Mail", "WhatsApp"],
                                      [Color.blue, .green, .blue, WA.green])), id: \.0) { name, color in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 9).fill(color).frame(width: 34, height: 34)
                                .overlay(Image(systemName: name == "WhatsApp" ? "phone.bubble.fill"
                                               : name == "Mail" ? "envelope.fill"
                                               : name == "Messages" ? "message.fill" : "dot.radiowaves.left.and.right")
                                    .font(.system(size: 14)).foregroundStyle(.white))
                                .tapHere(target == .whatsApp && name == "WhatsApp")
                            Text(name).font(.system(size: 7))
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(["Copy", "Save to Files", "Add to New Quick Note"], id: \.self) { row in
                        HStack {
                            Text(row).font(.system(size: 10))
                            Spacer()
                            Image(systemName: row == "Copy" ? "doc.on.doc" : row == "Save to Files" ? "folder" : "note.text")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .tapHere(target == .files && row == "Save to Files")
                        if row != "Add to New Quick Note" { Divider().overlay(Color(white: 0.25)) }
                    }
                }
                .background(Color(white: 0.2), in: .rect(cornerRadius: 9))
            }
            .padding(10).padding(.bottom, 12)
            .background(WA.sheet, in: .rect(cornerRadius: 18))
        }
    }

    private func picker(title: String, action: String) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text("Cancel").font(.system(size: 10)).foregroundStyle(WA.green)
                Spacer()
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(action == "Add" ? "Add" : "    ").font(.system(size: 10, weight: .semibold)).foregroundStyle(WA.green)
                    .tapHere(action == "Add")
            }
            .padding(.horizontal, 10).padding(.top, 24)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(WA.muted)
                Text("Search").font(.system(size: 9)).foregroundStyle(WA.muted)
                Spacer()
            }
            .padding(6).background(Color(white: 0.15), in: .rect(cornerRadius: 8)).padding(.horizontal, 10)
            VStack(spacing: 0) {
                ForEach(["Mom", "hindsight", "Reut", "Dan"], id: \.self) { name in
                    HStack(spacing: 7) {
                        Image(systemName: name == "hindsight" ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12)).foregroundStyle(name == "hindsight" ? WA.green : WA.muted)
                        Circle().fill(name == "hindsight" ? Color(red: 0.03, green: 0.04, blue: 0.08) : Color(white: 0.3))
                            .frame(width: 22, height: 22)
                            .overlay(name == "hindsight"
                                     ? Text("h.").font(.system(size: 9, weight: .black)).foregroundStyle(OnboardingStyle.accent)
                                     : nil)
                        Text(name).font(.system(size: 10, weight: name == "hindsight" ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .tapHere(name == "hindsight" && action != "Add" && action != "send")
                }
            }
            Spacer()
            if action == "send" {
                HStack {
                    Text("hindsight").font(.system(size: 9)).foregroundStyle(WA.muted)
                    Spacer()
                    Circle().fill(WA.green).frame(width: 28, height: 28)
                        .overlay(Image(systemName: "paperplane.fill").font(.system(size: 11)).foregroundStyle(.black))
                        .tapHere()
                }
                .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 16)
                .background(WA.bar)
            }
        }
        .background(Color.black)
    }

    private var shareHistory: some View {
        ZStack {
            chat(tapTitle: false).overlay(Color.black.opacity(0.55))
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Share recent messages?").font(.system(size: 11, weight: .semibold))
                    Text("New members can see messages from the last 14 days.")
                        .font(.system(size: 8)).foregroundStyle(WA.muted).multilineTextAlignment(.center)
                }
                .padding(10)
                ForEach(["Last 100 messages", "Last 25 messages", "Don't share"], id: \.self) { option in
                    Divider().overlay(Color(white: 0.25))
                    Text(option).font(.system(size: 11)).foregroundStyle(WA.green).padding(8)
                        .frame(maxWidth: .infinity)
                        .tapHere(option == "Last 100 messages")
                }
            }
            .background(WA.sheet, in: .rect(cornerRadius: 13))
            .padding(.horizontal, 22)
        }
    }

    private var botReply: some View {
        VStack(spacing: 0) {
            navBar(title: "hindsight", subtitle: "business account", tapTitle: false)
            VStack(spacing: 5) {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "doc.zipper").font(.system(size: 13))
                        Text("WhatsApp Chat - Notes.zip").font(.system(size: 9))
                    }
                    .padding(7).background(WA.bubble, in: .rect(cornerRadius: 8))
                }
                bubble("✓ Imported 84 links and 212 notes. Open hindsight to see them.", incoming: true)
            }
            .padding(8)
            inputBar
        }
        .background(WA.bg)
    }
}

// MARK: - Muse (Meta's AI app, dark mode)

private enum MS {
    static let bg = Color.black
    static let field = Color(white: 0.13)
    static let muted = Color(white: 0.55)
    static let ring = AngularGradient(colors: [.blue, .purple, .pink, .cyan, .blue], center: .center)
}

struct MuseGuide: View {
    enum Flow { case connector, paste }
    let flow: Flow

    var body: some View { PhoneGuide(steps: steps, interval: 2.6) }

    var steps: [GuideStep] {
        switch flow {
        case .connector:
            [
                GuideStep("Tap “Open Muse”. We copy the message for you") { hindsight(button: "Open Muse") },
                GuideStep("In Muse, tap the message box → Paste") { museChat(input: nil, pasteCallout: true) },
                GuideStep("Send it") { museChat(input: "Please add a custom connector named hindsight…", pasteCallout: false) },
                GuideStep("Tap “Always allow this site”") { allowPrompt },
                GuideStep("Muse sends your saves to hindsight") { museWorking },
                GuideStep("Come back: your saves are here") { hindsightDone },
            ]
        case .paste:
            [
                GuideStep("Tap “Open Muse”. We copy the message for you") { hindsight(button: "Open Muse") },
                GuideStep("In Muse, tap the message box → Paste") { museChat(input: nil, pasteCallout: true) },
                GuideStep("Send it") { museChat(input: "List my saved posts from Instagram and Facebook…", pasteCallout: false) },
                GuideStep("Long-press Muse's reply → Copy") { museJSON },
                GuideStep("Come back to hindsight and tap Paste") { hindsight(button: "Paste") },
                GuideStep("Your saves are here") { hindsightDone },
            ]
        }
    }

    private func museHeader() -> some View {
        HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal").font(.system(size: 12))
            Spacer()
            Circle().strokeBorder(MS.ring, lineWidth: 3).frame(width: 18, height: 18)
            Text("Muse").font(.system(size: 12, weight: .semibold))
            Spacer()
            Image(systemName: "square.and.pencil").font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.top, 28).padding(.bottom, 8)
    }

    private func museInput(_ text: String?, sendActive: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(MS.muted)
            Text(text ?? "Ask Muse")
                .font(.system(size: 9)).foregroundStyle(text == nil ? MS.muted : .white)
                .lineLimit(2)
            Spacer(minLength: 0)
            if text == nil {
                Image(systemName: "mic").font(.system(size: 11)).foregroundStyle(MS.muted)
            } else {
                Circle().fill(.white).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
                    .tapHere(sendActive)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(MS.field, in: .capsule)
        .padding(.horizontal, 10).padding(.bottom, 16)
    }

    private func museChat(input: String?, pasteCallout: Bool) -> some View {
        VStack(spacing: 0) {
            museHeader()
            Spacer()
            VStack(spacing: 6) {
                Circle().strokeBorder(MS.ring, lineWidth: 5).frame(width: 44, height: 44)
                Text("Ask Muse anything").font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            if pasteCallout {
                Text("Paste")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(white: 0.25), in: .capsule)
                    .tapHere()
                    .padding(.bottom, 4)
            }
            museInput(input, sendActive: input != nil)
        }
        .background(MS.bg)
    }

    private var allowPrompt: some View {
        VStack(spacing: 0) {
            museHeader()
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.03, green: 0.04, blue: 0.08))
                        .frame(width: 22, height: 22)
                        .overlay(Text("h.").font(.system(size: 9, weight: .black)).foregroundStyle(OnboardingStyle.accent))
                    Text("Connect to hindsight?").font(.system(size: 11, weight: .semibold))
                }
                Text("Muse will send information to this site.").font(.system(size: 8)).foregroundStyle(MS.muted)
                Text("Allow once").font(.system(size: 10, weight: .medium))
                    .frame(maxWidth: .infinity).padding(7).background(Color(white: 0.2), in: .capsule)
                Text("Always allow this site").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(7).background(.white, in: .capsule)
                    .tapHere()
                Text("Don't allow").font(.system(size: 10)).foregroundStyle(MS.muted).frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(MS.field, in: .rect(cornerRadius: 16))
            .padding(10)
            museInput(nil, sendActive: false)
        }
        .background(MS.bg)
    }

    private var museWorking: some View {
        VStack(alignment: .leading, spacing: 0) {
            museHeader()
            VStack(alignment: .leading, spacing: 7) {
                Spacer()
                Text("Please add a custom connector named hindsight…")
                    .font(.system(size: 9)).padding(7)
                    .background(MS.field, in: .rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                ForEach(["get_sync_status", "submit_saved_posts · 50", "submit_saved_posts · 50", "submit_saved_posts · 37"], id: \.self) { tool in
                    Label(tool, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(MS.muted)
                }
                Text("Done! I sent 137 saved posts to hindsight and set a daily sync at 9am.")
                    .font(.system(size: 10))
            }
            .padding(10)
            museInput(nil, sendActive: false)
        }
        .background(MS.bg)
    }

    private var museJSON: some View {
        VStack(alignment: .leading, spacing: 0) {
            museHeader()
            VStack(alignment: .leading, spacing: 7) {
                Spacer()
                Text("Here are your saved posts:").font(.system(size: 10))
                Text("{\"posts\": [\n  {\"url\": \"https://instagram…\",\n   \"author\": \"…\",\n   \"caption\": \"…\"},\n  …")
                    .font(.system(size: 8, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MS.field, in: .rect(cornerRadius: 10))
                    .overlay(alignment: .top) {
                        Text("Copy").font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color(white: 0.28), in: .capsule)
                            .tapHere()
                            .offset(y: -14)
                    }
            }
            .padding(10)
            museInput(nil, sendActive: false)
        }
        .background(MS.bg)
    }

    // Our own screen, as the user sees it in hindsight.
    private func hindsight(button: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer().frame(height: 40)
            Text("Sync with\nMuse.").font(.system(size: 24, weight: .black, design: .rounded))
            Text("It can already see your Instagram and Facebook saves.")
                .font(.system(size: 9)).foregroundStyle(MS.muted)
            Spacer()
            Text(button).font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(OnboardingStyle.onAccent)
                .frame(maxWidth: .infinity).padding(10)
                .background(OnboardingStyle.accent, in: .capsule)
                .tapHere()
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OnboardingStyle.background)
    }

    private var hindsightDone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer().frame(height: 40)
            Text("Sync with\nMuse.").font(.system(size: 24, weight: .black, design: .rounded))
            Label("+137 saves arrived from Muse", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(OnboardingStyle.accent)
            ForEach(["@chef.anna · reel", "@travelwithme · post", "@fitwithsam · reel"], id: \.self) { row in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.2)).frame(width: 26, height: 26)
                    Text(row).font(.system(size: 9))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OnboardingStyle.background)
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            WhatsAppGuide(flow: .exportToBot)
            WhatsAppGuide(flow: .addBot)
            MuseGuide(flow: .connector)
            MuseGuide(flow: .paste)
        }
        .padding()
    }
    .background(.black)
    .preferredColorScheme(.dark)
}
