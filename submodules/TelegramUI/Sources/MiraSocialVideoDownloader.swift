import Foundation
import Network
import Photos
import TelegramUIPreferences

/// Handles opt-in social-video downloads for links typed into a chat. The
/// resolver downloads to a temporary local file and can either hand that file
/// to the current chat or persist it using one of the legacy destinations.
public final class MiraSocialVideoDownloadHandle {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var progressTimer: DispatchSourceTimer?
    private var cancelled = false
    private var finished = false

    /// Cancels both the landing-page request and the resolved media request.
    /// Completion still fires once with a nil URL, which lets the caller close
    /// its progress UI without leaving an orphaned cache file.
    public func cancel() {
        self.lock.lock()
        self.cancelled = true
        let task = self.task
        let timer = self.progressTimer
        self.lock.unlock()
        task?.cancel()
        timer?.cancel()
    }

    fileprivate var isCancelled: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.cancelled
    }

    fileprivate func setTask(_ task: URLSessionDownloadTask) {
        self.lock.lock()
        self.task = task
        let cancelled = self.cancelled || self.finished
        self.lock.unlock()
        if cancelled {
            task.cancel()
        }
    }

    fileprivate func setProgressTimer(_ timer: DispatchSourceTimer) {
        self.lock.lock()
        self.progressTimer = timer
        let cancelled = self.cancelled || self.finished
        self.lock.unlock()
        if cancelled {
            timer.cancel()
        }
    }

    fileprivate func finish() {
        self.lock.lock()
        self.finished = true
        let timer = self.progressTimer
        self.progressTimer = nil
        self.task = nil
        self.lock.unlock()
        timer?.cancel()
    }
}

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
        // A chat upload needs a ChatController callback. This convenience API
        // has no chat context, so it only serves the explicit legacy export
        // destinations and never leaves an unreferenced cache file.
        guard settings.destination != .chat, !settings.confirmBeforeDownload else {
            return
        }
        Self.enqueue(links: links, settings: settings)
    }

    /// Removes stale completed chat downloads. The active upload owns its
    /// cache file for a short retry window; old files are safe to discard on
    /// the next social-link action.
    public static func cleanupCachedFiles(olderThan age: TimeInterval = 24.0 * 60.0 * 60.0) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stuxnet Social Videos", isDirectory: true)
        queue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                return
            }
            let cutoff = Date().addingTimeInterval(-age)
            for file in files {
                if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modified = values.contentModificationDate,
                   modified >= cutoff {
                    continue
                }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Resolves one link and returns a temporary video path suitable for a
    /// Telegram local media resource. The callback is always delivered on the
    /// main queue and the caller owns the returned file until upload finishes.
    @discardableResult
    public static func enqueue(link: MiraSocialVideoLink, settings: MiraSocialVideoSettings, completion: @escaping (URL?) -> Void) -> MiraSocialVideoDownloadHandle? {
        return self.enqueue(link: link, settings: settings, progress: nil, completion: completion)
    }

    /// Resolves one link while reporting best-effort byte progress. A social
    /// landing page may require two requests, so progress resets when the
    /// final CDN video starts; callers should treat it as a visual estimate.
    @discardableResult
    public static func enqueue(link: MiraSocialVideoLink, settings: MiraSocialVideoSettings, progress: ((Double) -> Void)?, completion: @escaping (URL?) -> Void) -> MiraSocialVideoDownloadHandle? {
        Self.cleanupCachedFiles()
        guard settings.enabled, settings.isEnabled(link.platform) else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        guard !settings.wifiOnly || (Self.pathMonitor.currentPath.status == .satisfied && Self.pathMonitor.currentPath.usesInterfaceType(.wifi)) else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        let handle = MiraSocialVideoDownloadHandle()
        Self.resolveAndDownload(link: link, destination: .chat, quality: settings.quality, handle: handle, progress: progress, completion: completion)
        return handle
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
                Self.resolveAndDownload(link: link, destination: settings.destination, quality: settings.quality, handle: MiraSocialVideoDownloadHandle(), progress: nil, completion: nil)
            }
        }
    }

    private static func resolveAndDownload(link: MiraSocialVideoLink, destination: MiraSocialVideoDestination, quality: MiraSocialVideoQuality, handle: MiraSocialVideoDownloadHandle, progress: ((Double) -> Void)?, completion: ((URL?) -> Void)?) {
        // Social links generally return an HTML landing page. Resolve only
        // explicit video metadata from that page; arbitrary page links are
        // discarded instead of being treated as downloadable media.
        var request = URLRequest(url: link.url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = Self.session.downloadTask(with: request) { location, response, _ in
            guard let response else {
                Self.finish(completion, value: nil, handle: handle)
                return
            }
            if Self.isVideoResponse(response) {
                guard let location else {
                    Self.finish(completion, value: nil, handle: handle)
                    return
                }
                Self.store(location: location, response: response, destination: destination, handle: handle, completion: completion)
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
                Self.finish(completion, value: nil, handle: handle)
                return
            }
            try? FileManager.default.removeItem(at: location)
            Self.download(url: videoURL, destination: destination, handle: handle, progress: progress, completion: completion)
        }
        handle.setTask(task)
        Self.monitorProgress(task, handle: handle, progress: progress)
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

    private static func download(url: URL, destination saveDestination: MiraSocialVideoDestination, handle: MiraSocialVideoDownloadHandle, progress: ((Double) -> Void)?, completion: ((URL?) -> Void)?) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = Self.session.downloadTask(with: request) { location, response, _ in
            guard let location, let response, Self.isVideoResponse(response) else {
                if let location {
                    try? FileManager.default.removeItem(at: location)
                }
                Self.finish(completion, value: nil, handle: handle)
                return
            }
            Self.store(location: location, response: response, destination: saveDestination, handle: handle, completion: completion)
        }
        handle.setTask(task)
        Self.monitorProgress(task, handle: handle, progress: progress)
        task.resume()
    }

    private static func store(location: URL, response: URLResponse, destination saveDestination: MiraSocialVideoDestination, handle: MiraSocialVideoDownloadHandle, completion: ((URL?) -> Void)?) {
        guard isVideoResponse(response) else {
            try? FileManager.default.removeItem(at: location)
            Self.finish(completion, value: nil, handle: handle)
            return
        }
        let fileName = "stuxnet-\(UUID().uuidString).mp4"
        if saveDestination == .chat {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Stuxnet Social Videos", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destinationURL = directory.appendingPathComponent(fileName)
                try FileManager.default.moveItem(at: location, to: destinationURL)
                Self.finish(completion, value: destinationURL, handle: handle)
            } catch {
                try? FileManager.default.removeItem(at: location)
                Self.finish(completion, value: nil, handle: handle)
            }
            return
        }
        let directory: URL
        switch saveDestination {
        case .chat:
            // Handled above; this branch keeps the enum switch exhaustive if
            // the destination is extended by a caller in the future.
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
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
            Self.finish(completion, value: nil, handle: handle)
            guard saveDestination == .photos else {
                return
            }
            PHPhotoLibrary.requestAuthorization { status in
                let canSaveToPhotos: Bool
                if #available(iOS 14.0, *) {
                    canSaveToPhotos = status == .authorized || status == .limited
                } else {
                    canSaveToPhotos = status == .authorized
                }
                guard canSaveToPhotos else {
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: location)
            Self.finish(completion, value: nil, handle: handle)
        }
    }

    private static func monitorProgress(_ task: URLSessionDownloadTask, handle: MiraSocialVideoDownloadHandle, progress: ((Double) -> Void)?) {
        guard let progress else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: Self.queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(120))
        timer.setEventHandler { [weak task, weak handle] in
            guard let task, let handle, !handle.isCancelled else {
                timer.cancel()
                return
            }
            let value = task.progress.fractionCompleted
            DispatchQueue.main.async {
                progress(min(1.0, max(0.0, value)))
            }
        }
        handle.setProgressTimer(timer)
        timer.resume()
    }

    private static func finish(_ completion: ((URL?) -> Void)?, value: URL?, handle: MiraSocialVideoDownloadHandle) {
        handle.finish()
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(value)
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
