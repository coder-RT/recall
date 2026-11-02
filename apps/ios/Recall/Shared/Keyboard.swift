import UIKit

/// Tapping anywhere outside a text field hides the keyboard, on every screen. While the keyboard is up (and only
/// then), one tap recognizer sits on the key window: it never cancels touches (buttons, rows and chips still get their
/// tap) and ignores taps inside a text field or text view (so tapping into a field still edits it). With no keyboard
/// on screen nothing is attached, so the rest of the app, and its accessibility, are untouched.
@MainActor
final class KeyboardDismissal: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissal()
    private var tap: UITapGestureRecognizer?
    private var observing = false

    /// Starts listening for the keyboard (once).
    func install() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardShown() {
        guard tap == nil, let window = keyWindow() else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        tap = recognizer
    }

    @objc private func keyboardHidden() {
        if let tap { tap.view?.removeGestureRecognizer(tap) }
        tap = nil
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated {
            var view = touch.view
            while let v = view {  // a tap in a field (or its clear button) keeps the keyboard
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
