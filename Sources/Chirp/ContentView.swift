import SwiftUI

struct ContentView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        ChatWebView(appState: appState)
            .frame(minWidth: 900, minHeight: 600)
            .ignoresSafeArea()
            // Surface re-auth prompt when session expires mid-use
            .overlay(alignment: .top) {
                if appState.requiresAuth {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Session expired — sign in to continue")
                            .font(.callout)
                        Spacer()
                        Button("Dismiss") { appState.requiresAuth = false }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
    }
}
