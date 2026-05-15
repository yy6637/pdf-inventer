import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - App Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Node.js Locator

func findNode() -> String? {
    let candidates = [
        "/opt/homebrew/bin/node",
        "/opt/homebrew/local/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
    ]
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    // Try locating via `which` with a broader PATH
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = ["node"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/local/bin:/usr/bin:/bin"
    task.environment = env
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return path
        }
    } catch {}
    return nil
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var serverProcess: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        startServer()

        // Poll for server readiness, then load
        pollServer(retries: 30, interval: 0.5) { [weak self] in
            self?.loadWebApp()
        }
    }

    // MARK: - Window

    func createWindow() {
        let rect = NSRect(x: 0, y: 0, width: 1280, height: 860)

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PDF 图片反转工具"
        window.minSize = NSSize(width: 800, height: 600)
        window.isOpaque = false
        window.backgroundColor = NSColor(red: 0.027, green: 0.051, blue: 0.102, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.center()

        let config = WKWebViewConfiguration()
        let handler = BridgeHandler()
        config.userContentController.add(handler, name: "nativeBridge")

        // Inject bridge JS before any page loads
        let bridgeJS = WKUserScript(source: BridgeHandler.jsBridge, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(bridgeJS)

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)

        // Menu bar
        let menuBar = NSMenu()
        let appMenu = NSMenuItem(title: "应用", action: nil, keyEquivalent: "")
        let appSub = NSMenu(title: "应用")
        appSub.addItem(NSMenuItem(title: "关于 PDF 图片反转工具", action: nil, keyEquivalent: ""))
        appSub.addItem(NSMenuItem.separator())
        appSub.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenu.submenu = appSub
        menuBar.addItem(appMenu)
        NSApp.mainMenu = menuBar

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Server Management

    func startServer() {
        let projectDir = projectDirectory()
        let mainJS = (projectDir as NSString).appendingPathComponent("main.js")
        guard FileManager.default.fileExists(atPath: mainJS) else {
            print("[PDFInverter] main.js not found at: \(mainJS)")
            return
        }

        guard let nodePath = findNode() else {
            print("[PDFInverter] Node.js not found. Please install Node.js")
            return
        }

        serverProcess = Process()
        serverProcess?.executableURL = URL(fileURLWithPath: nodePath)
        serverProcess?.arguments = [mainJS, "--server-only"]
        serverProcess?.currentDirectoryURL = URL(fileURLWithPath: projectDir)

        // Ensure PATH is set for any subprocesses that might need it
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        serverProcess?.environment = env

        let outPipe = Pipe()
        serverProcess?.standardOutput = outPipe
        serverProcess?.standardError = outPipe

        do {
            try serverProcess?.run()
            print("[PDFInverter] Server process started")
        } catch {
            print("[PDFInverter] Failed to start server: \(error)")
        }
    }

    func projectDirectory() -> String {
        // If running inside a .app bundle, try bundle's parent & grandparent
        if Bundle.main.bundlePath.contains(".app") {
            var d = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
            for _ in 0..<3 {
                if FileManager.default.fileExists(atPath: (d as NSString).appendingPathComponent("main.js")) {
                    return d
                }
                d = (d as NSString).deletingLastPathComponent
            }
        }
        // Walk up from binary location to find project root
        var dir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("main.js")) {
                return dir
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return FileManager.default.currentDirectoryPath
    }

    func loadWebApp() {
        let url = URL(string: "http://localhost:3456")!
        webView.load(URLRequest(url: url))
    }

    func pollServer(retries: Int, interval: TimeInterval, done: @escaping () -> Void) {
        let url = URL(string: "http://localhost:3456")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] _, response, error in
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                DispatchQueue.main.async { done() }
            } else if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    self?.pollServer(retries: retries - 1, interval: interval, done: done)
                }
            } else {
                print("[PDFInverter] Server not ready after polling")
            }
        }
        task.resume()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        serverProcess?.terminate()
        serverProcess?.waitUntilExit()
    }
}

// MARK: - Native Bridge

