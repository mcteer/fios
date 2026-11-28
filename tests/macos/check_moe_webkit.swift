import AppKit
import Foundation
import WebKit

struct Request: Decodable {
    let candidate: String
    let suite: String
    let `case`: String
    let prompt: String
}

final class Rehearsal: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let window: NSWindow
    let request: Request
    var start: UInt64?

    init(_ request: Request) {
        self.request = request
        let frame = NSRect(x: 0, y: 0, width: 960, height: 760)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: frame, configuration: config)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.contentView = web
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForModel()
    }

    func waitForModel() {
        let script = """
        const model = document.getElementById("alias");
        const option = model?.querySelector('option[value="large-moe"]');
        if (!option || option.disabled) return false;
        model.value = option.value;
        model.dispatchEvent(new Event("change"));
        return !document.getElementById("send").disabled;
        """
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure: self.fail("Could not select the large model.")
            case .success(let value):
                guard value as? Bool == true else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.waitForModel() }
                    return
                }
                self.submit()
            }
        }
    }

    func submit() {
        let script = """
        document.getElementById("prompt").value = fixture;
        document.getElementById("composer").requestSubmit();
        return true;
        """
        start = DispatchTime.now().uptimeNanoseconds
        web.callAsyncJavaScript(script, arguments: ["fixture": request.prompt], in: nil, in: .page) { result in
            switch result {
            case .failure: self.fail("Could not submit the fixture.")
            case .success: self.waitForAnswer()
            }
        }
    }

    func waitForAnswer() {
        let script = """
        const answers = Array.from(document.querySelectorAll('#thread article[data-publication="approved"]'));
        const answer = answers.find(item => item.getClientRects().length > 0
          && getComputedStyle(item).visibility === "visible"
          && item.querySelector("pre")?.textContent?.trim());
        if (answer) return {job: answer.dataset.job};
        const state = document.getElementById("status").textContent;
        if (/^(Withheld|Interrupted|Stopped|Expired)/.test(state)) return {failed: true};
        return {};
        """
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure: self.fail("Could not inspect the rendered fixture.")
            case .success(let value):
                let data = value as? [String: Any]
                if data?["failed"] as? Bool == true { self.fail("The fixture turn failed.") }
                if let job = data?["job"] as? String, let start = self.start {
                    let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    let record: [String: Any] = ["job": job, "candidate": self.request.candidate,
                        "suite": self.request.suite, "case": self.request.case, "visible_ms": elapsed]
                    guard let encoded = try? JSONSerialization.data(withJSONObject: record),
                          let text = String(data: encoded, encoding: .utf8) else {
                        self.fail("Could not encode timing evidence.")
                    }
                    print(text)
                    exit(0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitForAnswer() }
            }
        }
    }

    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
guard CommandLine.arguments.count == 3,
      let url = URL(string: CommandLine.arguments[1]),
      url.scheme == "http", url.host == "127.0.0.1", url.port != nil,
      url.path == "/chat", url.query == nil, url.user == nil,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
      data.count <= 32 * 1024,
      let request = try? JSONDecoder().decode(Request.self, from: data) else {
    exit(2)
}
let rehearsal = Rehearsal(request)
DispatchQueue.main.asyncAfter(deadline: .now() + (request.case == "full-budget" ? 900 : 240)) {
    rehearsal.fail("Timed out waiting for the approved fixture answer.")
}
rehearsal.web.load(URLRequest(url: url))
app.run()
