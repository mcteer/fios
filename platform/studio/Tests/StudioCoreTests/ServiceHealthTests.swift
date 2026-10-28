import Foundation

func runServiceHealthTests() throws {
    func reply(_ status:String,_ body:String,_ extra:String="")->Data {
        Data("HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: application/json\r\n\(extra)\r\n\(body)".utf8)
    }
    guard ServiceHealthWire.decode(reply("200 OK","{\"status\":\"ok\"}")) == .healthy,
          ServiceHealthWire.decode(reply("503 Service Unavailable","{\"status\":\"loading\"}")) == .loading,
          ServiceHealthWire.decode(reply("401 Unauthorized","")) == .waitingCredentials,
          ServiceHealthWire.decode(reply("403 Forbidden","")) == .waitingCredentials else {fatalError("Service health status mapping broken")}
    for data in [reply("302 Found","", "Location: http://example.invalid/\r\n"),
                 reply("200 OK","{\"status\":\"ok\",\"status\":\"loading\"}"),
                 reply("200 OK","{\"status\":\"ok\"}","Transfer-Encoding: chunked\r\n"),
                 reply("200 OK","{\"status\":\"ok\"}","Content-Length: 15\r\n"),
                 reply("200 OK","{\"status\":\"ok\",\"model\":\"unreviewed\"}"),
                 reply("200 OK",String(repeating:"x",count:16385)),
                 reply("200 OK","{\"status\":\"ok\"}")+Data([0])] {
        guard ServiceHealthWire.decode(data) == .unavailable else {fatalError("Redirect/ambiguous/unbounded service health accepted")}
    }
    for port in [0,1,80,443,65536] {
        do {_ = try ServiceHealthProbe(port:port);fatalError("Unapproved health target accepted")}
        catch RuntimeError.invalid {}
    }
    print("PASS: fixed no-inference health wire, loading/auth separation, redirects/ambiguous/oversized response and target refusal")
}
