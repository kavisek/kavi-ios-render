//
//  ContentView.swift
//  render
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model: VideoPlayerModel
    @State private var isImporterPresented = false
    @State private var isFilterPanelPresented = false

    init(model: VideoPlayerModel = VideoPlayerModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let player = model.player {
                PlayerView(player: player)
                    .background(Color.black)
            } else {
                ContentUnavailableView(
                    "No Video Selected",
                    systemImage: "film",
                    description: Text("Choose an .mp4 file to start playing.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.02))
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Open Video…", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)

                if let currentFileName = model.currentFileName {
                    Text(currentFileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Toggle(isOn: $isFilterPanelPresented) {
                    Label("Filters", systemImage: "camera.filters")
                }
                .toggleStyle(.button)
                .tint(model.isFilterEnabled ? .accentColor : nil)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .accessibilityIdentifier("filtersButton")
            }
            .padding(10)
        }
        .frame(minWidth: 640, minHeight: 400)
        .inspector(isPresented: $isFilterPanelPresented) {
            FilterPanel(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            model.handleImportResult(result)
        }
        .onDisappear { model.unload() }
    }
}

#Preview {
    ContentView()
}
