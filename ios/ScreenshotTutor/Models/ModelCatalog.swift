// ModelCatalog.swift
// The set of multimodal models we know how to load via MLX-VLM. Each
// entry maps to a Hugging Face repo id under the `mlx-community`
// namespace; quantized 4-bit ports are picked by default since they
// fit comfortably on iPad RAM.
//
// Adding a model: append a `ModelEntry` below. Anything supported by
// MLXVLM's `VLMModelFactory` works; the factory inspects the repo's
// config.json to pick the right architecture.

import Foundation
import MLXVLM
import MLXLMCommon

struct ModelEntry: Identifiable, Hashable {
    var id: String { huggingFaceID }
    let label: String
    let huggingFaceID: String
    let approxSizeMB: Int
    let note: String

    /// Convert to MLXLMCommon's `ModelConfiguration` consumed by
    /// `VLMModelFactory.loadContainer`.
    var configuration: ModelConfiguration {
        ModelConfiguration(id: huggingFaceID)
    }
}

enum ModelCatalog {
    static let entries: [ModelEntry] = [
        ModelEntry(
            label: "Qwen2-VL 2B (4-bit)",
            huggingFaceID: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
            approxSizeMB: 1500,
            note: "Strong general VLM. Good first pick on any iPad."
        ),
        ModelEntry(
            label: "SmolVLM 500M",
            huggingFaceID: "mlx-community/SmolVLM-500M-Instruct-bf16",
            approxSizeMB: 1000,
            note: "Smaller, faster. Lower quality on dense text."
        ),
        ModelEntry(
            label: "PaliGemma 3B (4-bit)",
            huggingFaceID: "mlx-community/paligemma-3b-mix-448-8bit",
            approxSizeMB: 3500,
            note: "Document-tuned. Best for textbook pages and dense diagrams."
        ),
    ]

    static let defaultModelID = entries[0].huggingFaceID
}
