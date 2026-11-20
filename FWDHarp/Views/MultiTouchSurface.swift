import SwiftUI
import UIKit

/// A touch surface that follows every finger on it, for the pads and the strum plate.
///
/// UIKit rather than SwiftUI gestures, for the reason FWD Sequencer's keyboard found
/// (KeyboardTouchSurface.swift): a SwiftUI drag that is taken away mid-touch ends
/// without telling anyone, so a pad would stay held. UIKit reports every touch's whole
/// life, cancellations included, and a surface leaving the screen ends its touches.
struct MultiTouchSurface: UIViewRepresentable {
    let onBegan: (ObjectIdentifier, CGPoint) -> Void
    let onMoved: (ObjectIdentifier, CGPoint) -> Void
    let onEnded: (ObjectIdentifier) -> Void

    func makeUIView(context: Context) -> MultiTouchView {
        let view = MultiTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isExclusiveTouch = false
        update(view)
        return view
    }

    func updateUIView(_ view: MultiTouchView, context: Context) {
        update(view)
    }

    static func dismantleUIView(_ view: MultiTouchView, coordinator: ()) {
        view.endAll()
    }

    private func update(_ view: MultiTouchView) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
    }
}

final class MultiTouchView: UIView {
    var onBegan: (ObjectIdentifier, CGPoint) -> Void = { _, _ in }
    var onMoved: (ObjectIdentifier, CGPoint) -> Void = { _, _ in }
    var onEnded: (ObjectIdentifier) -> Void = { _ in }

    private var active: Set<ObjectIdentifier> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            active.insert(id)
            onBegan(id, touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where active.contains(ObjectIdentifier(touch)) {
            onMoved(ObjectIdentifier(touch), touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if active.remove(id) != nil { onEnded(id) }
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { endAll() }
    }

    /// End every touch still down: the surface is going away mid-touch.
    func endAll() {
        for id in active { onEnded(id) }
        active.removeAll()
    }
}
