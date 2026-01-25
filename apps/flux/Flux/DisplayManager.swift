import Cocoa
@preconcurrency import Combine

struct DisplayContext {
	let window: DesktopWindow
	let webViewController: WebViewController
	let display: Display
}

@MainActor
final class DisplayManager {
	private var contexts: [UUID: DisplayContext] = [:]
	private var cancellables = Set<AnyCancellable>()
	private var globalMouseMonitor: Any?
	private var localMouseMonitor: Any?
	private var bottomRightDisplayId: UUID?

	var windows: [DesktopWindow] {
		contexts.values.map(\.window)
	}

	var allContexts: [DisplayContext] {
		Array(contexts.values)
	}

	// Get context for a specific display
	func context(for displayId: UUID) -> DisplayContext? {
		contexts[displayId]
	}

	// Get context for a specific display, or the main display as fallback
	func contextOrMain() -> DisplayContext? {
		if let mainDisplay = Display.main,
		   let context = contexts[mainDisplay.id] {
			return context
		}
		return contexts.values.first
	}

	/**
	Update the displays being managed. Creates windows for new displays, removes windows for removed displays.
	*/
	func updateDisplays(_ displays: Set<Display>) {
		NSLog("DisplayManager.updateDisplays(): Called with \(displays.count) displays")
		for (index, display) in displays.enumerated() {
			NSLog("  Display \(index): id=\(display.id.uuidString), name=\(display.localizedName), screen frame=\(display.screen?.frame ?? .zero)")
		}

		let currentDisplayIds = Set(contexts.keys)
		let newDisplayIds = Set(displays.map(\.id))

		// Remove displays that are no longer present
		let displaysToRemove = currentDisplayIds.subtracting(newDisplayIds)
		for displayId in displaysToRemove {
			removeWindow(for: displayId)
		}

		// Add new displays
		let displaysToAdd = newDisplayIds.subtracting(currentDisplayIds)
		for displayId in displaysToAdd {
			guard let display = displays.first(where: { $0.id == displayId }) else {
				continue
			}
			createWindow(for: display)
		}

		// Update bottom-right display and set up mouse tracking
		updateBottomRightDisplay(Array(displays))
	}

	/**
	Identifies the bottom-right display and sets up the mouse position overlay.
	The bottom-right display is the one with maximum X and minimum Y (macOS uses bottom-left origin).
	*/
	private func updateBottomRightDisplay(_ displays: [Display]) {
		// Clear previous overlay
		if let previousId = bottomRightDisplayId,
		   let previousContext = contexts[previousId] {
			previousContext.window.hideMousePositionOverlay()
		}

		// Find bottom-right display
		let displaysWithScreens = displays.compactMap { display -> (Display, NSScreen)? in
			guard let screen = display.screen else { return nil }
			return (display, screen)
		}

		guard !displaysWithScreens.isEmpty else {
			bottomRightDisplayId = nil
			return
		}

		// Sort by X (descending) then Y (ascending) to find bottom-right
		let sortedDisplays = displaysWithScreens.sorted { lhs, rhs in
			let lhsFrame = lhs.1.frame
			let rhsFrame = rhs.1.frame

			// First compare X (rightmost = higher X)
			if lhsFrame.maxX != rhsFrame.maxX {
				return lhsFrame.maxX > rhsFrame.maxX
			}

			// Then compare Y (bottommost = lower Y in macOS coordinates)
			return lhsFrame.minY < rhsFrame.minY
		}

		guard let bottomRightDisplay = sortedDisplays.first,
			  let context = contexts[bottomRightDisplay.0.id] else {
			bottomRightDisplayId = nil
			return
		}

		bottomRightDisplayId = bottomRightDisplay.0.id
		// print("DisplayManager: Bottom-right display identified: \(bottomRightDisplay.0.id)")
		// print("DisplayManager: Showing mouse position overlay on bottom-right display")
		// Comment out mouse position overlay
		// context.window.showMousePositionOverlay()

		// Set up global mouse tracking
		// setupGlobalMouseTracking()
	}

