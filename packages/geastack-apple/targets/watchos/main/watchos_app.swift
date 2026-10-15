import Combine
import SwiftUI
import WatchKit

// watchOS apps have no UIApplication or UIView hierarchy to host a renderer in,
// so the shell is SwiftUI: gea paints into its framebuffer (watchos_host.mm) and
// this view shows each presented frame as an image and feeds touches back.

@main
struct GeaWatchApp: App {
	var body: some Scene {
		WindowGroup {
			GeaWatchRootView()
		}
	}
}

final class GeaWatchHost: ObservableObject {
	@Published private(set) var frame: CGImage?
	// The Crown's value is the scroll position in Crown units, bounded by the
	// scroll range, so the system's Crown indicator shows where the list is.
	@Published var crownValue = 0.0
	@Published private(set) var crownMax = 1.0
	let scale: CGFloat = max(1, WKInterfaceDevice.current().screenScale)
	private var timer: AnyCancellable?
	private var touching = false
	private var lastCrownOffset = 0.0

	// SwiftUI reports the Crown in its own units, not points; this sets how far
	// one unit scrolls. Tune it on a real watch.
	static let crownPointsPerUnit = 20.0

	func start(size: CGSize) {
		guard size.width > 0, size.height > 0 else { return }
		gea_watchos_start(Int32((size.width * scale).rounded()), Int32((size.height * scale).rounded()), Double(scale))
		tick()
	}

	// The frame loop runs only while the app is frontmost: an inactive watch app
	// (wrist down, always-on dimmed) keeps no display link and should not spin.
	func setActive(_ active: Bool) {
		if !active {
			timer = nil
			return
		}
		guard timer == nil else { return }
		timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
			.autoconnect()
			.sink { [weak self] _ in self?.tick() }
	}

	func touch(_ phase: GeaWatchTouchPhase, at point: CGPoint) {
		gea_watchos_touch(phase, Double(point.x), Double(point.y))
		// Present the result of the tap now rather than on the next timer tick.
		tick()
	}

	func drag(at point: CGPoint) {
		touch(touching ? GeaWatchTouchMove : GeaWatchTouchDown, at: point)
		touching = true
	}

	func lift(at point: CGPoint) {
		guard touching else { return }
		touching = false
		touch(GeaWatchTouchUp, at: point)
	}

	func crown(to offset: Double) {
		let delta = offset - lastCrownOffset
		lastCrownOffset = offset
		gea_watchos_crown(delta * Self.crownPointsPerUnit)
		tick()
	}

	private func tick() {
		guard gea_watchos_frame() != 0 else { return }
		frame = gea_watchos_copy_frame_image()
		syncCrown()
	}

	// Follows scrolls the Crown did not make (touch, momentum, range changes) so
	// the indicator stays true. A Crown turn already left the two in step, so
	// this writes only when they differ by a pixel or more.
	private func syncCrown() {
		var top = 0.0
		var maxTop = 0.0
		guard gea_watchos_scroll_metrics(&top, &maxTop) != 0 else { return }
		let unitsMax = Swift.max(maxTop / Self.crownPointsPerUnit, 1)
		if crownMax != unitsMax { crownMax = unitsMax }
		let units = top / Self.crownPointsPerUnit
		guard abs(units - lastCrownOffset) * Self.crownPointsPerUnit * Double(scale) >= 1 else { return }
		lastCrownOffset = units
		crownValue = units
	}
}

struct GeaWatchRootView: View {
	@StateObject private var host = GeaWatchHost()
	@Environment(\.scenePhase) private var scenePhase
	@FocusState private var crownFocused: Bool

	// The canvas covers the whole screen. watchOS's safe area keeps roughly a
	// fifth of the panel clear at the top and bottom, which is too much to give
	// up on a watch; apps that need the clock area free lay themselves out
	// around it, as on the round ESP32 watch panels.
	var body: some View {
		GeometryReader { geometry in
			Group {
				if let frame = host.frame {
					Image(decorative: frame, scale: host.scale)
						.resizable()
						.interpolation(.none)
				} else {
					Color.black
				}
			}
			.frame(width: geometry.size.width, height: geometry.size.height)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0, coordinateSpace: .local)
					.onChanged { host.drag(at: $0.location) }
					.onEnded { host.lift(at: $0.location) }
			)
			// The Crown only reaches a focused view, and focusable() must come
			// before digitalCrownRotation() or the rotation is never delivered.
			.focusable()
			.focusEffectDisabled()
			.focused($crownFocused)
			.digitalCrownRotation($host.crownValue, from: 0, through: host.crownMax, onChange: { host.crown(to: $0.offset) })
			.onAppear {
				host.start(size: geometry.size)
				host.setActive(scenePhase == .active)
				crownFocused = true
			}
		}
		.ignoresSafeArea()
		.onChange(of: scenePhase) { _, phase in host.setActive(phase == .active) }
	}
}
