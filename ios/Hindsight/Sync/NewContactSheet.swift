import ContactsUI
import SwiftUI

/// iOS's own "New Contact" card, filled in with hindsight's WhatsApp number and
/// logo, so saving it is one tap (and it then shows up in WhatsApp's "Add members").
/// Runs out of process, so it needs no Contacts permission.
struct NewContactSheet: UIViewControllerRepresentable {
    let number: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.givenName = "hindsight"
        contact.phoneNumbers = [CNLabeledValue(label: "WhatsApp", value: CNPhoneNumber(stringValue: "+\(number)"))]
        contact.note = "Send notes and links here; they show up in the hindsight app."
        contact.imageData = Self.logoPNG()
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            DebugLog.write("whatsapp contact \(contact == nil ? "cancelled" : "saved")")
            dismiss()
        }
    }

    /// The app icon's look ("h." in a ring), drawn here since the icon itself
    /// isn't readable as an image at runtime.
    @MainActor
    static func logoPNG() -> Data? {
        let renderer = ImageRenderer(content: ContactLogo())
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}

private struct ContactLogo: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.08)
            Circle().stroke(Color(white: 0.16), lineWidth: 28).padding(56)
            Circle().trim(from: 0, to: 0.62)
                .stroke(OnboardingStyle.accent, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(56)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("h").font(.system(size: 190, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Circle().fill(OnboardingStyle.accent).frame(width: 40, height: 40)
            }
        }
        .frame(width: 512, height: 512)
    }
}

#Preview {
    ContactLogo().scaleEffect(0.5)
}
