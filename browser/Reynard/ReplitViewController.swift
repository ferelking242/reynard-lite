import GeckoView
import UIKit

final class ReplitViewController: UIViewController {

    // MARK: - Config

    private enum Config {
        static let replitURL = "https://replit.com"

        // Mobile Safari UA – matches what Replit expects on iPhone
        static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        // Keep-alive fires only while the app is backgrounded; 30 s is plenty
        // to prevent Gecko's child process from being suspended prematurely,
        // while still spending less CPU/battery than the original 20 s interval.
        static let keepAliveInterval: TimeInterval = 30
    }

    // MARK: - Gecko

    private let session = GeckoSession(
        settings: GeckoSessionSettings(
            userAgentOverride: Config.userAgent,
            userAgentMode: 1,   // Mobile UA mode
            viewportMode: 1     // Mobile viewport
        )
    )

    // MARK: - Views

    private lazy var geckoView: GeckoView = {
        let v = GeckoView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var errorView: ReplitErrorView = {
        let v = ReplitErrorView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onRetry = { [weak self] in self?.loadReplit() }
        return v
    }()

    // MARK: - Keep-Alive

    private var keepAliveTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        setupGecko()
        setupLayout()
        loadReplit()
    }

    /// Release Gecko caches when iOS signals memory pressure.
    /// On a 2 GB device (iPhone 7) this can be the difference between the tab
    /// process surviving and being OOM-killed mid-session.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        session.purgeHistory(keepFirst: true)
        NSURLCache.shared.removeAllCachedResponses()
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupGecko() {
        session.open()
        geckoView.session = session
        session.navigationDelegate = self
        session.progressDelegate = self
        session.contentDelegate = self
        session.promptDelegate = self
        session.permissionDelegate = self
    }

    private func setupLayout() {
        view.addSubview(geckoView)
        view.addSubview(errorView)

        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: view.topAnchor),
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Navigation

    func loadReplit() {
        errorView.isHidden = true
        session.load(Config.replitURL)
    }

    // MARK: - Background Handling

    func handleBackground() {
        session.setActive(false)
        session.setFocused(false)
        startBackgroundTask()
        startKeepAlive()
    }

    func handleForeground() {
        stopKeepAlive()
        endBackgroundTask()
        session.setActive(true)
        session.setFocused(true)
    }

    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(
            withTimeInterval: Config.keepAliveInterval,
            repeats: true
        ) { [weak self] _ in
            self?.session.setActive(true)
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ReplitSession") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

// MARK: - NavigationDelegate

extension ReplitViewController: NavigationDelegate {
    func onLoadRequest(_ session: GeckoSession, request: NavigationDelegate.LoadRequest) -> AllowOrDeny {
        return .allow
    }

    func onLocationChange(_ session: GeckoSession, url: String?, perms: [ContentPermission], hasUserGesture: Bool) {}
    func onCanGoBack(_ session: GeckoSession, canGoBack: Bool) {}
    func onCanGoForward(_ session: GeckoSession, canGoForward: Bool) {}
    func onLoadError(_ session: GeckoSession, url: String?, error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorView.isHidden = false
        }
    }
}

// MARK: - ProgressDelegate

extension ReplitViewController: ProgressDelegate {
    func onPageStart(_ session: GeckoSession, url: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorView.isHidden = true
        }
    }

    func onPageStop(_ session: GeckoSession, success: Bool) {}
    func onProgressChange(_ session: GeckoSession, progress: Int) {}
    func onSessionStateChange(_ session: GeckoSession, sessionState: String) {}
    func onSecurityChange(_ session: GeckoSession, securityInfo: ProgressDelegate.SecurityInformation) {}
}

// MARK: - ContentDelegate

extension ReplitViewController: ContentDelegate {
    func onTitleChange(_ session: GeckoSession, title: String?) {}
    func onFullScreen(_ session: GeckoSession, fullScreen: Bool) {}
    func onContextMenu(_ session: GeckoSession, screenX: Int, screenY: Int, element: ContentDelegate.ContextElement) {}
    func onCrash(_ session: GeckoSession, isKilled: Bool) {
        // Reload after crash/OOM kill – common on 2 GB devices
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadReplit()
        }
    }
    func onKillProcess(_ session: GeckoSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadReplit()
        }
    }
    func onFirstComposite(_ session: GeckoSession) {}
    func onWebAppManifest(_ session: GeckoSession, manifest: [String: Any]) {}
    func onFocusRequest(_ session: GeckoSession) {}
    func onCloseRequest(_ session: GeckoSession) {}
}

// MARK: - PromptDelegate

extension ReplitViewController: PromptDelegate {
    func onAlertPrompt(_ session: GeckoSession, request: AlertPromptRequest) async -> PromptResponse { request.dismiss() }
    func onButtonPrompt(_ session: GeckoSession, request: ButtonPromptRequest) async -> PromptResponse { request.confirm(button: .negative) }
    func onTextPrompt(_ session: GeckoSession, request: TextPromptRequest) async -> PromptResponse { request.dismiss() }
    func onAuthPrompt(_ session: GeckoSession, request: PromptRequest) async -> PromptResponse { request.dismiss() }
    func onColorPrompt(_ session: GeckoSession, request: ColorPromptRequest) async -> PromptResponse { request.dismiss() }
    func onDateTimePrompt(_ session: GeckoSession, request: DateTimePromptRequest) async -> PromptResponse { request.dismiss() }
    func onFilePrompt(_ session: GeckoSession, request: FilePickerPromptRequest) async -> PromptResponse { request.dismiss() }
    func onFolderUploadPrompt(_ session: GeckoSession, request: FolderUploadPromptRequest) async -> PromptResponse { request.dismiss() }
    func onSelectPrompt(_ session: GeckoSession, request: SelectPromptRequest) async -> PromptResponse { request.dismiss() }
    func onBeforeUnloadPrompt(_ session: GeckoSession, request: PromptRequest) async -> PromptResponse { request.dismiss() }
    func onLoginSelect(_ session: GeckoSession, request: PromptRequest) async -> PromptResponse { request.dismiss() }
    func onLoginSave(_ session: GeckoSession, request: PromptRequest) async -> PromptResponse { request.dismiss() }
    func onSharePrompt(_ session: GeckoSession, request: PromptRequest) async -> PromptResponse { request.dismiss() }
}

// MARK: - PermissionDelegate

extension ReplitViewController: PermissionEmbedderDelegate {
    func onContentPermissionRequest(_ session: GeckoSession, request: ContentPermissionRequest) async -> AllowOrDeny { .allow }
}

// MARK: - Error View

private final class ReplitErrorView: UIView {
    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "wifi.slash"))
        icon.tintColor = UIColor(white: 0.4, alpha: 1)
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let label = UILabel()
        label.text = "Connection lost"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor(white: 0.5, alpha: 1)

        let btn = UIButton(type: .system)
        btn.setTitle("Try again", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(btn)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func retryTapped() { onRetry?() }
}
