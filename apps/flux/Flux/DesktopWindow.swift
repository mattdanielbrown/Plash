import Cocoa
import SwiftUI

final class DesktopWindow: NSWindow {
	override var canBecomeMain: Bool { isInteractive }
	override var canBecomeKey: Bool { isInteractive }
	override var acceptsFirstResponder: Bool { isInteractive }

	private var cancellables = Set<AnyCancellable>()

	private(set) lazy var mouseTracker = MouseTracker(window: self)

	private var overlayHostingView: NSHostingView<MousePositionOverlay>?
	private(set) var mousePositionViewModel: MousePositionOverlayViewModel?
	private var containerView: NSView?
	private(set) var webViewContainer: NSView?

	private var controlsButtonHostingView: NSHostingView<ControlsButton>?
	private var controlsButtonViewModel: ControlsButtonViewModel?

	var sendMouseEvents: Bool = false {
		didSet {
			mouseTracker.isEnabled = sendMouseEvents && !isInteractive
		}
	}

	var targetDisplay: Display? {
		didSet {
			setFrame()
		}
	}

	var isInteractive = false {
		didSet {
			if isInteractive {
				level = Defaults[.bringBrowsingModeToFront] ? .floating : (.desktopIcon + 1) // The `+ 1` fixes a weird issue where the window is sometimes not interactive. (macOS 11.2.1)
				makeKeyAndOrderFront(self)
				ignoresMouseEvents = false

				// Disable mouse tracking in browsing mode (native events are available)
				mouseTracker.isEnabled = false
			} else {
				level = .desktop
				orderBack(self)

				// Even though the window is on `.desktop` level, the user would be able to interact if they hide desktop icons.
				ignoresMouseEvents = true

				// Re-enable mouse tracking if setting is on
				mouseTracker.isEnabled = sendMouseEvents
			}
		}
	}

	convenience init(display: Display?) {
		self.init(
			contentRect: .zero,
			styleMask: [
				.borderless
			],
			backing: .buffered,
			defer: false
		)

		self.targetDisplay = display

		self.isOpaque = false
		self.backgroundColor = .clear
		self.level = .desktop
		self.isRestorable = false
		self.canHide = false
		self.displaysWhenScreenProfileChanges = true
		self.collectionBehavior = [
			.stationary,
			.ignoresCycle,
			.fullScreenNone // This ensures that if Flux is launched while an app is fullscreen (fullscreen is a separate space), it will not show behind that app and instead show in the primary space.
		]

		disableSnapshotRestoration()
		setFrame()

		NSScreen.publisher
			.sink { [weak self] in
				self?.setFrame()
			}
			.store(in: &cancellables)

		Defaults.publisher(.extendFluxBelowMenuBar)
			.sink { [weak self] _ in
				self?.setFrame()
			}
			.store(in: &cancellables)
	}

	private func setFrame() {
		// Ensure the screen still exists.
		guard let screen = targetDisplay?.screen ?? .main else {
			return
		}

		var frame = screen.frameWithoutStatusBar
		frame.size.height += 1 // Probably not needed, but just to ensure it covers all the way up to the menu bar on older Macs (I can only test on M1 Mac)

		if Defaults[.extendFluxBelowMenuBar] {
			frame = screen.frame
		}

		setFrame(frame, display: true)
	}

	/**
	Shows the mouse position overlay on this window.
	*/
	func showMousePositionOverlay() {
		guard overlayHostingView == nil else {
			print("DesktopWindow: Mouse position overlay already shown")
			return
		}

		print("DesktopWindow: Creating mouse position overlay")

		// Create container view if needed
		if containerView == nil {
			let container = NSView(frame: contentView?.bounds ?? .zero)
			container.autoresizingMask = [.width, .height]
			containerView = container

			// Move existing content view (web view) into container
			if let existingContentView = contentView {
				let webContainer = NSView(frame: existingContentView.bounds)
				webContainer.autoresizingMask = [.width, .height]
				webViewContainer = webContainer

				// Transfer the existing content view to the web container
				existingContentView.removeFromSuperview()
				existingContentView.frame = webContainer.bounds
				existingContentView.autoresizingMask = [.width, .height]
				webContainer.addSubview(existingContentView)

				// Add web container to main container
				container.addSubview(webContainer)

				// Set container as window's content view
				contentView = container
			}
		}

		// Create overlay
		let viewModel = MousePositionOverlayViewModel()
		mousePositionViewModel = viewModel

		let overlayView = MousePositionOverlay(viewModel: viewModel)
		let hostingView = NSHostingView(rootView: overlayView)
		hostingView.autoresizingMask = [.width, .height]
		hostingView.frame = containerView?.bounds ?? .zero

		overlayHostingView = hostingView

		if let container = containerView {
			print("DesktopWindow: Adding overlay to container view with bounds: \(container.bounds)")
			container.addSubview(hostingView)
		} else {
			print("DesktopWindow: ERROR - No container view available")
		}
	}

	/**
	Hides and removes the mouse position overlay from this window.
	*/
	func hideMousePositionOverlay() {
		overlayHostingView?.removeFromSuperview()
		overlayHostingView = nil
		mousePositionViewModel = nil
	}

	/**
	Shows the controls button in the upper right corner.
	*/
	func showControlsButton() {
		guard controlsButtonHostingView == nil else {
			print("DesktopWindow: Controls button already shown")
			return
		}

		print("DesktopWindow: Creating controls button")

		let viewModel = ControlsButtonViewModel()
		viewModel.onTap = {
			// Open settings window
			SSApp.showSettingsWindow()
		}
		controlsButtonViewModel = viewModel

		let controlsButton = ControlsButton(viewModel: viewModel)
		let hostingView = NSHostingView(rootView: controlsButton)
		hostingView.autoresizingMask = [.width, .height]

		// Get the main content view to add the button to
		if let mainContentView = contentView {
			hostingView.frame = mainContentView.bounds
			controlsButtonHostingView = hostingView
			mainContentView.addSubview(hostingView)
			print("DesktopWindow: Controls button added to content view")
		} else {
			print("DesktopWindow: ERROR - No content view for controls button")
		}
	}

	/**
	Hides and removes the controls button.
	*/
	func hideControlsButton() {
		controlsButtonHostingView?.removeFromSuperview()
		controlsButtonHostingView = nil
		controlsButtonViewModel = nil
	}
}
