import Foundation
import Network
import Photos
import TelegramUIPreferences

/// Handles opt-in social-video downloads for links typed into a chat. The
/// operation is entirely local: the original text message still follows
/// Telegram's normal send path, while the downloaded file is written to the
/// user's chosen local destination.
public final class MiraSocialVideoDownloader {
    private static let queue = DispatchQueue(label: "org.telegram.mira.socialVideoDownloader", qos: .utility)
    private static let pathMonitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: queue)
        return monitor
    }()

    public static func enqueue(text: String, settings: MiraSocialVideoSettings) {
        guard settings.enabled else {
            return
        }
        let candidates = text.split(whereSeparator: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "\"" }).compactMap { MiraSocialVideoLinkParser.parse(String($0)) }
        let links = candidates.filter { settings.isEnabled($0.platform) }
        guard !links.isEmpty, !settings.confirmBeforeDownload else {
            return
        }
        guard !settings.wifiOnly || (Self.pathMonitor.currentPath.status == .satisfied && Self.pathMonitor.currentPath.usesInterfaceType(.wifi)) else {
            return
        }
        for link in links {
            queue.async {
                Self.download(link: link, destination: settings.destination)
            }
        }
    }

    private static func download(link: MiraSocialVideoLink, destination saveDestination: MiraSocialVideoDestination) {
        let task = URLSession.shared.downloadTask(with: link.url) { location, _, _ in
            guard let location else {
                return
            }
            let fileName = "stuxnet-\(UUID().uuidString).mp4"
            let destinationURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            do {
                try FileManager.default.moveItem(at: location, to: destinationURL)
            } catch {
                return
            }
            guard saveDestination == .photos else {
                return
            }
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized || status == .limited else {
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)
                }
            }
        }
        task.resume()
    }
}
