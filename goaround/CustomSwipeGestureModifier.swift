import SwiftUI
import UIKit

struct CustomSwipeGestureModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SwipeGestureView())
    }
}

struct SwipeGestureView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view = UIView()
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let swipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleSwipe))
        swipeGesture.direction = .right
        swipeGesture.delegate = context.coordinator
        uiViewController.view.addGestureRecognizer(swipeGesture)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func handleSwipe() {
            // カスタムアクション
            print("Swipe detected")
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let location = touch.location(in: gestureRecognizer.view)
            let height = gestureRecognizer.view?.bounds.height ?? 0
            return location.y > height * 0.4 && location.y < height * 0.6
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
}

extension View {
    func customSwipeGesture() -> some View {
        self.modifier(CustomSwipeGestureModifier())
    }
}
