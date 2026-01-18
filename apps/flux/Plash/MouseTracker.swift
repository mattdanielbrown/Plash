import Cocoa

final class MouseTracker {
	private var globalMonitor: Any?
	private var localMonitor: Any?
	private weak var targetWindow: NSWindow?
	private var lastPosition: CGPoint = .zero
	private var lastUpdateTime: Date = .distantPast
	private let throttleInterval: TimeInterval = 0.016 // ~60fps

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

	@MainActor init(window: NSWindow) {
		self.targetWindow = window
	}

	@MainActor private func startTracking() {
		// Global monitor for when window ignores mouse events (non-browsing mode)
		globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
			self?.handleMouseEvent(event)
		}

		// Local monitor for when window is interactive (browsing mode)
		localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
			self?.handleMouseEvent(event)
			return event
		}
	}

	private func stopTracking() {
		if let monitor = globalMonitor {
			NSEvent.removeMonitor(monitor)
			globalMonitor = nil
		}
		if let monitor = localMonitor {
			NSEvent.removeMonitor(monitor)
			localMonitor = nil
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

		// Check if mouse is within window bounds
		guard windowFrame.contains(mouseLocation) else {
			return
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

	deinit {
		stopTracking()
	}
}
