import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

final class MiraScreenCaptureGuard {
    private let getWindow: () -> UIWindow?
    private let disposable = MetaDisposable()

    private var currentSettings: MiraSettings = .defaultSettings
    private var overlayColor: UIColor = .black
    private var overlayIconColor: UIColor = .gray
    private var overlayView: UIView?

    init(accountManager: AccountManager<TelegramAccountManagerTypes>, presentationData: Signal<PresentationData, NoError>, getWindow: @escaping () -> UIWindow?) {
        self.getWindow = getWindow

        self.disposable.set((combineLatest(miraSettingsSignal(accountManager: accountManager), presentationData)
        |> deliverOnMainQueue).start(next: { [weak self] settings, presentationData in
            guard let self else {
                return
            }
            self.currentSettings = settings
            self.overlayColor = presentationData.theme.chatList.backgroundColor
            self.overlayIconColor = presentationData.theme.chatList.messageTextColor
            self.updateOverlay()
        }))

        NotificationCenter.default.addObserver(self, selector: #selector(self.capturedDidChange), name: UIScreen.capturedDidChangeNotification, object: nil)
        self.updateOverlay()
    }

    deinit {
        self.disposable.dispose()
        NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
    }

    @objc private func capturedDidChange() {
        self.updateOverlay()
    }

    private func updateOverlay() {
        let isActive = UIScreen.main.isCaptured && (self.currentSettings.streamerMode || self.currentSettings.screenshotEvasion)
        if isActive {
            if self.overlayView == nil, let window = self.getWindow() {
                let overlayView = UIView(frame: window.bounds)
                overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                overlayView.isUserInteractionEnabled = false
                if #available(iOS 13.0, *) {
                    let iconSize: CGFloat = 96.0
                    let imageView = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
                    imageView.contentMode = .scaleAspectFit
                    imageView.tintColor = self.overlayIconColor
                    imageView.frame = CGRect(x: floor((overlayView.bounds.width - iconSize) / 2.0), y: floor((overlayView.bounds.height - iconSize) / 2.0), width: iconSize, height: iconSize)
                    imageView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
                    overlayView.addSubview(imageView)
                }
                window.addSubview(overlayView)
                self.overlayView = overlayView
            }
            self.overlayView?.backgroundColor = self.overlayColor
        } else if let overlayView = self.overlayView {
            overlayView.removeFromSuperview()
            self.overlayView = nil
        }
    }
}
