//
//  ContentView.swift
//  render
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ContentView: View {
    @State private var model: VideoPlayerModel
    @State private var isImporterPresented = false
    @State private var isFilterPanelPresented = false
    #if os(iOS)
    @State private var photoSelection: PhotosPickerItem?
    #endif

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
                openButtons

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
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 400)
        #endif
        .inspector(isPresented: $isFilterPanelPresented) {
            FilterPanel(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                // On iPhone the inspector becomes a sheet; half height keeps
                // the video visible while tuning.
                .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            model.handleImportResult(result)
        }
        #if os(iOS)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            Task { await model.loadMovie(from: item) }
        }
        #endif
        .onDisappear { model.unload() }
    }

    /// Mac: one "Open Video…" button (Cmd+O). iOS/iPadOS: Files and Photos,
    /// since that's where videos usually live on iPhone and iPad.
    @ViewBuilder private var openButtons: some View {
        #if os(macOS)
        Button {
            isImporterPresented = true
        } label: {
            Label("Open Video…", systemImage: "folder")
        }
        .keyboardShortcut("o", modifiers: .command)
        #else
        Button {
            isImporterPresented = true
        } label: {
            Label("Files", systemImage: "folder")
        }
        .keyboardShortcut("o", modifiers: .command)
        .accessibilityIdentifier("openFilesButton")

        PhotosPicker(selection: $photoSelection, matching: .videos, preferredItemEncoding: .current) {
            Label("Photos", systemImage: "photo.on.rectangle")
        }
        .accessibilityIdentifier("openPhotosButton")
        #endif
    }
}

#Preview {
    ContentView()
}
