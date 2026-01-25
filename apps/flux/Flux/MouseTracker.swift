import Cocoa

final class MouseTracker {
	private var globalMonitor: Any?
	private var localMonitor: Any?
	private var eventTap: CFMachPort?
	private var runLoopSource: CFRunLoopSource?
	private weak var targetWindow: NSWindow?
	private var lastPosition: CGPoint = .zero
	private var lastUpdateTime: Date = .distantPast
	private let throttleInterval: TimeInterval = 0.016 // ~60fps

	/// Enable debug logging to help validate mouse tracking is working
	var enableDebugLogging: Bool = false

	@MainActor var isEnabled: Bool = false {
		didSet {
			if isEnabled {
				startTracking()
			} else {
				stopTracking()
			}
		}
	}

	var onMouseMove: ((CGPoint, CGSize) -> Void)?

	/// When true, sends mouse position even when mouse is not over the window (e.g., when other windows are in between)
	/// This enables CGEvent tap mode to capture all system-wide mouse events
	@MainActor var alwaysSendPosition: Bool = true {
		didSet {
			if isEnabled {
				stopTracking()
				startTracking()
			}
		}
	}

	@MainActor init(window: NSWindow) {
		self.targetWindow = window
	}

	@MainActor private func startTracking() {
		if alwaysSendPosition {
			// Use CGEvent tap for true global mouse tracking (works even when cursor is over other windows)
			startEventTap()
		} else {
			// Use NSEvent monitors for tracking only when cursor is over the window
			startEventMonitors()
		}
	}

	@MainActor private func startEventMonitors() {
		// Monitor all mouse movement events (both moves and drags)
		let eventMask: NSEvent.EventTypeMask = [
			.mouseMoved,
			.leftMouseDragged,
			.rightMouseDragged,
			.otherMouseDragged
		]

		// Global monitor for when window ignores mouse events (non-browsing mode)
		globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
			self?.handleMouseEvent(event)
		}

