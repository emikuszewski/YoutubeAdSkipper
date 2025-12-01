import Cocoa
import Quartz
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isEnabled = true
    private var skipCount = 0
    private var lastSkipTime: Date = .distantPast
    
    // JavaScript to find and click skip button
    private func getSkipScript() -> String {
        return "var b=document.querySelector('#movie_player .ytp-skip-ad-button');if(b){b.click();'skipped';}else{'none';}"
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: "YouTube Ad Skipper")
            button.image?.isTemplate = true
        }
        
        setupMenu()
        
        // Check if Chrome allows AppleScript
        checkChromeScriptingAccess()
        
        startMonitoring()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Status: Active", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        let countMenuItem = NSMenuItem(title: "Ads Skipped: 0", action: nil, keyEquivalent: "")
        countMenuItem.tag = 101
        menu.addItem(countMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Disable", action: #selector(toggleEnabled), keyEquivalent: "t")
        toggleItem.tag = 102
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem(title: "Test Skip Now", action: #selector(testSkip), keyEquivalent: "s"))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func toggleEnabled() {
        isEnabled.toggle()
        
        if let menu = statusItem.menu {
            if let statusItem = menu.item(withTag: 100) {
                statusItem.title = isEnabled ? "Status: Active" : "Status: Paused"
            }
            if let toggleItem = menu.item(withTag: 102) {
                toggleItem.title = isEnabled ? "Disable" : "Enable"
            }
        }
        
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: isEnabled ? "forward.fill" : "forward",
                accessibilityDescription: "YouTube Ad Skipper"
            )
        }
    }
    
    @objc private func testSkip() {
        trySkipAd(isManual: true)
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    private func checkChromeScriptingAccess() {
        // Check accessibility permissions (needed for mouse events)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "YouTube Ad Skipper needs accessibility permissions to click the skip button.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        
        // Test Chrome automation
        let testScript = """
        tell application "Google Chrome"
            return "ok"
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: testScript) {
            script.executeAndReturnError(&error)
            
            if error != nil {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Automation Permission Required"
                    alert.informativeText = "YouTube Ad Skipper needs permission to control Chrome.\n\nWhen prompted, click 'OK' to allow access.\n\nIf you denied it previously:\nSystem Settings → Privacy & Security → Automation → Enable Chrome for this app"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Got it")
                    alert.runModal()
                }
            }
        }
    }
    
    private func startMonitoring() {
        // Poll every 0.75 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.trySkipAd(isManual: false)
        }
    }
    
    private func trySkipAd(isManual: Bool) {
        guard isEnabled || isManual else { return }
        
        // Debounce - don't skip more than once per second
        guard Date().timeIntervalSince(lastSkipTime) > 1.0 else { return }
        
        // Step 1: Get button coordinates from Chrome via JavaScript
        let getCoords = """
        tell application "Google Chrome" to execute front window's active tab javascript "var b=document.querySelector('#movie_player .ytp-skip-ad-button');if(b){var r=b.getBoundingClientRect();JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2,sx:window.screenX,sy:window.screenY,oh:window.outerHeight,ih:window.innerHeight});}else{'none';}"
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            guard let script = NSAppleScript(source: getCoords) else { return }
            let result = script.executeAndReturnError(&error)
            
            guard let resultString = result.stringValue, resultString != "none" else {
                if isManual {
                    DispatchQueue.main.async {
                        self?.showManualTestResult("none")
                    }
                }
                return
            }
            
            // Parse coordinates
            guard let data = resultString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                  let x = json["x"], let y = json["y"],
                  let screenX = json["sx"], let screenY = json["sy"],
                  let outerHeight = json["oh"], let innerHeight = json["ih"] else {
                if isManual {
                    DispatchQueue.main.async {
                        self?.showManualTestResult("Failed to parse coordinates")
                    }
                }
                return
            }
            
            // Calculate screen position (account for Chrome toolbar)
            let toolbarHeight = outerHeight - innerHeight
            let clickX = screenX + x
            let clickY = screenY + toolbarHeight + y
            
            // Perform real mouse click
            DispatchQueue.main.async {
                self?.performClick(at: CGPoint(x: clickX, y: clickY), isManual: isManual)
            }
        }
    }
    
    private func performClick(at point: CGPoint, isManual: Bool) {
        // CGEvent uses top-left origin (same as web), so no conversion needed
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        
        mouseDown?.post(tap: .cghidEventTap)
        usleep(100000) // 100ms delay
        mouseUp?.post(tap: .cghidEventTap)
        
        lastSkipTime = Date()
        skipCount += 1
        updateSkipCount()
        flashIcon()
        
        if isManual {
            showManualTestResult("Clicked at (\(Int(point.x)), \(Int(point.y)))")
        }
    }
    
    private func showManualTestResult(_ result: String) {
        let alert = NSAlert()
        alert.messageText = "Skip Test Result"
        
        switch result {
        case "skipped":
            alert.informativeText = "✅ Successfully clicked skip button!"
        case "no_window":
            alert.informativeText = "No Chrome window open"
        case "not_youtube":
            alert.informativeText = "Current tab is not YouTube"
        case "none":
            alert.informativeText = "No skip button found on page.\n\nMake sure:\n• An ad is currently playing\n• The skip button has appeared"
        default:
            alert.informativeText = result
        }
        
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func updateSkipCount() {
        if let menu = statusItem.menu,
           let countItem = menu.item(withTag: 101) {
            countItem.title = "Ads Skipped: \(skipCount)"
        }
    }
    
    private func flashIcon() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Skipped!")
            button.image?.isTemplate = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                button.image = NSImage(
                    systemSymbolName: self?.isEnabled == true ? "forward.fill" : "forward",
                    accessibilityDescription: "YouTube Ad Skipper"
                )
                button.image?.isTemplate = true
            }
        }
    }
}
