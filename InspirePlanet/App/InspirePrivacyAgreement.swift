import SwiftUI
import UIKit
import WebKit

@MainActor
final class InspirePrivacyGate: ObservableObject {
    static let acceptedKey = "inspireplanet.privacy.agreement.accepted"

    @Published private(set) var hasAccepted: Bool

    init(defaults: UserDefaults = .standard) {
        hasAccepted = defaults.bool(forKey: Self.acceptedKey)
    }

    func accept() {
        UserDefaults.standard.set(true, forKey: Self.acceptedKey)
        hasAccepted = true
    }
}

struct InspirePrivacyAgreementView: UIViewControllerRepresentable {
    let onAgree: () -> Void

    func makeUIViewController(context: Context) -> InspireAgreementViewController {
        let controller = InspireAgreementViewController()
        controller.onAgree = onAgree
        return controller
    }

    func updateUIViewController(_ uiViewController: InspireAgreementViewController, context: Context) {}
}

final class InspireAgreementViewController: UIViewController, UITextViewDelegate {
    var onAgree: (() -> Void)?

    private let cardView = UIView()
    private let checkBoxButton = UIButton(type: .system)
    private let textView = UITextView()
    private var isChecked = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        setupCard()
    }

    private func setupCard() {
        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 16
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.75)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "个人信息保护提示"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.font = .systemFont(ofSize: 13)
        textView.dataDetectorTypes = []
        textView.delegate = self
        textView.attributedText = Self.buildAttributedSummary()
        textView.linkTextAttributes = [.foregroundColor: UIColor.systemBlue]

        checkBoxButton.setImage(UIImage(systemName: "square"), for: .normal)
        checkBoxButton.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
        checkBoxButton.tintColor = .systemBlue
        checkBoxButton.addTarget(self, action: #selector(toggleCheck), for: .touchUpInside)
        checkBoxButton.translatesAutoresizingMaskIntoConstraints = false

        let checkLabel = UILabel()
        checkLabel.text = "我已阅读并同意《用户协议》和《隐私政策》"
        checkLabel.font = .systemFont(ofSize: 12)
        checkLabel.textColor = .secondaryLabel
        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkLabel.isUserInteractionEnabled = true
        checkLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleCheck)))

        let checkRow = UIStackView(arrangedSubviews: [checkBoxButton, checkLabel])
        checkRow.axis = .horizontal
        checkRow.spacing = 6
        checkRow.alignment = .center
        checkRow.translatesAutoresizingMaskIntoConstraints = false

        let agreeButton = UIButton(type: .system)
        agreeButton.setTitle("同意并继续", for: .normal)
        agreeButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        agreeButton.setTitleColor(.white, for: .normal)
        agreeButton.backgroundColor = .black
        agreeButton.layer.cornerRadius = 8
        agreeButton.addTarget(self, action: #selector(tapAgree), for: .touchUpInside)
        agreeButton.translatesAutoresizingMaskIntoConstraints = false

        let disagreeButton = UIButton(type: .system)
        disagreeButton.setTitle("不同意", for: .normal)
        disagreeButton.titleLabel?.font = .systemFont(ofSize: 14)
        disagreeButton.setTitleColor(.secondaryLabel, for: .normal)
        disagreeButton.addTarget(self, action: #selector(tapDisagree), for: .touchUpInside)
        disagreeButton.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, textView, checkRow, agreeButton, disagreeButton].forEach(cardView.addSubview)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            checkRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            checkRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            checkRow.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
            checkBoxButton.widthAnchor.constraint(equalToConstant: 22),
            checkBoxButton.heightAnchor.constraint(equalToConstant: 22),
            agreeButton.topAnchor.constraint(equalTo: checkRow.bottomAnchor, constant: 16),
            agreeButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            agreeButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            agreeButton.heightAnchor.constraint(equalToConstant: 46),
            disagreeButton.topAnchor.constraint(equalTo: agreeButton.bottomAnchor, constant: 8),
            disagreeButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            disagreeButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    private static func buildAttributedSummary() -> NSAttributedString {
        let text = """
        欢迎使用灵感星球！

        AI 模型服务由智谱大模型提供。我们倡导用户遵守相关法律法规及政策，不得使用本服务从事违法违规活动。

        模型名称：智谱大模型 GLM-4.5
        授权模型：GLM-4.5
        授权编号：202606091295564742

        我们将通过《用户协议》和《隐私政策》，帮助您了解我们为您提供的服务、我们如何处理个人信息以及您享有的权利。

        灵感星球主要提供 AI 数字人文字与语音对话服务。为实现这些功能，在您同意后我们可能处理以下信息：

        1、麦克风与语音内容，用于语音识别和数字人对话；
        2、设备信息（设备型号、系统版本、网络类型及设备标识信息），用于保障服务安全、统计使用情况并改善产品体验；
        3、您主动提交的账号信息和对话内容，用于提供登录及 AI 对话服务。

        为便于您清晰理解，我们特别向您明示：
        1、处理目的：实现文字与语音对话、账号服务、运行分析及故障诊断；
        2、处理方式：仅在您点击同意后初始化数字人及友盟+统计 SDK，并在实现服务所必需的范围内处理信息；
        3、您可以在《隐私政策》中了解第三方 SDK、个人信息处理规则及您的权利。

        点击同意即代表您已阅读并同意《用户协议》及《隐私政策》相关内容。
        """
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttributes([
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: attributed.length))
        for (name, link) in [("用户协议", "agreement://user"), ("隐私政策", "agreement://privacy")] {
            var searchRange = NSRange(location: 0, length: attributed.length)
            while searchRange.length > 0 {
                let range = (text as NSString).range(of: name, options: [], range: searchRange)
                guard range.location != NSNotFound else { break }
                attributed.addAttribute(.link, value: link, range: range)
                let next = NSMaxRange(range)
                searchRange = NSRange(location: next, length: attributed.length - next)
            }
        }
        return attributed
    }

    @objc private func toggleCheck() {
        isChecked.toggle()
        checkBoxButton.isSelected = isChecked
    }

    @objc private func tapAgree() {
        guard isChecked else {
            let alert = UIAlertController(title: nil, message: "请先阅读并勾选同意《用户协议》和《隐私政策》", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        onAgree?()
    }

    @objc private func tapDisagree() {
        let alert = UIAlertController(
            title: "提示",
            message: "您需要同意《用户协议》和《隐私政策》后才能使用灵感星球。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "查看协议", style: .default))
        alert.addAction(UIAlertAction(title: "退出App", style: .destructive) { _ in exit(0) })
        present(alert, animated: true)
    }

    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let title: String
        let remoteURL: URL
        switch url.absoluteString {
        case "agreement://user":
            title = "用户协议"
            remoteURL = URL(string: "https://www.cjym123.cn/agreement_inspireplanet.html")!
        case "agreement://privacy":
            title = "隐私政策"
            remoteURL = URL(string: "https://www.cjym123.cn/privacy_inspireplanet.html")!
        default:
            return false
        }
        let controller = InspirePrivacyWebViewController(title: title, url: remoteURL)
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissLegalDocument)
        )
        present(navigation, animated: true)
        return false
    }

    @objc private func dismissLegalDocument() {
        presentedViewController?.dismiss(animated: true)
    }
}

private final class InspirePrivacyWebViewController: UIViewController {
    private let remoteURL: URL

    init(title: String, url: URL) {
        remoteURL = url
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: remoteURL, cachePolicy: .reloadRevalidatingCacheData))
        view = webView
    }
}

#if canImport(UMCommon)
import UMCommon
#endif

final class InspireUMengAnalytics {
    static let shared = InspireUMengAnalytics()

    private let appKey = "6a6f142ee87a8d65f0a49a57"
    private let channel = "App Store"
    private var isInitialized = false

    private init() {}

    func initializeIfAllowed() {
        guard UserDefaults.standard.bool(forKey: InspirePrivacyGate.acceptedKey), !isInitialized else { return }
        #if canImport(UMCommon)
        UMConfigure.initWithAppkey(appKey, channel: channel)
        #if DEBUG
        UMConfigure.setLogEnabled(true)
        #else
        UMConfigure.setLogEnabled(false)
        #endif
        isInitialized = true
        #if DEBUG
        print("友盟统计初始化成功")
        #endif
        #else
        #if DEBUG
        print("友盟统计 SDK 未安装")
        #endif
        #endif
    }
}
