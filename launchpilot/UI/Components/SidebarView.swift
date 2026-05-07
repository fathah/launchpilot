import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: SidebarSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }

            if appState.hasProjects && selection == .projects {
                Section("Recent") {
                    ForEach(appState.projects.prefix(8)) { project in
                        Button {
                            appState.selectProject(project)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(project.name)
                                    .lineLimit(1)
                                Spacer()
                                if project.id == appState.selectedProjectId {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppConstants.appName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.addProjectFromPicker() }
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .help("Add a project folder")
            }
        }
    }
}
