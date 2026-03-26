//
//  ContextBorderView.swift
//  cookinn.notch
//
//  Extracted ContextBorder with cached path computation
//  Progress indicator around the pill
//

import SwiftUI

struct ContextBorderView: View {
    let percent: Double
    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        // Use trim on the pill shape for smooth progress
        PillBorderPath(cornerRadius: cornerRadius)
            .trim(from: 0, to: min(percent / 100, 1.0))
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .animation(.easeInOut(duration: 0.3), value: percent)
    }
}

// Shape that traces the pill border (left side rounded, right side flat)
// Path is computed once per size change and cached by SwiftUI
struct PillBorderPath: Shape {
    let cornerRadius: CGFloat

    // Cache key for SwiftUI's shape caching
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()

        let r = min(cornerRadius, rect.height / 2)
        let w = rect.width
        let h = rect.height

        // Start at top-left corner (top of the arc)
        path.move(to: CGPoint(x: r, y: 0))

        // Top edge (left to right)
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right edge (top to bottom) - no corner radius
        path.addLine(to: CGPoint(x: w, y: h))

        // Bottom edge (right to left)
        path.addLine(to: CGPoint(x: r, y: h))

        // Bottom-left corner arc
        path.addArc(
            center: CGPoint(x: r, y: h - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge (bottom to top)
        path.addLine(to: CGPoint(x: 0, y: r))

        // Top-left corner arc
        path.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        return path
    }
}
