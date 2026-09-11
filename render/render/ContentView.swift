//
//  ContentView.swift
//  render
//
//  Created by Kavi Sekhon on 2026-09-04.
//

import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var player: AVPlayer?
    @State private var isImporterPresented = false
    @State private var currentFileName: String?
    @State private var errorMessage: String?
    @State private var accessedURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
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

                if let currentFileName {
                    Text(currentFileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .frame(minWidth: 640, minHeight: 400)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .onDisappear { releaseAccess() }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func load(url: URL) {
        releaseAccess()

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access \(url.lastPathComponent)."
            return
        }
        accessedURL = url

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        currentFileName = url.lastPathComponent
        newPlayer.play()
    }

    private func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}

#Preview {
    ContentView()
}
