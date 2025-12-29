import Cocoa
import SwiftUI
import WebKit
import UserNotifications
import Sparkle
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    weak var settingsWindow: NSWindow?
    var serverManager: ServerManager!
    var thinkingProxy: ThinkingProxy!
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationPermissionGranted = false
    private let updaterController: SPUStandardUpdaterController
    private var modelRouterCancellable: AnyCancellable?
    var modelSearchWindow: NSWindow?
    
    override init() {
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar
        setupMenuBar()
        
        // Setup Edit menu for Cmd+V, Cmd+C, Cmd+X support
        setupEditMenu()

        // Initialize managers
        serverManager = ServerManager()
        thinkingProxy = ThinkingProxy()
        
        // Initialize model router
        _ = ModelRouter.shared
        
        // Observe model router changes
        modelRouterCancellable = ModelRouter.shared.$activeModelId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateModelMenu()
            }
        
        // Warm commonly used icons to avoid first-use disk hits
        preloadIcons()
        
        configureNotifications()

        // Start server automatically
        startServer()

        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarStatus),
            name: .serverStatusChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFallbackNotification(_:)),
            name: .fallbackTriggered,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRoutingNotification(_:)),
            name: .init("routingNotification"),
            object: nil
        )

    }
    
    private func preloadIcons() {
        let statusIconSize = NSSize(width: 18, height: 18)
        let serviceIconSize = NSSize(width: 20, height: 20)
        
        let iconsToPreload = [
            ("icon-active.png", statusIconSize),
            ("icon-inactive.png", statusIconSize),
            ("icon-codex.png", serviceIconSize),
            ("icon-claude.png", serviceIconSize),
            ("icon-gemini.png", serviceIconSize)
        ]
        
        for (name, size) in iconsToPreload {
            if IconCatalog.shared.image(named: name, resizedTo: size, template: true) == nil {
                NSLog("[IconPreload] Warning: Failed to preload icon '%@'", name)
            }
        }
    }
    
    private func configureNotifications() {
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error {
                NSLog("[Notifications] Authorization failed: %@", error.localizedDescription)
            }
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
                if !granted {
                    NSLog("[Notifications] Authorization not granted; notifications will be suppressed")
                }
            }
        }
    }
    
    // MARK: - Notification Helper
    
    private func sendNotification(title: String, body: String, sound: Bool = false) {
        guard notificationPermissionGranted else {
            NSLog("[Notifications] Skipping notification (permission not granted): %@", title)
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                NSLog("[Notifications] Failed to send notification: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Edit Menu for Cmd+V Support
    
    /// Setup standard Edit menu to enable Cmd+V, Cmd+C, Cmd+X in text fields
    private func setupEditMenu() {
        // Get or create the main menu
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        NSApp.mainMenu = mainMenu
        
        // Create Edit menu
        let editMenu = NSMenu(title: "Edit")
        
        // Add standard editing actions
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(undoItem)
        
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        
        editMenu.addItem(NSMenuItem.separator())
        
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(cutItem)
        
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(copyItem)
        
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(pasteItem)
        
        editMenu.addItem(NSMenuItem.separator())
        
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(selectAllItem)
        
        // Create Edit menu item and add submenu
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        
        // Add to main menu (after any existing items)
        mainMenu.addItem(editMenuItem)
        
        NSLog("[AppDelegate] Edit menu added for Cmd+V support")
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let icon = IconCatalog.shared.image(named: "icon-inactive.png", resizedTo: NSSize(width: 18, height: 18), template: true) {
                button.image = icon
            } else {
                let fallback = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "EllProxy")
                fallback?.isTemplate = true
                button.image = fallback
                NSLog("[MenuBar] Failed to load inactive icon from bundle; using fallback system icon")
            }
        }

        menu = NSMenu()

        // Server Status
        menu.addItem(NSMenuItem(title: "Server: Stopped", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // 🎯 Active Models Section
        let activeModelsHeader = NSMenuItem(title: "🎯 ACTIVE MODELS", action: nil, keyEquivalent: "")
        activeModelsHeader.tag = 204
        activeModelsHeader.isEnabled = false
        menu.addItem(activeModelsHeader)
        
        // Default Model (clickable)
        let defaultModelItem = NSMenuItem(title: "⚡ Default: None", action: #selector(quickSwitchDefault), keyEquivalent: "")
        defaultModelItem.tag = 205
        menu.addItem(defaultModelItem)
        
        // Thinking Model (clickable)
        let thinkingModelItem = NSMenuItem(title: "🧠 Thinking: None", action: #selector(quickSwitchThinking), keyEquivalent: "")
        thinkingModelItem.tag = 206
        menu.addItem(thinkingModelItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick Routing Toggle
        let routingToggleItem = NSMenuItem(title: "Routing: Enabled", action: #selector(toggleRouting), keyEquivalent: "r")
        routingToggleItem.tag = 203
        menu.addItem(routingToggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Models Submenu REMOVED as per user request
        /*
        let modelsItem = NSMenuItem(title: "Switch Model", action: nil, keyEquivalent: "")
        modelsItem.tag = 201
        let modelsSubmenu = NSMenu()
        modelsItem.submenu = modelsSubmenu
        menu.addItem(modelsItem)
        
        menu.addItem(NSMenuItem.separator())
        */

        // Main Actions
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())

        // Server Control
        let startStopItem = NSMenuItem(title: "Start Server", action: #selector(toggleServer), keyEquivalent: "")
        startStopItem.tag = 100
        menu.addItem(startStopItem)

        menu.addItem(NSMenuItem.separator())

        // Copy URL
        let copyURLItem = NSMenuItem(title: "Copy Server URL", action: #selector(copyServerURL), keyEquivalent: "c")
        copyURLItem.isEnabled = false
        copyURLItem.tag = 102
        menu.addItem(copyURLItem)

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "u")
        checkForUpdatesItem.target = updaterController
        menu.addItem(checkForUpdatesItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        
        // Listen for menu bar update notifications from Search window
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UpdateMenuBar"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateModelMenu()
            self?.updateMenuBarStatus()
        }
        
        // Initial model menu update
        updateModelMenu()
    }
    
    /// Updates the model submenu with available models grouped by provider
    func updateModelMenu() {
        let router = ModelRouter.shared
        
        // Update Active Models display (tags 205, 206)
        if let defaultItem = menu.item(withTag: 205) {
            if let activeModel = router.activeModel {
                defaultItem.title = "⚡ Default: \(activeModel.name)"
            } else {
                defaultItem.title = "⚡ Default: None"
            }
        }
        
        if let thinkingItem = menu.item(withTag: 206) {
            if let thinkingModel = router.defaultThinkingModel {
                thinkingItem.title = "🧠 Thinking: \(thinkingModel.name)"
            } else {
                thinkingItem.title = "🧠 Thinking: Not Set"
            }
        }
        
        // Update routing toggle display (tag 203)
        if let routingItem = menu.item(withTag: 203) {
            if router.routingEnabled {
                routingItem.title = "Routing: ON (Smart)"
                routingItem.state = .on
            } else {
                routingItem.title = "Routing: OFF (Panic)"
                routingItem.state = .off
            }
        }
        
        // Submenu update logic removed since the item is removed
    }
    
    // MARK: - Menu Actions
    
    @objc func quickSwitchDefault() {
        // Opens Search Models window for Default model
        openModelSearchInternal(mode: .defaultModel)
    }
    
    @objc func quickSwitchThinking() {
        // Opens Search Models window for Thinking model
        openModelSearchInternal(mode: .thinkingModel)
    }
    
    @objc func toggleRouting() {
        ModelRouter.shared.routingEnabled.toggle()
        updateModelMenu()
        updateMenuBarStatus()
        
        let status = ModelRouter.shared.routingEnabled ? "enabled" : "disabled"
        sendNotification(title: "Model Routing", body: "Routing is now \(status)")
    }
    
    @objc func selectModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        
        ModelRouter.shared.activeModelId = modelId
        ModelRouter.shared.routingEnabled = true
        ModelRouter.shared.addToRecentModels(modelId)  // Track recent
        updateModelMenu()
        
        if let model = ModelRouter.shared.activeModel {
            sendNotification(title: "Model Selected", body: model.name)
        }
    }
    
    @objc func selectThinkingModel(_ sender: NSMenuItem) {
        guard let modelId = sender.representedObject as? String else { return }
        
        ModelRouter.shared.defaultThinkingModelId = modelId
        ModelRouter.shared.addToRecentModels(modelId)  // Track recent
        updateModelMenu()
        
        if let model = ModelRouter.shared.defaultThinkingModel {
            sendNotification(title: "Thinking Model Selected", body: model.name)
        }
    }
    
    @objc func openModelSearch() {
        openModelSearchInternal(mode: .defaultModel)
    }
    
    func openModelSearchInternal(mode: ModelSelectionMode) {
        // Always create new window to ensure mode is applied correctly
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Search Models"  // Generic title since mode selector is inside
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ModelSearchWindowView(mode: mode))
        modelSearchWindow = window
        
        modelSearchWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func createSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 950),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EllProxy"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let contentView = SettingsView(serverManager: serverManager)
        window.contentView = NSHostingView(rootView: contentView)

        settingsWindow = window
    }
    
    func windowDidClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }

    @objc func toggleServer() {
        if serverManager.isRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    func startServer() {
        // Start the thinking proxy first (port 8317)
        thinkingProxy.start()
        
        // Poll for thinking proxy readiness with timeout
        pollForProxyReadiness(attempts: 0, maxAttempts: 60, intervalMs: 50)
    }
    
    private func pollForProxyReadiness(attempts: Int, maxAttempts: Int, intervalMs: Int) {
        // Check if proxy is running
        if thinkingProxy.isRunning {
            // Success - proceed to start backend
            serverManager.start { [weak self] success in
                DispatchQueue.main.async {
                    if success {
                        self?.updateMenuBarStatus()
                        // User always connects to 8317 (thinking proxy)
                        self?.sendNotification(title: "Server Started", body: "EllProxy is now running on port 8317", sound: true)
                    } else {
                        // Backend failed - stop the proxy to keep state consistent
                        self?.thinkingProxy.stop()
                        self?.sendNotification(title: "Server Failed", body: "Could not start backend server on port 8318", sound: true)
                    }
                }
            }
            return
        }
        
        // Check if we've exceeded timeout
        if attempts >= maxAttempts {
            DispatchQueue.main.async { [weak self] in
                // Clean up partially initialized proxy
                self?.thinkingProxy.stop()
                self?.sendNotification(title: "Server Failed", body: "Could not start thinking proxy on port 8317 (timeout)", sound: true)
            }
            return
        }
        
        // Schedule next poll
        let interval = Double(intervalMs) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.pollForProxyReadiness(attempts: attempts + 1, maxAttempts: maxAttempts, intervalMs: intervalMs)
        }
    }

    func stopServer() {
        // Stop the thinking proxy first to stop accepting new requests
        thinkingProxy.stop()
        
        // Then stop CLIProxyAPI backend
        serverManager.stop()
        
        updateMenuBarStatus()
        sendNotification(title: "Server Stopped", body: "EllProxy server has been stopped")
    }

    @objc func copyServerURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("http://localhost:\(thinkingProxy.proxyPort)", forType: .string)
        sendNotification(title: "Copied", body: "Server URL copied to clipboard")
    }

    @objc func handleFallbackNotification(_ notification: Notification) {
        if let message = notification.userInfo?["message"] as? String {
            sendNotification(title: "Model Fallback", body: message, sound: true)
        }
    }

    
    @objc func handleRoutingNotification(_ notification: Notification) {
        if let message = notification.userInfo?["message"] as? String {
           // Use showNotification for cleaner banner
           showNotification(title: "EllProxy", body: message)
        }
    }

    @objc func updateMenuBarStatus() {
        // Update status items
        if let serverStatus = menu.item(at: 0) {
            serverStatus.title = serverManager.isRunning ? "Server: Running (port \(thinkingProxy.proxyPort))" : "Server: Stopped"
        }

        // Update button states
        if let startStopItem = menu.item(withTag: 100) {
            startStopItem.title = serverManager.isRunning ? "Stop Server" : "Start Server"
        }

        if let copyURLItem = menu.item(withTag: 102) {
            copyURLItem.isEnabled = serverManager.isRunning
        }
        
        // Update routing toggle
        if let routingToggleItem = menu.item(withTag: 203) {
            let enabled = ModelRouter.shared.routingEnabled
            routingToggleItem.title = enabled ? "✓ Routing: ON (Smart)" : "✗ Routing: OFF (Force)"
        }

        // Update icon based on server status
        if let button = statusItem.button {
            let iconName = serverManager.isRunning ? "icon-active.png" : "icon-inactive.png"
            let fallbackSymbol = serverManager.isRunning ? "network" : "network.slash"
            
            if let icon = IconCatalog.shared.image(named: iconName, resizedTo: NSSize(width: 18, height: 18), template: true) {
                button.image = icon
                NSLog("[MenuBar] Loaded %@ icon from cache", serverManager.isRunning ? "active" : "inactive")
            } else {
                let fallback = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: serverManager.isRunning ? "Running" : "Stopped")
                fallback?.isTemplate = true
                button.image = fallback
                NSLog("[MenuBar] Failed to load %@ icon; using fallback", serverManager.isRunning ? "active" : "inactive")
            }
        }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "io.automaze.ellproxy.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                NSLog("[Notifications] Failed to deliver notification '%@': %@", title, error.localizedDescription)
            }
        }
    }

    @objc func quit() {
        // Stop server and wait for cleanup before quitting
        if serverManager.isRunning {
            thinkingProxy.stop()
            serverManager.stop()
        }
        // Give a moment for cleanup to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .serverStatusChanged, object: nil)
        // Final cleanup - stop server if still running
        if serverManager.isRunning {
            thinkingProxy.stop()
            serverManager.stop()
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If server is running, stop it first
        if serverManager.isRunning {
            thinkingProxy.stop()
            serverManager.stop()
            // Give server time to stop (up to 3 seconds total with the improved stop method)
            return .terminateNow
        }
        return .terminateNow
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