	/**
	Sets up global mouse tracking to update the mouse position overlay.
	*/
	private func setupGlobalMouseTracking() {
		// Remove existing monitors
		if let monitor = globalMouseMonitor {
			NSEvent.removeMonitor(monitor)
			globalMouseMonitor = nil
		}
		if let monitor = localMouseMonitor {
			NSEvent.removeMonitor(monitor)
			localMouseMonitor = nil
		}

		print("DisplayManager: Setting up global mouse tracking for overlay")

		// Add global mouse monitor
		globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
			self?.updateGlobalMousePosition()
		}

		// Also add local monitor
		localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
			self?.updateGlobalMousePosition()
			return event
		}
	}

	/**
	Updates the mouse position overlay with the current global mouse position.
	*/
	private func updateGlobalMousePosition() {
		guard let bottomRightDisplayId,
			  let context = contexts[bottomRightDisplayId],
			  let viewModel = context.window.mousePositionViewModel else {
			print("DisplayManager: Cannot update mouse position - missing bottomRightDisplayId, context, or viewModel")
			return
		}

		// Get mouse location in screen coordinates
		let mouseLocation = NSEvent.mouseLocation

		// Calculate global bounding box of all screens
		let screens = NSScreen.screens
		guard !screens.isEmpty else {
			return
		}

		var globalBounds = screens[0].frame
		for screen in screens {
			globalBounds = globalBounds.union(screen.frame)
		}

		// Convert mouse location to combined screen space
		// macOS uses bottom-left origin, so we convert to top-left origin for display
		let globalX = mouseLocation.x - globalBounds.origin.x
		let globalY = globalBounds.size.height - (mouseLocation.y - globalBounds.origin.y)

		viewModel.updatePosition(x: globalX, y: globalY)
	}

	/**
	Set the website for a specific display.
	*/
	func setWebsite(_ website: Website?, for displayId: UUID) {
		guard let context = contexts[displayId] else {
			return
		}

		// Recreate the web view with the new website
		context.webViewController.recreateWebView()

		// If there's a web view container (from mouse overlay), update it
		// Otherwise, set the web view as the window's content view directly
		if let webViewContainer = context.window.webViewContainer {
			// Remove old web view
			webViewContainer.subviews.forEach { $0.removeFromSuperview() }
			// Add new web view
			let webView = context.webViewController.webView
			webView.frame = webViewContainer.bounds
			webView.autoresizingMask = [.width, .height]
			webViewContainer.addSubview(webView)
		} else {
			context.window.contentView = context.webViewController.webView
		}

		// Load the URL
		if let website {
			loadURL(website.url, in: context)
		}
	}

	/**
	Load a URL in a specific context.
	*/
	private func loadURL(_ url: URL?, in context: DisplayContext) {
		guard
			var url,
			url.isValid
		else {
			return
		}

		do {
			url = try replacePlaceholders(of: url, for: context) ?? url
		} catch {
			error.presentAsModal()
			return
		}

		context.webViewController.loadURL(url)

		delay(.seconds(1)) {
			context.window.contentView?.isHidden = false
		}
	}

	/**
	Replace placeholders in URL for a specific display context.
	*/
	private func replacePlaceholders(of url: URL, for context: DisplayContext) throws -> URL? {
		guard let screen = context.display.screen else {
			return nil
		}

		return try url
			.replacingPlaceholder("[[screenWidth]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.width))
			.replacingPlaceholder("[[screenHeight]]", with: String(format: "%.0f", screen.frameWithoutStatusBar.height))
	}

	/**
	Set interactive mode (browsing mode) for all windows.
	*/
	func setInteractive(_ interactive: Bool) {
		for context in contexts.values {
			context.window.isInteractive = interactive
		}
	}

	/**
	Set alpha value for all windows.
	*/
	func setAlpha(_ alpha: CGFloat) {
		for context in contexts.values {
			context.window.alphaValue = alpha
		}
	}

	/**
	Show all windows.
	*/
	func showAllWindows() {
		for context in contexts.values {
			context.window.makeKeyAndOrderFront(self)
		}
	}

	/**
	Hide all windows.
	*/
	func hideAllWindows() {
		for context in contexts.values {
			context.window.orderOut(self)
		}
	}

	/**
	Recreate web views for all contexts.
	*/
	func recreateAllWebViews() {
		for context in contexts.values {
			context.webViewController.recreateWebView()
			context.window.contentView = context.webViewController.webView
		}
	}

	/**
	Load a URL in all contexts.
	*/
	func loadURLInAllContexts(_ url: URL?) {
		for context in contexts.values {
			loadURL(url, in: context)
		}
	}

	/**
	Create a window for a display.
	*/
	private func createWindow(for display: Display) {
		NSLog("DisplayManager.createWindow(): Creating window for display \(display.id.uuidString), name=\(display.localizedName)")
		let window = DesktopWindow(display: display)
		let webViewController = WebViewController()

		window.contentView = webViewController.webView
		window.contentView?.isHidden = true

		NSLog("DisplayManager.createWindow(): Window created with frame: \(window.frame)")

		// Wire up mouse tracker callback with display arrangement info
		window.mouseTracker.onMouseMove = { [weak webViewController, weak self] position, size in
			guard let self, let webViewController else { return }
			webViewController.injectMousePosition(position, windowSize: size)
			// Inject display arrangement for multi-monitor continuity
			self.injectDisplayArrangement(to: webViewController, for: display)
		}

		// Initialize mouse tracking from settings
		window.sendMouseEvents = Defaults[.sendMousePositionEvents]
		window.mouseTracker.alwaysSendPosition = Defaults[.trackMouseGlobally]
		window.mouseTracker.enableDebugLogging = Defaults[.debugMouseTracking]

		let context = DisplayContext(
			window: window,
			webViewController: webViewController,
			display: display
		)

		contexts[display.id] = context

		// Show controls button in upper right corner
		window.showControlsButton()

		// Inject initial display arrangement
		injectDisplayArrangement(to: webViewController, for: display)

		// Load the assigned website for this display if available
		if let websiteId = Defaults[.websitesPerDisplay][display.id.uuidString],
		   let website = WebsitesController.shared.all.first(where: { $0.id.uuidString == websiteId }) {
			loadURL(website.url, in: context)
		}
	}

	/**
	Inject display arrangement information into a WebViewController.
	This enables multi-monitor continuity for visual effects.
	*/
	private func injectDisplayArrangement(to webViewController: WebViewController, for display: Display) {
		guard let currentScreen = display.screen else {
			return
		}

		// Get all screens and calculate the global bounding rectangle
		let screens = NSScreen.screens
		guard !screens.isEmpty else {
			return
		}

		// Calculate the union of all screen frames (global bounding box) in macOS coordinates
		var globalBounds = screens[0].frame
		for screen in screens {
			globalBounds = globalBounds.union(screen.frame)
		}

		// Get the current screen's frame in macOS coordinates
		let screenFrame = currentScreen.frame

		// Convert from macOS coordinates (origin bottom-left, Y up) to web coordinates (origin top-left, Y down)
		// Web X = macOS X (same, relative to global origin)
		let macOSRelativeX = screenFrame.origin.x - globalBounds.origin.x
		let macOSRelativeY = screenFrame.origin.y - globalBounds.origin.y

		// Web Y = globalHeight - macOS Y - screenHeight
		let webScreenX = macOSRelativeX
		let webScreenY = globalBounds.size.height - macOSRelativeY - screenFrame.size.height

		webViewController.injectDisplayArrangement(
			screenWidth: Double(screenFrame.size.width),
			screenHeight: Double(screenFrame.size.height),
			globalWidth: Double(globalBounds.size.width),
			globalHeight: Double(globalBounds.size.height),
			screenOffsetX: Double(webScreenX),
			screenOffsetY: Double(webScreenY)
		)
	}

	/**
	Remove a window for a display.
	*/
	private func removeWindow(for displayId: UUID) {
		guard let context = contexts[displayId] else {
			return
		}

		// Stop mouse tracking before closing to prevent crash
		context.window.mouseTracker.isEnabled = false
		context.window.close()
		contexts.removeValue(forKey: displayId)
	}

	/**
	Clean up all windows.
	*/
	func cleanup() {
		// Remove global mouse monitors
		if let monitor = globalMouseMonitor {
			NSEvent.removeMonitor(monitor)
			globalMouseMonitor = nil
		}
		if let monitor = localMouseMonitor {
			NSEvent.removeMonitor(monitor)
			localMouseMonitor = nil
		}

		for context in contexts.values {
			context.window.close()
		}
		contexts.removeAll()
		bottomRightDisplayId = nil
	}

	// Singleton lifecycle managed by AppState\n
}
