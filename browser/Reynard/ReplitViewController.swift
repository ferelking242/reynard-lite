import GeckoView
import UIKit

final class ReplitViewController: UIViewController {

    // MARK: - Config

    private enum Config {
        static let replitURL = "https://replit.com"

        // Mobile Safari UA — matches what Replit expects on iPhone
        static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        // 30 s is sufficient to prevent Gecko's child process from being
        // suspended while backgrounded, and burns less CPU/battery than 20 s.
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

    /// Called by iOS when memory pressure is high (common on 2 GB devices).
    /// Dropping the URL cache frees tens of MB instantly without affecting
    /// the active Gecko session or any in-flight network requests.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
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
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        return .allow
    }
}

// MARK: - ProgressDelegate

extension ReplitViewController: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorView.isHidden = true
        }
    }
}

// MARK: - ContentDelegate

extension ReplitViewController: ContentDelegate {
    /// Auto-reload after a content-process crash.
    /// On a 2 GB device an OOM kill can happen mid-session; reloading
    /// automatically keeps the user in Replit without manual intervention.
    func onCrash(session: GeckoSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadReplit()
        }
    }

    /// Same recovery path as `onCrash` but triggered by an OS-level kill.
    func onKill(session: GeckoSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadReplit()
        }
    }
}

// MARK: - PromptDelegate

extension ReplitViewController: PromptDelegate {
    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? {
        return nil
    }
}

// MARK: - PermissionEmbedderDelegate

extension ReplitViewController: PermissionEmbedderDelegate {
    func permissionDelegate(decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
        return .allow
    }

    func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
        return true
    }
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
