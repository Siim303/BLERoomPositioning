//
//  GridOverlay.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 09.04.2025.
//
import SwiftUI

struct GridOverlay: View {
    /// Spacing in design units (1.0 = 1 m)
    let spacing: CGFloat
    let designSize: CGSize

    var body: some View {
        ZStack {
            // Vertical lines.
            ForEach(0...Int(ceil(designSize.width / spacing)), id: \.self) { i in
                Path { path in
                    let x = CGFloat(i) * spacing
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: designSize.height))
                }
                .stroke(Color.gray.opacity(0.6), lineWidth: 0.94)
            }
            // Horizontal lines.
            ForEach(0...Int(ceil(designSize.height / spacing)), id: \.self) { i in
                Path { path in
                    let y = CGFloat(i) * spacing
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: designSize.width, y: y))
                }
                .stroke(Color.gray.opacity(0.6), lineWidth: 0.94)
            }
        }
        .frame(width: designSize.width, height: designSize.height)
    }
}
