//
//  DeltaView.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 09.04.2025.
//

/*
import SwiftUI
import CoreGraphics

// I think this class is not used!!!

struct DeltaView: View {
    // Define the design coordinate system in meters.
    // The original image is 3909 x 4096 px and 1 m = 40 px.
    // So, designSize is (3909/40) x (4096/40)
    let designSize: CGSize = CGSize(width: 3909 / 40.0,
                                    height: 4096 / 40.0)
    
    // For interactive pan and zoom.
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero      // user-provided offset
    @State private var lastOffset: CGSize = .zero    // stores last offset
    
    var body: some View {
        GeometryReader { geo in
            // Compute a base scale that maps the design space into the available view.
            let baseScale = min(geo.size.width / designSize.width,
                                geo.size.height / designSize.height)
            
            // Compute an initial centering offset so that the design container is centered in the view.
            let initialOffset = CGSize(
                width: (geo.size.width - designSize.width * baseScale) / 2,
                height: (geo.size.height - designSize.height * baseScale) / 2
            )
            
            // The overall (final) offset is the initialOffset plus any user-applied offset.
            let finalOffset = CGSize(
                width: initialOffset.width + offset.width,
                height: initialOffset.height + offset.height
            )
            
            // The design container: map image and grid overlay.
            let designContainer = ZStack(alignment: .topLeading) {
                // The underlying map image.
                Image("Delta_2korrus")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Draw the image using the design coordinate dimensions.
                    .frame(width: designSize.width, height: designSize.height)
                
                // Overlay the grid. Here, spacing = 1.0 in design units.
                GridOverlay(spacing: 1.0, designSize: designSize)
                
                // Example marker (optional): Place a marker at the center of the design space.
                /*
                Circle()
                    .fill(Color.red)
                    .frame(width: 0.2, height: 0.2)  // Marker size in design units
                    .position(CGPoint(x: designSize.width/2, y: designSize.height/2))
                */
            }
            .frame(width: designSize.width, height: designSize.height, alignment: .topLeading)
            
            // Apply the unified transformation: scale and then offset.
            let transformedContainer = designContainer
                .scaleEffect(currentScale * baseScale, anchor: .topLeading)
                .offset(finalOffset)
            
            // Wrap the transformed container in a container that fills the available area.
            ZStack(alignment: .topLeading) {
                transformedContainer
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            // Attach pan and zoom gestures.
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        },
                    MagnificationGesture()
                        .onChanged { value in
                            currentScale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = currentScale
                        }
                )
            )
        }
        .ignoresSafeArea()  // Uncomment if you want true full-screen.
    }
}
*/
