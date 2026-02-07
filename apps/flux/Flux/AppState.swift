import SwiftUI

@MainActor
final class AppState: ObservableObject {
	static let shared = AppState()

	var cancellables = Set<AnyCancellable>()

	let menu = SSMenu()
	let powerSourceWatcher = PowerSourceWatcher()

	private(set) lazy var statusItem = with(NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)) {
		$0.isVisible = true
		$0.behavior = [.removalAllowed, .terminationOnRemoval]
		$0.menu = menu
		$0.button!.image = .menuBarIcon
		$0.button!.setAccessibilityTitle(SSApp.name)
	}

	private(set) lazy var statusItemButton = statusItem.button!

	private(set) lazy var displayManager = DisplayManager()

	// Backward compatibility: single display mode
	private var desktopWindow: DesktopWindow? {
		displayManager.contextOrMain()?.window
	}

	var webViewController: WebViewController? {
		displayManager.contextOrMain()?.webViewController
	}

	var isBrowsingMode = false {
		didSet {
			guard isEnabled else {
				return
			}

			displayManager.setInteractive(isBrowsingMode)
			displayManager.setAlpha(isBrowsingMode ? 1 : Defaults[.opacity])
			resetTimer()
		}
	}

	var isEnabled = true {
		didSet {
			resetTimer()
			statusItemButton.appearsDisabled = !isEnabled

			if isEnabled {
				loadUserURL()
				displayManager.showAllWindows()
			} else {
				// TODO: Properly unload the web view instead of just clearing and hiding it.
				displayManager.hideAllWindows()
				loadURL("about:blank")
			}
		}
	}

	var isScreenLocked = false

	var isManuallyDisabled = false {
		didSet {
			setEnabledStatus()
		}
	}

	var reloadTimer: Timer?

	var webViewError: Error? {
		didSet {
			if let webViewError {
				statusItemButton.toolTip = "Error: \(webViewError.localizedDescription)"

				// TODO: There's a macOS bug that makes it black instead of a color.
//				statusItemButton.contentTintColor = .systemRed

				// TODO: Also present the error when the user just added it from the input box as then it's also "interactive".
				if
					isBrowsingMode,
					!webViewError.localizedDescription.contains("No internet connection")
				{
					webViewError.presentAsModal()
				}

				return
			}

			statusItemButton.contentTintColor = nil
		}
	}

	private init() {
		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		_ = statusItemButton
		addBuiltInWebsiteIfNeeded()
		initializeDisplays()
		setUpEvents()
		showWelcomeScreenIfNeeded()

		#if DEBUG
//		SSApp.showSettingsWindow()
//		Constants.openWebsitesWindow()
		#endif
	}

	private func addBuiltInWebsiteIfNeeded() {
		let controller = WebsitesController.shared

		guard !controller.all.contains(where: \.isBuiltIn) else {
			return
		}

		guard let url = Bundle.main.url(forResource: "FluidSimulation", withExtension: nil) else {
			return
		}

		var website = Website(
			id: UUID(),
			isCurrent: true,
			url: url,
			usePrintStyles: false
		)
		website.title = "Fluid Simulation"
		website.isBuiltIn = true

		controller.add(website)
	}

	private func initializeDisplays() {
		if Defaults[.enableMultiMonitor] {
			displayManager.updateDisplays(Set(Display.all))
		} else {
			// Single display mode
			let display = Defaults[.display] ?? .main
			if let display {
				displayManager.updateDisplays(Set([display]))
			}
		}
	}

	func handleMenuBarIcon() {
		statusItem.isVisible = true

		delay(.seconds(5)) { [self] in
			guard Defaults[.hideMenuBarIcon] else {
				return
			}

			statusItem.isVisible = false
		}
	}

	func handleAppReopen() {
		handleMenuBarIcon()
	}

	func setEnabledStatus() {
		isEnabled = !isManuallyDisabled && !isScreenLocked && !(Defaults[.deactivateOnBattery] && powerSourceWatcher?.powerSource.isUsingBattery == true)
	}

	func resetTimer() {
		reloadTimer?.invalidate()
		reloadTimer = nil

		guard
			isEnabled,
			!isBrowsingMode,
			let reloadInterval = Defaults[.reloadInterval]
		else {
			return
		}

		reloadTimer = Timer.scheduledTimer(withTimeInterval: reloadInterval, repeats: true) { [self] _ in
			Task { @MainActor in
				reloadWebsite()
			}
		}
	}

	func recreateWebView() {
		displayManager.recreateAllWebViews()
	}

	func recreateWebViewAndReload() {
		recreateWebView()
		loadUserURL()
	}

	func reloadWebsite() {
		// We always load the website the user specified in case it's a redirect that may change on each call.
		loadUserURL()

//		webViewController.reloadCurrentPageFromOrigin()
	}

	func loadUserURL() {
		loadURL(WebsitesController.shared.current?.url)
	}

	func toggleBrowsingMode() {
		Defaults[.isBrowsingMode].toggle()
	}

	func loadURL(_ url: URL?) {
		webViewError = nil

		guard
			let url,
			url.isValid
		else {
			return
		}

		// In multi-monitor mode, load the appropriate website for each display
		// In single-monitor mode, load the URL to all displays (which should be just one)
		if Defaults[.enableMultiMonitor] {
			// Load per-display websites
			for context in displayManager.allContexts {
				let displayId = context.display.id.uuidString
				if let websiteId = Defaults[.websitesPerDisplay][displayId],
				   let website = WebsitesController.shared.all.first(where: { $0.id.uuidString == websiteId }) {
					displayManager.setWebsite(website, for: context.display.id)
				} else {
					// Load the current website as fallback
					displayManager.setWebsite(WebsitesController.shared.current, for: context.display.id)
				}
			}
		} else {
			// Single display mode - load to all contexts
			displayManager.loadURLInAllContexts(url)
		}
	}
}
