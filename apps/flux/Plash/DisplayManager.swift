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
		context.window.contentView = context.webViewController.webView

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
		let window = DesktopWindow(display: display)
		let webViewController = WebViewController()

		window.contentView = webViewController.webView
		window.contentView?.isHidden = true

		// Wire up mouse tracker callback
		window.mouseTracker.onMouseMove = { [weak webViewController] position, size in
			webViewController?.injectMousePosition(position, windowSize: size)
		}

		let context = DisplayContext(
			window: window,
			webViewController: webViewController,
			display: display
		)

		contexts[display.id] = context

		// Load the assigned website for this display if available
		if let websiteId = Defaults[.websitesPerDisplay][display.id.uuidString],
		   let website = WebsitesController.shared.all.first(where: { $0.id.uuidString == websiteId }) {
			loadURL(website.url, in: context)
		}
	}

	/**
	Remove a window for a display.
	*/
	private func removeWindow(for displayId: UUID) {
		guard let context = contexts[displayId] else {
			return
		}

		context.window.close()
		contexts.removeValue(forKey: displayId)
	}

	/**
	Clean up all windows.
	*/
	func cleanup() {
		for context in contexts.values {
			context.window.close()
		}
		contexts.removeAll()
	}

	// Singleton lifecycle managed by AppState\n
}
