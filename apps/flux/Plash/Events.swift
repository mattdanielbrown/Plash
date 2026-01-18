import Cocoa
import KeyboardShortcuts

extension AppState {
	func setUpEvents() {
		menu.onUpdate = { [self] in
			updateMenu()
		}

		// Note: In multi-monitor mode, we listen to the first web view controller's events
		// This is a simplification; ideally we'd track all web views
		if let webViewController {
			webViewController.didLoadPublisher
				.convertToResult()
				.sink { [self] result in
					switch result {
					case .success:
						// Set the persisted zoom level.
						// This must be here as `webView.url` needs to have been set.
						let zoomLevel = webViewController.webView.zoomLevelWrapper
						if zoomLevel != 1 {
							webViewController.webView.zoomLevelWrapper = zoomLevel
						}

						statusItemButton.toolTip = WebsitesController.shared.current?.tooltip
					case .failure(let error):
						webViewError = error
					}
				}
				.store(in: &cancellables)
		}

		powerSourceWatcher?.didChangePublisher
			.sink { [self] _ in
				guard Defaults[.deactivateOnBattery] else {
					return
				}

				setEnabledStatus()
			}
			.store(in: &cancellables)

		SSEvents.deviceDidWake
			.sink { [self] in
				reloadWebsite()
			}
			.store(in: &cancellables)

		SSEvents.isScreenLocked
			.sink { [self] in
				isScreenLocked = $0
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.websites, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] in
				resetTimer()
				recreateWebViewAndReload()

				// We never destroy the webview, so we have to make sure it's not in browsing mode when there are no websites.
				if $0.newValue.isEmpty {
					Defaults[.isBrowsingMode] = false
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.isBrowsingMode)
			.receive(on: DispatchQueue.main)
			.sink { [self] change in
				isBrowsingMode = change.newValue
			}
			.store(in: &cancellables)

		Defaults.publisher(.hideMenuBarIcon)
			.sink { [self] _ in
				handleMenuBarIcon()
			}
			.store(in: &cancellables)

		Defaults.publisher(.opacity)
			.sink { [self] change in
				displayManager.setAlpha(isBrowsingMode ? 1 : change.newValue)
			}
			.store(in: &cancellables)

		Defaults.publisher(.reloadInterval)
			.sink { [self] _ in
				resetTimer()
			}
			.store(in: &cancellables)

		Defaults.publisher(.display, options: [])
			.sink { [self] change in
				// Only update if not in multi-monitor mode
				if !Defaults[.enableMultiMonitor], let display = change.newValue {
					displayManager.updateDisplays(Set([display]))
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.deactivateOnBattery)
			.sink { [self] _ in
				setEnabledStatus()
			}
			.store(in: &cancellables)

		Defaults.publisher(.showOnAllSpaces)
			.sink { [self] change in
				for window in displayManager.windows {
					window.collectionBehavior.toggleExistence(.canJoinAllSpaces, shouldExist: change.newValue)
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.bringBrowsingModeToFront, options: [])
			.sink { [self] _ in
				// Trigger isInteractive update for all windows
				for window in displayManager.windows {
					window.isInteractive = window.isInteractive
				}
			}
			.store(in: &cancellables)

		Defaults.publisher(.muteAudio, options: [])
			.receive(on: DispatchQueue.main)
			.sink { [self] _ in
				recreateWebViewAndReload()
			}
			.store(in: &cancellables)

		// Multi-monitor support
		Defaults.publisher(.enableMultiMonitor)
			.sink { [self] change in
				if change.newValue {
					// Enable multi-monitor mode - show on all displays
					displayManager.updateDisplays(Set(Display.all))
				} else {
					// Disable multi-monitor mode - revert to single display
					let display = Defaults[.display] ?? .main
					if let display {
						displayManager.updateDisplays(Set([display]))
					}
				}
				loadUserURL()
			}
			.store(in: &cancellables)

		// Monitor screen changes (display connect/disconnect)
		NSScreen.publisher
			.debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
			.sink { [self] in
				if Defaults[.enableMultiMonitor] {
					displayManager.updateDisplays(Set(Display.all))
					loadUserURL()
				}
			}
			.store(in: &cancellables)

		// Mouse position tracking (will be wired up when MouseTracker is integrated)
		Defaults.publisher(.sendMousePositionEvents)
			.sink { [self] change in
				for window in displayManager.windows {
					window.sendMouseEvents = change.newValue
				}
			}
			.store(in: &cancellables)

		KeyboardShortcuts.onKeyUp(for: .toggleBrowsingMode) {
			Defaults[.isBrowsingMode].toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .toggleEnabled) { [self] in
			isManuallyDisabled.toggle()
		}

		KeyboardShortcuts.onKeyUp(for: .reload) { [self] in
			reloadWebsite()
		}

		KeyboardShortcuts.onKeyUp(for: .nextWebsite) {
			WebsitesController.shared.makeNextCurrent()
		}

		KeyboardShortcuts.onKeyUp(for: .previousWebsite) {
			WebsitesController.shared.makePreviousCurrent()
		}

		KeyboardShortcuts.onKeyUp(for: .randomWebsite) {
			WebsitesController.shared.makeRandomCurrent()
		}
	}
}
