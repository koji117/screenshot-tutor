// ModelCatalog.swift
// The set of multimodal models we offer. These map to ready-made
// `ModelConfiguration` presets in MLX-VLM's `VLMRegistry`, which
// already point at the canonical mlx-community ONNX-style ports on
// Hugging Face. Adding a new VLM = add another entry that picks a
// `VLMRegistry` constant.

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
            label: "Qwen2-VL 2B (4-bit)",
            configuration: VLMRegistry.qwen2VL2BInstruct4Bit,
            approxSizeMB: 1500,
            note: "Strong general VLM. Good first pick on any iPad."
        ),
        ModelEntry(
            label: "SmolVLM (4-bit)",
            configuration: VLMRegistry.smolvlminstruct4bit,
            approxSizeMB: 1100,
            note: "Smaller, faster. Lower quality on dense text."
        ),
        ModelEntry(
            label: "Gemma 4 E2B (4-bit)",
            configuration: VLMRegistry.gemma4_E2B_it_4bit,
            approxSizeMB: 1500,
            note: "Native MLX port of the web app's e2b model. Strong reading."
        ),
        ModelEntry(
            label: "Gemma 4 E4B (4-bit)",
            configuration: VLMRegistry.gemma4_E4B_it_4bit,
            approxSizeMB: 3000,
            note: "Best reading quality. Heavier — comfortable on iPad Pro/Air."
        ),
        ModelEntry(
            label: "Qwen2.5-VL 3B (4-bit)",
            configuration: VLMRegistry.qwen2_5VL3BInstruct4Bit,
            approxSizeMB: 2200,
            note: "Newer Qwen with stronger document understanding."
        ),
        ModelEntry(
            label: "PaliGemma 3B (8-bit)",
            configuration: VLMRegistry.paligemma3bMix448_8bit,
            approxSizeMB: 3500,
            note: "Document-tuned. Best for textbook pages and dense diagrams."
        ),
    ]

    static let defaultID: String = entries[0].id

    static func entry(id: String) -> ModelEntry? {
        entries.first { $0.id == id }
    }
}
