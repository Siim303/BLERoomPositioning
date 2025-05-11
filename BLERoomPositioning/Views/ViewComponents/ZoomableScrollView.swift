// Updated ZoomableScrollView with double-tap gesture using corrected coordinate conversion:
import SwiftUI

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    @Binding var contentOffset: CGPoint
    @Binding var zoomScale: CGFloat
    let maximumZoom: CGFloat
    let designSize: CGSize
    let autoCenter: Bool

    init(
        designSize: CGSize,
        contentOffset: Binding<CGPoint>,
        zoomScale: Binding<CGFloat>,
        maximumZoom: CGFloat,
        autoCenter: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.designSize = designSize
        self._contentOffset = contentOffset
        self._zoomScale = zoomScale
        self.maximumZoom = maximumZoom
        self.autoCenter = autoCenter
        self.content = content()
    }
    // NEW helper so RoomView can ask for the padding value later
    private var padding: CGSize {                 // 1× map on each side
        CGSize(width: designSize.width, height: designSize.height)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        
        // — zoom configuration —
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maximumZoom
        scrollView.bouncesZoom = true
        
        // — allow overscroll bounce —
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true

        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        // ① total scrollable pasture = map (designSize) + padding*2
        //let pasture = CGSize(width: designSize.width  * 3,
        //                     height: designSize.height * 3)
        //scrollView.contentSize = pasture
        scrollView.contentSize = scrollView.bounds.size        // ← same as before

        
        // ② place the hosted map view at (padding.x, padding.y)
        //let hostView = context.coordinator.hostingController.view!
        //hostView.frame = CGRect(origin: CGPoint(x: padding.width,
        //                                        y: padding.height),
        //                        size: designSize)
        // no autoresizing masks
        //scrollView.addSubview(hostView)

        //
        // ③ start with map centred in viewport
        //scrollView.contentOffset = CGPoint(x: padding.width - scrollView.bounds.width/2 + designSize.width/2,
        //                                   y: padding.height - scrollView.bounds.height/2 + designSize.height/2)
        // … add double‑tap gesture …
    
        // Add double-tap gesture recognizer for zooming.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        
        let hostedView = context.coordinator.hostingController.view!
        hostedView.frame = scrollView.bounds
        //hostedView.frame = CGRect(origin: .zero, size: designSize)
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        //hostedView.autoresizingMask = []
        scrollView.addSubview(hostedView)
        
        /// Optional: disable gestures while autocentered
        scrollView.isScrollEnabled = !autoCenter
        scrollView.panGestureRecognizer.isEnabled = !autoCenter
        /// Disable zoom while autocentered
        //scrollView.pinchGestureRecognizer?.isEnabled = !autoCenter
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // update rootView
        context.coordinator.hostingController.rootView = content

        // keep contentSize in sync with current zoom
        let scaledSize = CGSize(width: designSize.width  * uiView.zoomScale,
                                height: designSize.height * uiView.zoomScale)
        if uiView.contentSize != scaledSize {
            uiView.contentSize = scaledSize
        }
        
        if uiView.contentOffset != contentOffset {
            if !autoCenter {
                uiView.setContentOffset(contentOffset, animated: true)
            } else {
                UIView.animate(withDuration: 0.3) {
                    uiView.setContentOffset(contentOffset, animated: false)
                }
            }
        }
        if uiView.zoomScale != zoomScale {
            uiView.setZoomScale(zoomScale, animated: true)
        }
        /// Disable gestures onUpdate
        uiView.isScrollEnabled = !autoCenter
        uiView.panGestureRecognizer.isEnabled = !autoCenter
        //uiView.pinchGestureRecognizer?.isEnabled = !autoCenter
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hostingController: UIHostingController(rootView: content),
            contentOffset: $contentOffset,
            zoomScale: $zoomScale)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>
        var contentOffset: Binding<CGPoint>
        var zoomScale: Binding<CGFloat>

        init(
            hostingController: UIHostingController<Content>,
            contentOffset: Binding<CGPoint>,
            zoomScale: Binding<CGFloat>
        ) {
            self.hostingController = hostingController
            self.contentOffset = contentOffset
            self.zoomScale = zoomScale
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            DispatchQueue.main.async {
                self.contentOffset.wrappedValue = scrollView.contentOffset
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            DispatchQueue.main.async {
                self.zoomScale.wrappedValue = scrollView.zoomScale
            }
        }

        // Handle double-tap gesture to zoom in/out with correct centering.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            // Convert the tap location into the content view's coordinate system.
            let pointInContent = gesture.location(in: hostingController.view)
            let newZoomScale: CGFloat
            if scrollView.zoomScale < scrollView.maximumZoomScale {
                newZoomScale = min(
                    scrollView.zoomScale * 2, scrollView.maximumZoomScale)
            } else {
                newZoomScale = scrollView.minimumZoomScale
            }
            let zoomRect = self.zoomRect(
                for: newZoomScale, center: pointInContent,
                scrollView: scrollView)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        // Compute the zoom rectangle given the new scale and center in content coordinates.
        func zoomRect(
            for scale: CGFloat, center: CGPoint, scrollView: UIScrollView
        ) -> CGRect {
            var zoomRect = CGRect.zero
            zoomRect.size.height = scrollView.bounds.size.height / scale
            zoomRect.size.width = scrollView.bounds.size.width / scale
            zoomRect.origin.x = center.x - zoomRect.size.width / 2.0
            zoomRect.origin.y = center.y - zoomRect.size.height / 2.0
            return zoomRect
        }
    }
}
