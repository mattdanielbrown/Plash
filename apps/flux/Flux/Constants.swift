import SwiftUI
import KeyboardShortcuts

enum Constants {
	@MainActor
	static var websitesWindow: NSWindow? {
		NSApp.windows.first { $0.identifier?.rawValue == "websites" }
	}

	@MainActor
	static func openWebsitesWindow() {
		SSApp.forceActivate()
		EnvironmentValues().openWindow(id: "websites")
	}
}

extension Defaults.Keys {
	static let websites = Key<[Website]>("websites", default: [])
	static let isBrowsingMode = Key<Bool>("isBrowsingMode", default: false)

	// Settings
	static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
	static let opacity = Key<Double>("opacity", default: 1)
	static let reloadInterval = Key<Double?>("reloadInterval")
	static let display = Key<Display?>("display")
	static let deactivateOnBattery = Key<Bool>("deactivateOnBattery", default: false)
	static let showOnAllSpaces = Key<Bool>("showOnAllSpaces", default: false)
	static let bringBrowsingModeToFront = Key<Bool>("bringBrowsingModeToFront", default: false)
	static let openExternalLinksInBrowser = Key<Bool>("openExternalLinksInBrowser", default: false)
	static let muteAudio = Key<Bool>("muteAudio", default: true)

	static let extendFluxBelowMenuBar = Key<Bool>("extendFluxBelowMenuBar", default: false)

	// Multi-monitor settings
	static let enableMultiMonitor = Key<Bool>("enableMultiMonitor", default: false)
	static let websitesPerDisplay = Key<[String: String]>("websitesPerDisplay", default: [:])

	// Mouse tracking
	static let sendMousePositionEvents = Key<Bool>("sendMousePositionEvents", default: false)
	static let trackMouseGlobally = Key<Bool>("trackMouseGlobally", default: true)
	static let debugMouseTracking = Key<Bool>("debugMouseTracking", default: false)
}

extension KeyboardShortcuts.Name {
	static let toggleBrowsingMode = Self("toggleBrowsingMode")
	static let toggleEnabled = Self("toggleEnabled")
	static let reload = Self("reload")
	static let nextWebsite = Self("nextWebsite")
	static let previousWebsite = Self("previousWebsite")
	static let randomWebsite = Self("randomWebsite")
}

extension Notification.Name {
	static let showAddWebsiteDialog = Self("showAddWebsiteDialog")
	static let showEditWebsiteDialog = Self("showEditWebsiteDialog")
}
