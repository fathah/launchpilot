import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView(selection: Binding(
                get: { state.selectedSection },
                set: { state.setSection($0) }
            ))
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            if appState.projects.isEmpty {
                await appState.bootstrap()
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { appState.lastError = nil }
            },
            message: {
                Text(appState.lastError ?? "")
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .projects:
            ProjectsRouter()
        case .builds:
            BuildsView()
        case .releases:
            PlaceholderView(
                title: "Releases",
                subtitle: "Release artifacts and upload status will appear here.",
                symbol: "shippingbox"
            )
        case .credentials:
            PlaceholderView(
                title: "Credentials",
                subtitle: "Apple, Google Play, and keystore credentials are coming next.",
                symbol: "key"
            )
        case .settings:
            SettingsView()
        }
    }
}

private struct ProjectsRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.hasProjects {
            WelcomeView()
        } else if let project = appState.selectedProject {
            ProjectDetailView(project: project)
        } else {
            ProjectsListView()
        }
    }
}
