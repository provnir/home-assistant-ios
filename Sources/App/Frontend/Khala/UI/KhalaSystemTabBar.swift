import SFSafeSymbols
import SwiftUI
import UIKit

/// iOS 26+: the screen's sections on the SYSTEM tab bar — a standalone `UITabBar` (no `UITabBarController`), so
/// UIKit draws all of it: the floating Liquid Glass platter, the selection capsule, press-and-drag scrubbing with
/// the lens following the finger, its morph and its haptics (Nir, build 24.1: "Bottom tabs don't use the Liquid
/// Glass animation/sliding feature"). Nothing of ours is drawn behind or over it.
///
/// It only reports selections (`UITabBarDelegate`); it hosts no content, so it serves a lifted Home Assistant page
/// (one web view under all its tabs) as well as a device screen. A selection made elsewhere (the page reporting
/// its tab) is set on `selectedItem` and the system moves its capsule.
///
/// Sources (SCREENS-IMPL.md "System tab bar"): WWDC25 "Build a UIKit app with the new design" (tab bars adopt
/// Liquid Glass and float on iPhone); Apple Developer Forums 791643 (a standalone `UITabBar` gets the glass, but
/// the scroll-edge blur under it is `UITabBarController`'s doing — `UIScrollEdgeElementContainerInteraction` for
/// custom setups); 821539 (the selected capsule is the system's mandatory indicator under Liquid Glass).
@available(iOS 26.0, *)
struct KhalaSystemTabBar: UIViewRepresentable {
    let tabs: [KhalaSubTab]
    @Binding var selection: Int
    let accent: Color
    /// The animation a selection made on the bar is applied with, so the screen's section transitions with it.
    let motion: Animation

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, motion: motion)
    }

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        bar.setContentHuggingPriority(.required, for: .vertical)
        apply(to: bar, coordinator: context.coordinator)
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.motion = motion
        apply(to: bar, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView bar: UITabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? bar.window?.bounds.width ?? 390
        let fitted = bar.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height))
        return CGSize(width: width, height: fitted.height)
    }

    private func apply(to bar: UITabBar, coordinator: Coordinator) {
        bar.tintColor = UIColor(accent)
        if coordinator.tabs != tabs {
            coordinator.tabs = tabs
            let items = tabs.enumerated().map { index, tab in
                UITabBarItem(title: tab.title, image: UIImage(systemName: tab.symbol.rawValue), tag: index)
            }
            bar.setItems(items, animated: false)
        }
        guard let items = bar.items, !items.isEmpty else { return }
        let wanted = items[min(max(selection, 0), items.count - 1)]
        if bar.selectedItem !== wanted {
            bar.selectedItem = wanted
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>
        var motion: Animation
        var tabs: [KhalaSubTab] = []

        init(selection: Binding<Int>, motion: Animation) {
            self.selection = selection
            self.motion = motion
        }

        /// A tap, or the end of a drag across the bar: the system has already moved its capsule.
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard item.tag != selection.wrappedValue else { return }
            withAnimation(motion) {
                selection.wrappedValue = item.tag
            }
        }
    }
}