		// Local monitor for when window is interactive (browsing mode)
		localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
			self?.handleMouseEvent(event)
			return event
		}
	}

	@MainActor private func startEventTap() {
		// Check for accessibility permissions
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		guard AXIsProcessTrustedWithOptions(options) else {
			print("MouseTracker: Accessibility permissions not granted. Falling back to event monitors.")
			print("MouseTracker: Please grant accessibility permissions in System Preferences > Privacy & Security > Accessibility")
			startEventMonitors()
			return
		}

		if enableDebugLogging {
			print("MouseTracker: Starting CGEvent tap for global mouse tracking")
		}

		// Event mask for mouse movement
		let eventMask = (1 << CGEventType.mouseMoved.rawValue) |
						(1 << CGEventType.leftMouseDragged.rawValue) |
						(1 << CGEventType.rightMouseDragged.rawValue) |
						(1 << CGEventType.otherMouseDragged.rawValue)

		// Create event tap with self as user info
		let selfPointer = Unmanaged.passUnretained(self).toOpaque()

		guard let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .listenOnly,
			eventsOfInterest: CGEventMask(eventMask),
			callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
				// Extract self from user info
				guard let userInfo = userInfo else {
					return Unmanaged.passUnretained(event)
				}
				let tracker = Unmanaged<MouseTracker>.fromOpaque(userInfo).takeUnretainedValue()

				// Handle the event on main thread
				Task { @MainActor in
					tracker.handleCGMouseEvent()
				}

				return Unmanaged.passUnretained(event)
			},
			userInfo: selfPointer
		) else {
			print("MouseTracker: Failed to create event tap. Falling back to event monitors.")
			startEventMonitors()
			return
		}

		// Create run loop source and add to current run loop
		let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

		// Enable the tap
		CGEvent.tapEnable(tap: tap, enable: true)

		self.eventTap = tap
		self.runLoopSource = runLoopSource
	}

	@MainActor private func stopTracking() {
		// Stop event monitors
		if let monitor = globalMonitor {
			NSEvent.removeMonitor(monitor)
			globalMonitor = nil
		}
		if let monitor = localMonitor {
			NSEvent.removeMonitor(monitor)
			localMonitor = nil
		}

		// Stop event tap
		if let source = runLoopSource {
			CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
			runLoopSource = nil
		}
		if let tap = eventTap {
			CGEvent.tapEnable(tap: tap, enable: false)
			eventTap = nil
		}
	}

	@MainActor private func handleMouseEvent(_ event: NSEvent) {
		guard let window = targetWindow else {
			return
		}

		// Throttle updates to reduce CPU usage
		let now = Date()
		guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else {
			return
		}
		lastUpdateTime = now

		let mouseLocation = NSEvent.mouseLocation // Screen coordinates
		let windowFrame = window.frame

		// In multi-monitor mode, only send events if mouse is on this window's screen
		// This ensures each monitor's webpage gets the correct mouse position
		if let windowScreen = window.screen {
			// Find which screen the mouse is on
			let mouseScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }

			// Only process if mouse is on this window's screen
			guard mouseScreen == windowScreen else {
				return
			}
		}

		// Check if mouse is within window bounds (unless alwaysSendPosition is enabled)
		if !alwaysSendPosition {
			guard windowFrame.contains(mouseLocation) else {
				return
			}
		}

		// Convert to window coordinates (bottom-left origin)
		let x = mouseLocation.x - windowFrame.minX
		let y = mouseLocation.y - windowFrame.minY

		// Normalize to 0-1 range
		let normalizedX = x / windowFrame.width
		let normalizedY = y / windowFrame.height

		let position = CGPoint(x: normalizedX, y: normalizedY)

		// Only send update if position changed
		if position != lastPosition {
			lastPosition = position
			onMouseMove?(position, windowFrame.size)
		}
	}

	@MainActor private func handleCGMouseEvent() {
		guard let window = targetWindow else {
			if enableDebugLogging {
				print("MouseTracker [CGEvent]: No target window")
			}
			return
		}

		// Throttle updates to reduce CPU usage
		let now = Date()
		guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else {
			return
		}
		lastUpdateTime = now

		let mouseLocation = NSEvent.mouseLocation // Screen coordinates
		let windowFrame = window.frame

		if enableDebugLogging {
			print("MouseTracker [CGEvent]: Received event at \(mouseLocation), window frame: \(windowFrame)")
		}

		// In multi-monitor mode, only send events if mouse is on this window's screen
		// This ensures each monitor's webpage gets the correct mouse position
		if let windowScreen = window.screen {
			// Find which screen the mouse is on
			let mouseScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }

			// Only process if mouse is on this window's screen
			guard mouseScreen == windowScreen else {
				if enableDebugLogging {
					print("MouseTracker [CGEvent]: Mouse on different screen, skipping")
				}
				return
			}
		}

		// Convert to window coordinates (bottom-left origin)
		let x = mouseLocation.x - windowFrame.minX
		let y = mouseLocation.y - windowFrame.minY

		// Normalize to 0-1 range
		let normalizedX = x / windowFrame.width
		let normalizedY = y / windowFrame.height

		let position = CGPoint(x: normalizedX, y: normalizedY)

		// Only send update if position changed
		if position != lastPosition {
			lastPosition = position
			if enableDebugLogging {
				print("MouseTracker [CGEvent]: Sending position update: \(position)")
			}
			onMouseMove?(position, windowFrame.size)
		}
	}

	deinit {
		// Clean up monitors and event tap
		// Note: Event monitors can be removed from any context
		if let monitor = globalMonitor {
			NSEvent.removeMonitor(monitor)
		}
		if let monitor = localMonitor {
			NSEvent.removeMonitor(monitor)
		}
		// Event tap cleanup must happen on main thread if still active
		// In practice, stopTracking() should have been called before deinit
		if let tap = eventTap {
			CGEvent.tapEnable(tap: tap, enable: false)
		}
	}
}
