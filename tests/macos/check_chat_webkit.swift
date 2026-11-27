import AppKit
import Foundation
import WebKit

final class Acceptance: NSObject, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let web: WKWebView
    var width = 375
    var checks = 0
    var interaction = 0

    override init() {
        let frame = NSRect(x: 0, y: 0, width: width, height: 760)
        self.window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.web = WKWebView(frame: frame)
        super.init()
        window.contentView = web
        web.navigationDelegate = self
        web.uiDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        check()
    }

    func check() {
        let script = """
        (() => {
          const prompt = document.getElementById("prompt");
          const send = document.getElementById("send");
          const stream = typeof TextDecoderStream === "function";
          if (!prompt || !send || send.disabled || !stream) return null;
          prompt.focus();
          return { focus: document.activeElement === prompt,
                   width: document.documentElement.clientWidth,
                   overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth };
        })()
        """
        web.evaluateJavaScript(script) { result, error in
            if let failure = error {
                self.fail("WebKit evaluation failed: \(failure)")
            }
            guard let value = result as? [String: Any] else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.check() }
                return
            }
            guard value["focus"] as? Bool == true, value["overflow"] as? Bool == false,
                  value["width"] as? Int == self.width else {
                self.fail("Chat layout or keyboard focus failed at \(self.width) CSS pixels.")
            }
            self.checks += 1
            if self.checks == 2 {
                self.exercise()
                return
            }
            self.width = 1100
            self.window.setContentSize(NSSize(width: self.width, height: 760))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.check() }
        }
    }

    func exercise() {
        let script = """
        (() => {
          const control = (id) => document.getElementById(id);
          switch (\(interaction)) {
            case 0:
              control("prompt").value = "WebKit disposable turn";
              control("composer").requestSubmit();
              return true;
            case 1:
              if (control("stop").disabled || !control("history").querySelector("button")) return false;
              control("stop").click();
              return true;
            case 2:
              if (!control("status").textContent.startsWith("Stopped")) return false;
              control("new").click();
              control("history").querySelector("button").click();
              return true;
            case 3:
              if (!control("thread").textContent.includes("WebKit disposable turn")) return false;
              control("delete").click();
              return true;
            default:
              return !control("history").querySelector("button") && !control("thread").textContent;
          }
        })()
        """
        web.evaluateJavaScript(script) { result, error in
            if let failure = error {
                self.fail("Chat interaction failed: \(failure)")
            }
            if result as? Bool == true {
                self.interaction += 1
            }
            if self.interaction == 5 {
                print("WebKit passed layout, focus, compose, stop, reopen and delete.")
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.exercise() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(message.hasPrefix("Delete"))
    }

    func fail(_ reason: String) -> Never {
        FileHandle.standardError.write(Data((reason + "\n").utf8))
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
guard CommandLine.arguments.count == 2, let url = URL(string: CommandLine.arguments[1]) else {
    exit(2)
}
let acceptance = Acceptance()
DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
    acceptance.fail("Timed out during chat interaction \(acceptance.interaction).")
}
acceptance.web.load(URLRequest(url: url))
app.run()
