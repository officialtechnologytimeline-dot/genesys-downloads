import XCTest

/// GENESYS web app on an iPhone: Safari -> Share -> Add to Home Screen -> open the icon -> watch the automatic test.
final class WebAppTests: XCTestCase {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var url: String { ProcessInfo.processInfo.environment["GENESYS_URL"] ?? "https://ios-test.genesys-site.pages.dev/app/" }

    func note(_ s: String) { print("[ios] \(Date()) \(s)") }
    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        note("foto \(name)")
    }
    /// Labels on screen, read from one accessibility snapshot (no element-by-element queries: they break while pages change).
    func labels(_ app: XCUIApplication, _ max: Int = 40) -> [String] {
        var out: [String] = []
        for line in app.debugDescription.components(separatedBy: "\n") {
            guard let r = line.range(of: "label: '") else { continue }
            var l = String(line[r.upperBound...]); if let e = l.range(of: "'", options: .backwards) { l = String(l[..<e.lowerBound]) }
            l = l.trimmingCharacters(in: .whitespaces)
            if !l.isEmpty && !out.contains(l) { out.append(l) }
            if out.count >= max { break }
        }
        return out
    }
    func ids(_ app: XCUIApplication, _ max: Int = 40) -> [String] {
        var out: [String] = []
        for line in app.debugDescription.components(separatedBy: "\n") {
            guard let r = line.range(of: "identifier: '") else { continue }
            var l = String(line[r.upperBound...]); if let e = l.range(of: "'") { l = String(l[..<e.lowerBound]) }
            if !l.isEmpty && !out.contains(l) && l.count < 60 { out.append(l) }
            if out.count >= max { break }
        }
        return out
    }
    @discardableResult
    func tapAny(_ app: XCUIApplication, _ names: [String], wait: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(wait)
        let pred = NSPredicate(format: "label IN %@ OR identifier IN %@", names, names)
        repeat {
            let e = app.descendants(matching: .any).matching(pred).firstMatch
            if e.exists && e.isHittable { let l = e.label; e.tap(); note("tocco '\(l)'"); return true }
            usleep(500_000)
        } while Date() < end
        note("non trovato: \(names) · etichette: \(labels(app, 25)) · id: \(ids(app, 20))")
        return false
    }

    func testWebAppOnIPhone() throws {
        continueAfterFailure = true
        // run.sh has already opened the page in Safari (simctl openurl): bring Safari to the front without restarting it
        safari.activate()
        sleep(3)
        tapAny(safari, ["Continue", "Continua", "Not Now", "Close"], wait: 2)
        if !safari.debugDescription.contains("ios-test") && !safari.debugDescription.contains("GENESYS") { note("pagina non aperta: la apro"); safari.open(URL(string: url)!); sleep(12) }
        sleep(6)
        snap("1-safari")
        note("Safari: \(labels(safari, 30))")
        let mode = ProcessInfo.processInfo.environment["GENESYS_MODE"] ?? "home"
        note("modo: \(mode)")
        if mode != "safari" {
        // Share -> Add to Home Screen -> Add
        if !tapAny(safari, ["ShareButton", "Share", "Condividi"], wait: 8) {
            tapAny(safari, ["TabBarItemTitle", "Address"], wait: 3); sleep(1); tapAny(safari, ["ShareButton", "Share"], wait: 5)
        }
        sleep(3); snap("2-condividi")
        var added = tapAny(safari, ["Add to Home Screen", "Aggiungi alla schermata Home"], wait: 4)
        if !added { safari.swipeUp(); sleep(2); added = tapAny(safari, ["Add to Home Screen", "Aggiungi alla schermata Home"], wait: 6) }
        if !added { safari.swipeUp(); sleep(2); added = tapAny(safari, ["Add to Home Screen", "Aggiungi alla schermata Home"], wait: 6) }
        sleep(3); snap("3-aggiungi")
        note("Foglio: \(labels(safari, 30))")
        tapAny(safari, ["Add", "Aggiungi"], wait: 8)
        sleep(4); snap("4-home")
        XCUIDevice.shared.press(.home); sleep(2)
        var opened = false
        for _ in 0..<6 {
            let icon = springboard.icons["GENESYS"]
            if icon.exists && icon.isHittable { icon.tap(); opened = true; break }
            springboard.swipeLeft(); sleep(1)
        }
        note(opened ? "aperta l'icona GENESYS" : "icona GENESYS non trovata · \(labels(springboard, 30))")
        snap("5-aperta")
        } // fine "home"
        // watch the web app run its automatic test (up to 18 minutes). The page text is read from the accessibility tree.
        let candidates = ["com.apple.webapp", "com.apple.WebSheet", "com.apple.mobilesafari"]
        sleep(5)
        for c in candidates { note("app \(c): stato \(XCUIApplication(bundleIdentifier: c).state.rawValue)") }
        var landscape = false, seen = Set<String>()
        let start = Date()
        var finished: Date? = nil
        let keys = [" HOP", "PROVA", "[gioco]", "install", "salvato", "ritorno", "chiave", "ERRORE", "accesso", "standalone"]
        let watch = Double(ProcessInfo.processInfo.environment["GENESYS_WATCH"] ?? "1080") ?? 1080
        while Date().timeIntervalSince(start) < watch {
            sleep(10)
            var tree = ""
            for c in candidates {
                let app = XCUIApplication(bundleIdentifier: c)
                if app.state == .runningForeground { tree = app.debugDescription; if c != "com.apple.webapp" && !seen.contains("fg-" + c) { seen.insert("fg-" + c); note("in primo piano: \(c)") }; break }
            }
            if tree.isEmpty { tree = springboard.debugDescription }
            for line in tree.components(separatedBy: "\n") {
                guard let r = line.range(of: "label: '") else { continue }
                let label = String(line[r.upperBound...].dropLast(1))
                for part in label.components(separatedBy: "\\n") where keys.contains(where: { part.contains($0) }) && !seen.contains(part) {
                    seen.insert(part); note("web app: \(part.prefix(220))")
                }
            }
            if tree.contains("pagina gioco aperta") && !landscape { XCUIDevice.shared.orientation = .landscapeLeft; landscape = true; note("telefono girato in orizzontale"); sleep(3); snap("6-gioco-orizzontale") }
            if tree.contains("GIOCO AVVIATO") && !seen.contains("snap-game") { seen.insert("snap-game"); sleep(8); snap("7-gioco-avviato") }
            if tree.contains("ritorno dal gioco") && landscape { XCUIDevice.shared.orientation = .portrait; landscape = false; note("telefono di nuovo verticale"); sleep(3); snap("8-ritorno") }
            if tree.contains("PROVA FERMA") || tree.contains("NON PARTE") { snap("x-errore"); note("ERRORE nella prova"); break }
            if tree.contains("FINE PROVA") && finished == nil { finished = Date(); snap("9-fine") }
            if let f = finished, Date().timeIntervalSince(f) > 25 { snap("10-accesso-google"); break }
            if Int(Date().timeIntervalSince(start)) % 120 < 10 { snap("t\(Int(Date().timeIntervalSince(start)))") }
        }
        note("fine osservazione dopo \(Int(Date().timeIntervalSince(start))) s")
    }
}
