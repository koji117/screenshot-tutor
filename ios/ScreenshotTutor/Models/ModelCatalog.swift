// ModelCatalog.swift
// The set of multimodal models we offer. These map to ready-made
// `ModelConfiguration` presets in MLX-VLM's `VLMRegistry`, which
// already point at the canonical mlx-community ports on Hugging
// Face. Adding a new VLM = add another entry that picks a
// `VLMRegistry` constant.
//
// Scoped to Gemma 4 only — the app is a screenshot tutor for the
// user's own study material, and the Gemma 4 family gives them
// parity with the web version's model choice. Other VLM families
// (Qwen, SmolVLM, PaliGemma) are intentionally omitted.

import Foundation
import MLXVLM
import MLXLMCommon

struct ModelEntry: Identifiable, Hashable {
    var id: String { configuration.name }
    let label: String
    let configuration: ModelConfiguration
    let approxSizeMB: Int
    let note: String

    static func == (lhs: ModelEntry, rhs: ModelEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ModelCatalog {
    static let entries: [ModelEntry] = [
        ModelEntry(
            label: "Gemma 4 E2B (4-bit)",
            configuration: VLMRegistry.gemma4_E2B_it_4bit,
            approxSizeMB: 1500,
            note: "Smaller and faster. Fits any iPad comfortably."
        ),
        ModelEntry(
            label: "Gemma 4 E4B (4-bit)",
            configuration: VLMRegistry.gemma4_E4B_it_4bit,
            approxSizeMB: 3000,
            note: "Best reading quality. Needs the increased-memory entitlement and an iPad with enough RAM (Air / Pro / mini 7+)."
        ),
    ]

    /// First-time default. E4B is the higher-quality option and is
    /// the right pick on devices with the increased-memory
    /// entitlement (paid Apple Developer signing + iPad Air / Pro /
    /// mini 7+ class hardware). Users can drop down to E2B from
    /// Settings or the empty-state picker if their device can't
    /// fit the heavier weights.
    static let defaultID: String = entries[1].id

    static func entry(id: String) -> ModelEntry? {
        entries.first { $0.id == id }
    }
}
