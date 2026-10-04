//
//  FilterPanel.swift
//  render
//

import SwiftUI

/// Inspector for the CRT filter: on/off, presets, and every parameter.
struct FilterPanel: View {
    @Bindable var model: VideoPlayerModel

    private static let customTag = "custom"

    var body: some View {
        Form {
            Section {
                Toggle("CRT Filter", isOn: $model.isFilterEnabled)
                    .accessibilityIdentifier("crtFilterToggle")

                Picker("Preset", selection: presetSelection) {
                    ForEach(CRTPreset.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    if model.matchingPreset == nil {
                        Divider()
                        Text("Custom").tag(Self.customTag)
                    }
                }
                .accessibilityIdentifier("crtPresetPicker")
            }

            ForEach(CRTSettings.Section.allCases) { section in
                Section(section.rawValue) {
                    ForEach(section.parameters) { parameter in
                        ParameterSlider(parameter: parameter, settings: $model.crtSettings)
                    }
                }
            }
            .disabled(!model.isFilterEnabled)

            Section {
                Button("Reset to \(model.basePreset.name)") {
                    model.resetToBasePreset()
                }
                .disabled(model.crtSettings == model.basePreset.settings)
            }
        }
        .formStyle(.grouped)
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: { model.matchingPreset?.id ?? Self.customTag },
            set: { id in
                guard let preset = CRTPreset.all.first(where: { $0.id == id }) else { return }
                model.applyPreset(preset)
            }
        )
    }
}

private struct ParameterSlider: View {
    let parameter: CRTSettings.Parameter
    @Binding var settings: CRTSettings

    var body: some View {
        LabeledContent {
            HStack {
                slider
                Text(parameter.format(settings[parameter]))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(parameter.title)
        }
        .accessibilityIdentifier("crt.\(parameter.rawValue)")
    }

    @ViewBuilder private var slider: some View {
        let value = Binding(get: { settings[parameter] }, set: { settings[parameter] = $0 })
        if let step = parameter.step {
            Slider(value: value, in: parameter.range, step: step)
        } else {
            Slider(value: value, in: parameter.range)
        }
    }
}

#Preview {
    FilterPanel(model: VideoPlayerModel())
        .frame(width: 320, height: 700)
}
