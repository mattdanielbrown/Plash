import SwiftUI
import AppKit

@MainActor
final class ControlsButtonViewModel: ObservableObject {
	@Published var isHovered: Bool = false

	var onTap: (() -> Void)?

	func handleTap() {
		onTap?()
	}
}

struct ControlsButton: View {
	@ObservedObject var viewModel: ControlsButtonViewModel

	var body: some View {
		VStack {
			HStack {
				Spacer()
				Button(action: {
					viewModel.handleTap()
				}) {
					Image(systemName: "gear")
						.font(.system(size: 20, weight: .medium))
						.foregroundColor(.white)
						.frame(width: 44, height: 44)
						.background(
							Color.black.opacity(viewModel.isHovered ? 0.6 : 0.4)
						)
						.cornerRadius(8)
				}
				.buttonStyle(PlainButtonStyle())
				.onHover { hovering in
					viewModel.isHovered = hovering
				}
				.padding(12)
			}
			Spacer()
		}
		.allowsHitTesting(true)
	}
}
