// HuggingFaceBridge.swift
// Manual replacements for the `#hubDownloader()` and
// `#huggingFaceTokenizerLoader()` macros that ship in MLXHuggingFace.
//
// Why inline these instead of depending on MLXHuggingFace? The macro
// plugin in mlx-swift-lm requires explicit user trust on first build
// in Xcode, and a failed/untrusted macro plugin manifests as
// "Missing package product" errors across the *entire* package — not
// just the macro target. Implementing the bridges by hand removes
// MLXHuggingFace from the dependency graph and avoids that whole
// failure mode.
//
// The implementations below are direct ports of the macro expansions
// in mlx-swift-lm/Libraries/MLXHuggingFaceMacros/*.swift — they wrap
// `HuggingFace.HubClient` (from huggingface/swift-huggingface) and
// `Tokenizers.AutoTokenizer` (from huggingface/swift-transformers)
// to satisfy the `MLXLMCommon.Downloader` and
// `MLXLMCommon.TokenizerLoader` protocols.

import Foundation
import MLXLMCommon
import HuggingFace
import Tokenizers

enum HFBridgeError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        }
    }
}

/// Bridges `HuggingFace.HubClient` to `MLXLMCommon.Downloader`.
struct HFDownloader: MLXLMCommon.Downloader {
    private let upstream: HuggingFace.HubClient

    init(_ upstream: HuggingFace.HubClient = HuggingFace.HubClient()) {
        self.upstream = upstream
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Foundation.Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw HFBridgeError.invalidRepositoryID(id)
        }
        return try await upstream.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
    }
}

/// Adapts a `Tokenizers.Tokenizer` to `MLXLMCommon.Tokenizer`.
private struct HFTokenizerAdapter: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    // swift-transformers spells the parameter `tokens:` rather than `tokenIds:`.
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

/// Loads tokenizers from `Tokenizers.AutoTokenizer` and adapts them
/// to `MLXLMCommon.Tokenizer`.
struct HFTokenizerLoader: MLXLMCommon.TokenizerLoader {
    init() {}

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return HFTokenizerAdapter(upstream: upstream)
    }
}

/// On-disk cache management for HuggingFace-downloaded models.
/// Mirrors the standard `~/.cache/huggingface/hub` layout that
/// `HubClient` writes into — repository directory is named
/// `models--<namespace>--<name>` under the cache root, with a sibling
/// `.metadata/...` entry. Both are removed on delete so the next
/// download is a fresh fetch.
enum HFCacheManager {
    /// Bytes consumed on disk by the given repo, or 0 if not cached.
    static func sizeOnDisk(repoID id: String) -> Int64 {
        guard let dir = repoDirectory(for: id) else { return 0 }
        return directorySize(at: dir)
    }

    /// Whether anything from the given repo is on disk.
    static func isDownloaded(repoID id: String) -> Bool {
        guard let dir = repoDirectory(for: id) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Remove the repo's directory and its sibling metadata entry.
    /// Safe to call when nothing is cached (becomes a no-op).
    static func deleteModel(repoID id: String) throws {
        let cache = HuggingFace.HubClient().cache
        guard let cache, let parsedID = HuggingFace.Repo.ID(rawValue: id) else { return }
        let repoDir = cache.repoDirectory(repo: parsedID, kind: .model)
        let metaDir = cache.metadataDirectory(repo: parsedID, kind: .model)
        try? FileManager.default.removeItem(at: repoDir)
        try? FileManager.default.removeItem(at: metaDir)
    }

    private static func repoDirectory(for id: String) -> URL? {
        guard let cache = HuggingFace.HubClient().cache,
              let parsedID = HuggingFace.Repo.ID(rawValue: id)
        else { return nil }
        return cache.repoDirectory(repo: parsedID, kind: .model)
    }

    /// Recursively sum the size of regular files under `url`.
    private static func directorySize(at url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                let size = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? 0
                total += Int64(size)
            }
        }
        return total
    }
}
