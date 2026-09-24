import UIKit
import UniformTypeIdentifiers

/// iOS share sheet entry that writes into the App Group format
/// `receive_sharing_intent` 1.8.1 already reads from the host app.
final class ShareViewController: UIViewController {
    private let userDefaultsKey = "ShareKey"
    private let userDefaultsMessageKey = "ShareMessageKey"
    private let schemePrefix = "ShareMedia"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        processSharePayload()
    }

    private func processSharePayload() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }

        let group = DispatchGroup()
        var shared: [[String: Any]] = []
        var messages: [String] = []
        let lock = NSLock()

        for item in items {
            if let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                messages.append(title)
            }
            if let text = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                messages.append(text)
            }

            for attachment in item.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                        defer { group.leave() }
                        let value: String?
                        if let url = data as? URL {
                            value = url.absoluteString
                        } else {
                            value = data as? String
                        }
                        guard let value, !value.isEmpty else { return }
                        lock.lock()
                        shared.append(Self.media(path: value, type: "url"))
                        messages.append(value)
                        lock.unlock()
                    }
                    continue
                }

                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                        defer { group.leave() }
                        let value: String?
                        if let text = data as? String {
                            value = text
                        } else if let url = data as? URL {
                            value = url.absoluteString
                        } else {
                            value = nil
                        }
                        guard let value, !value.isEmpty else { return }
                        lock.lock()
                        shared.append(Self.media(path: value, type: "text", mimeType: "text/plain"))
                        messages.append(value)
                        lock.unlock()
                    }
                    continue
                }

                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        if let url = data as? URL {
                            lock.lock()
                            shared.append(Self.media(path: url.absoluteString, type: "image"))
                            lock.unlock()
                            return
                        }
                        if let image = data as? UIImage,
                           let path = self.writeTempImage(image) {
                            lock.lock()
                            shared.append(
                                Self.media(path: path, type: "image", mimeType: "image/png"),
                            )
                            lock.unlock()
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.saveAndRedirect(shared: shared, message: messages.joined(separator: "\n"))
        }
    }

    private func saveAndRedirect(shared: [[String: Any]], message: String) {
        let defaults = UserDefaults(suiteName: appGroupId)
        if let data = try? JSONSerialization.data(withJSONObject: shared, options: []) {
            defaults?.set(data, forKey: userDefaultsKey)
        }
        defaults?.set(message, forKey: userDefaultsMessageKey)
        defaults?.synchronize()
        openHostApp()
        finish()
    }

    private func openHostApp() {
        guard let url = URL(string: "\(schemePrefix)-\(hostBundleId):share") else { return }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func writeTempImage(_ image: UIImage) -> String? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId,
        ) else {
            return nil
        }
        let dest = container.appendingPathComponent("TempImage.png")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try image.pngData()?.write(to: dest)
            return dest.absoluteString.removingPercentEncoding
        } catch {
            return nil
        }
    }

    private var appGroupId: String {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String,
           !custom.isEmpty,
           !custom.contains("$(") {
            return custom
        }
        return "group.\(hostBundleId)"
    }

    private var hostBundleId: String {
        let extensionId = Bundle.main.bundleIdentifier ?? "com.softstudio.wishlist.ShareExtension"
        if let lastDot = extensionId.lastIndex(of: ".") {
            return String(extensionId[..<lastDot])
        }
        return "com.softstudio.wishlist"
    }

    private static func media(
        path: String,
        type: String,
        mimeType: String? = nil,
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "path": path,
            "type": type,
        ]
        if let mimeType {
            payload["mimeType"] = mimeType
        }
        return payload
    }
}
