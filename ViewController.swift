import UIKit
import WebKit
import Network

class ViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    var webView: WKWebView!
    var proxyButton: UIButton!
    var isProxyActive = false
    var currentHost = ""
    var currentPort: UInt16 = 1080
    let targetURL = "https://hnproxy.io"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView(proxyHost: nil, proxyPort: nil, isSOCKS5: true)
        setupFloatingProxyButton()
    }

    func setupWebView(proxyHost: String?, proxyPort: UInt16?, isSOCKS5: Bool) {
        if webView != nil {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "hnProxyBridge")
            webView.removeFromSuperview()
        }

        // Jembatan jika website hnproxy.io ingin memanggil native proxy secara otomatis via JS
        let contentController = WKUserContentController()
        contentController.add(self, name: "hnProxyBridge")

        let dataStore = WKWebsiteDataStore.default()

        if let host = proxyHost, let port = proxyPort, !host.isEmpty, port > 0,
           let nwPort = NWEndpoint.Port(rawValue: port) {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
            let proxyConfig = isSOCKS5
                ? ProxyConfiguration(socksv5Proxy: endpoint)
                : ProxyConfiguration(httpCONNECTProxy: endpoint)

            dataStore.proxyConfigurations = [proxyConfig]
            isProxyActive = true
            currentHost = host
            currentPort = port
        } else {
            dataStore.proxyConfigurations = []
            isProxyActive = false
        }

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)

        if proxyButton != nil {
            view.bringSubviewToFront(proxyButton)
            updateButtonAppearance()
        }

        if let url = URL(string: targetURL) {
            webView.load(URLRequest(url: url))
        }
    }

    // Tombol melayang di pojok kanan bawah untuk menghidupkan/mematikan Proxy kapan saja
    func setupFloatingProxyButton() {
        proxyButton = UIButton(type: .system)
        proxyButton.frame = CGRect(x: view.bounds.width - 135, y: view.bounds.height - 95, width: 120, height: 44)
        proxyButton.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        proxyButton.layer.cornerRadius = 22
        proxyButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        proxyButton.setTitleColor(.white, for: .normal)
        proxyButton.addTarget(self, action: #selector(openProxyMenu), for: .touchUpInside)
        updateButtonAppearance()
        view.addSubview(proxyButton)
    }

    func updateButtonAppearance() {
        if isProxyActive {
            proxyButton.setTitle("Proxy: ON", for: .normal)
            proxyButton.backgroundColor = UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 0.9)
        } else {
            proxyButton.setTitle("Proxy: OFF", for: .normal)
            proxyButton.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 0.85)
        }
    }

    @objc func openProxyMenu() {
        let statusMsg = isProxyActive ? "Aktif (\(currentHost):\(currentPort))" : "Mati (Koneksi Langsung)"
        let alert = UIAlertController(title: "Pengaturan HNProxy", message: "Status: \(statusMsg)", preferredStyle: .alert)

        alert.addTextField { tf in
            tf.placeholder = "IP / Host Proxy (contoh: 103.150.10.1)"
            tf.text = self.currentHost
            tf.keyboardType = .URL
        }

        alert.addTextField { tf in
            tf.placeholder = "Port (contoh: 1080 atau 8080)"
            tf.text = "\(self.currentPort)"
            tf.keyboardType = .numberPad
        }

        alert.addAction(UIAlertAction(title: "Hidupkan (SOCKS5)", style: .default) { _ in
            let host = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let portStr = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1080"
            let port = UInt16(portStr) ?? 1080
            self.setupWebView(proxyHost: host, proxyPort: port, isSOCKS5: true)
        })

        alert.addAction(UIAlertAction(title: "Hidupkan (HTTP/HTTPS)", style: .default) { _ in
            let host = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let portStr = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "8080"
            let port = UInt16(portStr) ?? 8080
            self.setupWebView(proxyHost: host, proxyPort: port, isSOCKS5: false)
        })

        if isProxyActive {
            alert.addAction(UIAlertAction(title: "Matikan Proxy", style: .destructive) { _ in
                self.setupWebView(proxyHost: nil, proxyPort: nil, isSOCKS5: true)
            })
        }

        alert.addAction(UIAlertAction(title: "Muat Ulang hnproxy.io", style: .default) { _ in
            self.webView.reload()
        })

        alert.addAction(UIAlertAction(title: "Batal", style: .cancel))
        present(alert, animated: true)
    }

    // Jika di dalam kode website hnproxy.io Anda ingin memicu proxy otomatis lewat JavaScript:
    // window.webkit.messageHandlers.hnProxyBridge.postMessage({action: "start", host: "1.2.3.4", port: 1080, type: "socks5"})
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "hnProxyBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        if action == "start" {
            let host = body["host"] as? String ?? ""
            let portInt = body["port"] as? Int ?? 1080
            let type = body["type"] as? String ?? "socks5"
            setupWebView(proxyHost: host, proxyPort: UInt16(clamping: portInt), isSOCKS5: (type == "socks5"))
        } else if action == "stop" {
            setupWebView(proxyHost: nil, proxyPort: nil, isSOCKS5: true)
        }
    }
}