class BridgeHandler: NSObject, WKScriptMessageHandler {
    /// JavaScript bridge injected at document start
    static let jsBridge = """
    window.__nativeCallbacks = {};
    window.__nativeId = 0;
    window.callNative = function(method, args = {}) {
        return new Promise(function(resolve, reject) {
            var id = ++window.__nativeId;
            window.__nativeCallbacks[id] = { resolve: resolve, reject: reject };
            args.method = method;
            args.id = id;
            try {
                window.webkit.messageHandlers.nativeBridge.postMessage(args);
            } catch(e) {
                delete window.__nativeCallbacks[id];
                reject(e);
            }
        });
    };
    window.__nativeCallback = function(json) {
        var data = JSON.parse(json);
        var cb = window.__nativeCallbacks[data.id];
        if (!cb) return;
        delete window.__nativeCallbacks[data.id];
        if (data.error) {
            var err = new Error(data.error);
            err.code = data.code || 'NATIVE_ERROR';
            cb.reject(err);
        } else {
            cb.resolve(data.result);
        }
    };
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nativeBridge",
              let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let id = body["id"] as? UInt else { return }

        switch method {
        case "selectFolder":
            selectFolder(id: id)
        case "saveImagesToFolder":
            saveImagesToFolder(id: id, body: body)
        case "downloadSingleImage":
            downloadSingleImage(id: id, body: body)
        case "savePDF":
            savePDF(id: id, body: body)
        default:
            sendError(id: id, message: "Unknown method: \(method)")
        }
    }

    // MARK: - Native Operations

    func selectFolder(id: UInt) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "选择保存文件夹"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    self.sendResult(id: id, result: url.path)
                } else {
                    self.sendError(id: id, message: "cancelled", code: "CANCELLED")
                }
            }
        }
    }

    func saveImagesToFolder(id: UInt, body: [String: Any]) {
        guard let dirPath = body["dirPath"] as? String,
              let items = body["items"] as? [[String: Any]] else {
            sendError(id: id, message: "Invalid arguments")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var saved = 0
            for item in items {
                guard let name = item["name"] as? String,
                      let dataUrl = item["dataUrl"] as? String else { continue }

                let safeName = name.replacingOccurrences(of: "[<>:\"/\\\\|?*]", with: "_", options: .regularExpression)
                let ext = dataUrl.hasPrefix("data:application/pdf") ? ".pdf" : ".png"
                let filePath = (dirPath as NSString).appendingPathComponent(safeName + ext)

                if let data = self.dataFromDataURL(dataUrl) {
                    do {
                        try data.write(to: URL(fileURLWithPath: filePath))
                        saved += 1
                    } catch {
                        print("[PDFInverter] Write error: \(error)")
                    }
                }
            }
            self.sendResult(id: id, result: ["success": true, "count": saved])
        }
    }

    func downloadSingleImage(id: UInt, body: [String: Any]) {
        guard let name = body["name"] as? String,
              let dataUrl = body["dataUrl"] as? String else {
            sendError(id: id, message: "Invalid arguments")
            return
        }

        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "保存图片"
            panel.nameFieldStringValue = name.replacingOccurrences(of: "[<>:\"/\\\\|?*]", with: "_", options: .regularExpression) + ".png"
            panel.allowedContentTypes = [.png]

            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    self.sendError(id: id, message: "cancelled", code: "CANCELLED")
                    return
                }

                if let data = self.dataFromDataURL(dataUrl) {
                    do {
                        try data.write(to: url)
                        self.sendResult(id: id, result: ["success": true, "path": url.path])
                    } catch {
                        self.sendError(id: id, message: error.localizedDescription)
                    }
                } else {
                    self.sendError(id: id, message: "Failed to decode image data")
                }
            }
        }
    }

    func savePDF(id: UInt, body: [String: Any]) {
        guard let fileName = body["fileName"] as? String,
              let dataUrl = body["dataUrl"] as? String else {
            sendError(id: id, message: "Invalid arguments")
            return
        }

        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "保存 PDF"
            panel.nameFieldStringValue = fileName.replacingOccurrences(of: "[<>:\"/\\\\|?*]", with: "_", options: .regularExpression)
            panel.allowedContentTypes = [.pdf]

            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    self.sendError(id: id, message: "cancelled", code: "CANCELLED")
                    return
                }

                if let data = self.dataFromDataURL(dataUrl) {
                    do {
                        try data.write(to: url)
                        self.sendResult(id: id, result: ["success": true, "path": url.path])
                    } catch {
                        self.sendError(id: id, message: error.localizedDescription)
                    }
                } else {
                    self.sendError(id: id, message: "Failed to decode PDF data")
                }
            }
        }
    }

    // MARK: - Helpers

    func dataFromDataURL(_ dataUrl: String) -> Data? {
        guard let commaRange = dataUrl.range(of: ",") else { return nil }
        let base64 = String(dataUrl[commaRange.upperBound...])
        return Data(base64Encoded: base64)
    }

    func sendResult(id: UInt, result: Any) {
        let payload: [String: Any] = ["id": Int(id), "result": result]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__nativeCallback('\(escaped)')"
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.webView.evaluateJavaScript(js)
        }
    }

    func sendError(id: UInt, message: String, code: String = "NATIVE_ERROR") {
        let payload: [String: Any] = ["id": Int(id), "error": message, "code": code]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        let escaped = json
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__nativeCallback('\(escaped)')"
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.webView.evaluateJavaScript(js)
        }
    }
}
