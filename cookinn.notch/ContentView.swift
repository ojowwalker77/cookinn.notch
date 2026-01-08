//
//  ContentView.swift
//  cookinn.notch
//
//  Main content view for previewing
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NotchView()
            .background(Color.clear)
    }
}

#Preview {
    ContentView()
        .frame(width: 300, height: 60)
        .background(Color.gray.opacity(0.3))
}
