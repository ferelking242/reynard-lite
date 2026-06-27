import GeckoView
  import UIKit

  final class ReplitViewController: UIViewController {

      // MARK: - Config

      private enum Config {
          static let replitURL = "https://replit.com"
          static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
          static let keepAliveInterval: TimeInterval = 20
      }

      // MARK: - Gecko

      private let session = GeckoSession(
          settings: GeckoSessionSettings(
              userAgentOverride: Config.userAgent,
              userAgentMode: 1,
              viewportMode: 1
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
          backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
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
      func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {}
      func onCanGoBack(session: GeckoSession, canGoBack: Bool) {}
      func onCanGoForward(session: GeckoSession, canGoForward: Bool) {}
      func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
      func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
      func onNewSession(session: GeckoSession, uri: String, windowId: String) async -> GeckoSession? { nil }
  }

  // MARK: - ProgressDelegate

  extension ReplitViewController: ProgressDelegate {
      func onPageStart(session: GeckoSession, url: String) {}
      func onProgressChange(session: GeckoSession, progress: Int) {}
      func onPageStop(session: GeckoSession, success: Bool) {
          DispatchQueue.main.async {
              if !success { self.errorView.isHidden = false }
          }
      }
  }

  // MARK: - ContentDelegate

  extension ReplitViewController: ContentDelegate {
      func onCrash(session: GeckoSession) {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              self.session.close()
              self.session.open()
              self.geckoView.session = self.session
              self.loadReplit()
          }
      }

      func onKill(session: GeckoSession) {
          onCrash(session: session)
      }
  }

  // MARK: - PromptDelegate

  extension ReplitViewController: PromptDelegate {

      @MainActor
      func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? {
          switch request {

          case .alert(let r):
              return await withCheckedContinuation { cont in
                  let alert = UIAlertController(title: r.title, message: r.message, preferredStyle: .alert)
                  alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in cont.resume(returning: .button(0)) })
                  present(alert, animated: true)
              }

          case .button(let r):
              let titles = r.customButtonTitles.isEmpty ? r.buttonTitles : r.customButtonTitles
              return await withCheckedContinuation { cont in
                  let alert = UIAlertController(title: r.title, message: r.message, preferredStyle: .alert)
                  for (i, title) in titles.enumerated() {
                      let style: UIAlertAction.Style = i == 0 ? .default : (i == titles.count - 1 ? .cancel : .default)
                      alert.addAction(UIAlertAction(title: title, style: style) { _ in cont.resume(returning: .button(i)) })
                  }
                  present(alert, animated: true)
              }

          case .text(let r):
              return await withCheckedContinuation { cont in
                  let alert = UIAlertController(title: r.title, message: r.message, preferredStyle: .alert)
                  alert.addTextField { $0.text = r.value }
                  alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in cont.resume(returning: nil) })
                  alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                      cont.resume(returning: .text(alert.textFields?.first?.text ?? ""))
                  })
                  present(alert, animated: true)
              }

          default:
              return nil
          }
      }

      @MainActor func onPromptUpdate(session: GeckoSession, request: PromptRequest) {}
      @MainActor func onPromptDismiss(session: GeckoSession, promptId: String) {}
  }

  // MARK: - PermissionEmbedderDelegate

  extension ReplitViewController: PermissionEmbedderDelegate {

      @MainActor
      func permissionDelegate(decideContentPermission permission: ContentPermission, session: GeckoSession) async -> ContentPermission.Value {
          .allow
      }

      @MainActor
      func permissionDelegate(decideMediaPermission request: MediaPermissionRequest, session: GeckoSession) async -> Bool {
          return await withCheckedContinuation { cont in
              let parts = [request.videoRequested ? "camera" : nil, request.audioRequested ? "microphone" : nil]
                  .compactMap { $0 }
              let name = parts.joined(separator: " & ")
              let alert = UIAlertController(
                  title: name.capitalized,
                  message: "\(request.host) wants to use your \(name).",
                  preferredStyle: .alert
              )
              alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { _ in cont.resume(returning: false) })
              alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in cont.resume(returning: true) })
              present(alert, animated: true)
          }
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
  