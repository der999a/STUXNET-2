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
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()
    private static let pathMonitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: queue)
        return monitor
    }()

    /// Returns supported links from a message without doing network work.
    /// Callers use this to present an explicit confirmation before starting a
    /// local download.
    public static func links(in text: String, settings: MiraSocialVideoSettings) -> [MiraSocialVideoLink] {
        guard settings.enabled else {
            return []
        }
        let candidates = text.split(whereSeparator: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "\"" }).compactMap { MiraSocialVideoLinkParser.parse(String($0)) }
        return candidates.filter { settings.isEnabled($0.platform) }
    }

    public static func enqueue(text: String, settings: MiraSocialVideoSettings) {
        let links = Self.links(in: text, settings: settings)
        guard !settings.confirmBeforeDownload else {
            return
        }
        Self.enqueue(links: links, settings: settings)
    }

    /// Starts confirmed local downloads. The caller is responsible for any UI
    /// confirmation; this method never sends or edits a Telegram message.
    public static func enqueue(links: [MiraSocialVideoLink], settings: MiraSocialVideoSettings) {
        guard settings.enabled else {
            return
        }
        let enabledLinks = links.filter { settings.isEnabled($0.platform) }
        guard !enabledLinks.isEmpty else {
            return
        }
        guard !settings.wifiOnly || (Self.pathMonitor.currentPath.status == .satisfied && Self.pathMonitor.currentPath.usesInterfaceType(.wifi)) else {
            return
        }
        for link in enabledLinks {
            queue.async {
                Self.resolveAndDownload(link: link, destination: settings.destination, quality: settings.quality)
            }
        }
    }

    private static func resolveAndDownload(link: MiraSocialVideoLink, destination: MiraSocialVideoDestination, quality: MiraSocialVideoQuality) {
        // Social links generally return an HTML landing page. Resolve only
        // explicit video metadata from that page; arbitrary page links are
        // discarded instead of being treated as downloadable media.
        var request = URLRequest(url: link.url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = Self.session.downloadTask(with: request) { location, response, _ in
            guard let response else {
                return
            }
            if Self.isVideoResponse(response) {
                guard let location else {
                    return
                }
                Self.store(location: location, response: response, destination: destination)
                return
            }
            guard let location,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: location.path),
                  let size = attributes[.size] as? NSNumber,
                  size.intValue <= 5 * 1024 * 1024,
                  let data = try? Data(contentsOf: location, options: [.mappedIfSafe]),
                  let html = String(data: data, encoding: .utf8),
                  let videoURL = Self.videoURL(in: html, baseURL: response.url ?? link.url, quality: quality) else {
                if let location {
                    try? FileManager.default.removeItem(at: location)
                }
                return
            }
            try? FileManager.default.removeItem(at: location)
            Self.download(url: videoURL, destination: destination)
        }
        task.resume()
    }

    private static func isVideoResponse(_ response: URLResponse) -> Bool {
        if response.mimeType?.hasPrefix("video/") == true {
            return true
        }
        if let pathExtension = response.url?.pathExtension.lowercased(),
           ["mp4", "m4v", "mov", "webm"].contains(pathExtension) {
            return true
        }
        guard let suggestedExtension = response.suggestedFilename?.split(separator: ".").last.map(String.init)?.lowercased() else {
            return false
        }
        return ["mp4", "m4v", "mov", "webm"].contains(suggestedExtension)
    }

    private static func download(url: URL, destination saveDestination: MiraSocialVideoDestination) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = Self.session.downloadTask(with: request) { location, response, _ in
            guard let location, let response, Self.isVideoResponse(response) else {
                if let location {
                    try? FileManager.default.removeItem(at: location)
                }
                return
            }
            Self.store(location: location, response: response, destination: saveDestination)
        }
        task.resume()
    }

    private static func store(location: URL, response: URLResponse, destination saveDestination: MiraSocialVideoDestination) {
        guard isVideoResponse(response) else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        let fileName = "stuxnet-\(UUID().uuidString).mp4"
        let directory: URL
        switch saveDestination {
        case .files:
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Social Videos", isDirectory: true)
        case .photos:
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationURL = directory.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: location, to: destinationURL)
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
        } catch {
            try? FileManager.default.removeItem(at: location)
        }
    }

    private static func videoURL(in html: String, baseURL: URL, quality: MiraSocialVideoQuality) -> URL? {
        let normalized = html
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        var candidates: [URL] = []

        // OpenGraph and Twitter stream tags cover the canonical public
        // metadata used by YouTube, Instagram and TikTok landing pages.
        let metadataPatterns = [
            #"<(?:meta)[^>]+(?:property|name)=[\"'](?:og:video(?::secure_url)?|twitter:player:stream)[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
            #"<(?:meta)[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"'](?:og:video(?::secure_url)?|twitter:player:stream)[\"']"#
        ]
        for pattern in metadataPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard match.numberOfRanges > 1,
                      let matchRange = Range(match.range(at: 1), in: normalized),
                      let url = Self.resolve(String(normalized[matchRange]), baseURL: baseURL) else {
                    continue
                }
                candidates.append(url)
            }
        }

        // Some providers expose the stream in JSON rather than a meta tag.
        // Restrict this fallback to URLs that look like video/CDN resources so
        // normal page links cannot accidentally be downloaded.
        if candidates.isEmpty,
           let regex = try? NSRegularExpression(pattern: #"https?://[^"'\s<>]+"#, options: [.caseInsensitive]) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let matchRange = Range(match.range, in: normalized) else {
                    continue
                }
                let raw = String(normalized[matchRange])
                guard raw.contains(".mp4") || raw.contains(".m3u8") || raw.contains("video") || raw.contains("cdn") else {
                    continue
                }
                if let url = Self.resolve(raw, baseURL: baseURL) {
                    candidates.append(url)
                }
            }
        }

        // Prefer URLs carrying an explicit quality marker when a provider
        // exposes several candidates. With a single source URL this remains a
        // transparent pass-through, since transcoding is outside the client.
        let marker: String?
        switch quality {
        case .source:
            marker = nil
        case .p720:
            marker = "720"
        case .p1080:
            marker = "1080"
        }
        if let marker,
           let matching = candidates.first(where: { $0.absoluteString.localizedCaseInsensitiveContains(marker) }) {
            return matching
        }
        return candidates.first
    }

    private static func resolve(_ value: String, baseURL: URL) -> URL? {
        let decoded = value
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003d", with: "=")
        if let absolute = URL(string: decoded), absolute.scheme != nil {
            return absolute
        }
        return URL(string: decoded, relativeTo: baseURL)?.absoluteURL
    }
}
