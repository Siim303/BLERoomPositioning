//
//  RoomView.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 27.02.2025.
//
// Adjusted RoomView that centers via updating contentOffset
import SwiftUI
import CoreGraphics

struct RoomView: View {
    let position: CGPoint?            // The user/device position in design space.
    let beacons: [BLEDevice]          // Beacon positions (also in design coordinates).
    let mapImageName: String          // Name of the background map image.
    let designSize: CGSize            // e.g., CGSize(width: 1000, height: 1000)
    let worldScale: CGFloat

    // Now tracking the UIScrollView properties.
    @State private var contentOffset: CGPoint = .zero
    @State private var zoomScale: CGFloat = 1.0

    // Auto-center toggle.
    @State private var autoCenter: Bool = false

    var body: some View {
        GeometryReader { geo in
            // Compute the base scale that maps design space into available view.
            let baseScale = min(geo.size.width / designSize.width,
                                geo.size.height / designSize.height)
            
            // Build the design container.
            let designContainer = ZStack {
                Image(mapImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: designSize.width, height: designSize.height)
                
                // Grid overlay on top of the map.
                GridOverlay(spacing: 1 * worldScale, designSize: (CGSize(width: designSize.width, height: designSize.height)))
                
                ForEach(beacons) { beacon in
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 20, height: 20)
                        Text(beacon.name)
                            .foregroundColor(.white)
                            .font(.caption)
                            .bold()
                    }
                    .position(beacon.position)
                }
                if let pos = position {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                        .position(pos)
                        .animation(Animation.easeInOut(duration: 0.1), value: pos)
                }
            }
            .frame(width: designSize.width, height: designSize.height, alignment: .topLeading)
            
            // Only scale the container to fit the design space.
            let transformedContainer = designContainer
                .scaleEffect(baseScale, anchor: .topLeading)
            
            // Pass the bindings into ZoomableScrollView.
            ZoomableScrollView(designSize: designSize, contentOffset: $contentOffset, zoomScale: $zoomScale, maximumZoom: (designSize.height / worldScale / 2)) {
                ZStack(alignment: .topLeading) {
                    transformedContainer
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .onChange(of: position) { _, newPosition in
                    if autoCenter, newPosition != nil {
                        centerOnUser(using: geo, baseScale: baseScale)
                    }
                }
            }
            .overlay(
                ZStack {
                    // -------- Add‑Beacon overlay --------
                    AddBeaconOverlay(
                        contentOffset: $contentOffset,
                        zoomScale:     $zoomScale,
                        baseScale:      baseScale,
                        designSize:     designSize
                    )   // ⬅️ the overlay itself will load / save JSON internally
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                autoCenter.toggle()
                                if autoCenter { centerOnUser(using: geo, baseScale: baseScale) }
                            }) {
                                Image(systemName: autoCenter ? "location.fill" : "location")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(autoCenter ? Color.blue : Color.gray)
                                    .clipShape(Circle())
                            }
                            .padding()
                        }
                    }
                }
            )
        }
    }

    /// Centers the scroll view on the user by updating contentOffset.
    private func centerOnUser(using geo: GeometryProxy, baseScale: CGFloat) {
        guard let userPosition = position else { return }
        
        //let originShiftX = designSize.width          // same padding.x
        //let originShiftY = designSize.height
        
        // Calculate the user's position in scaled content coordinates.
        let scaledUserX = userPosition.x * zoomScale * baseScale
        let scaledUserY = userPosition.y * zoomScale * baseScale
        //let scaledUserX = userPosition.x * zoomScale * baseScale + originShiftX
        //let scaledUserY = userPosition.y * zoomScale * baseScale + originShiftY
        
        let viewCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        // UIScrollView's contentOffset is defined by the top-left visible point.
        let newOffset = CGPoint(x: scaledUserX - viewCenter.x, y: scaledUserY - viewCenter.y)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            contentOffset = newOffset
        }
    }
}
