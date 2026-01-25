import SwiftUI

@MainActor
final class MousePositionOverlayViewModel: ObservableObject {
	@Published var mouseX: CGFloat = 0
	@Published var mouseY: CGFloat = 0
	@Published var isVisible: Bool = true

	func updatePosition(x: CGFloat, y: CGFloat) {
		mouseX = x
		mouseY = y
	}
}

struct MousePositionOverlay: View {
	@ObservedObject var viewModel: MousePositionOverlayViewModel

	var body: some View {
		VStack {
			Spacer()
			HStack {
				Spacer()
				VStack(alignment: .trailing, spacing: 6) {
					Text("X: \(Int(viewModel.mouseX))")
						.font(.system(.title3, design: .monospaced))
						.fontWeight(.bold)
					Text("Y: \(Int(viewModel.mouseY))")
						.font(.system(.title3, design: .monospaced))
						.fontWeight(.bold)
				}
				.padding(16)
				.background(Color.red.opacity(0.8))
				.foregroundColor(.white)
				.cornerRadius(8)
				.padding(20)
				.border(Color.yellow, width: 3)
			}
		}
		.allowsHitTesting(false)
		.opacity(viewModel.isVisible ? 1 : 0)
	}
}
