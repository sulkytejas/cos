import Foundation
import SwiftData
import os

/// Coordinates Gemini-generated chapter icons. The look we ask for: a sparse
/// editorial line drawing in deep ink (#0d141a) on pure white, hairline
/// strokes only, centered with whitespace. Designed to harmonize with the
/// italic-serif glyph it replaces.
enum IconGenerator {
    static let log = Logger(subsystem: "com.atlas.app", category: "IconGenerator")

    /// Generates icons for every chapter without a cached one, or whose
    /// cached prompt no longer matches the current title.
    @MainActor
    static func generateMissing(in context: ModelContext) async {
        guard GeminiClient.apiKey != nil else {
            log.info("skipping: no API key set")
            return
        }
        let descriptor = FetchDescriptor<Chapter>()
        guard let chapters = try? context.fetch(descriptor) else { return }
        for chapter in chapters where needsIcon(chapter) {
            _ = await regenerate(chapter, in: context)
        }
    }

    /// Always regenerates (used when the user taps a refresh button or
    /// renames a chapter). Returns nil on success, or an error string.
    @discardableResult
    @MainActor
    static func regenerate(_ chapter: Chapter, in context: ModelContext) async -> String? {
        let prompt = prompt(for: chapter)
        log.info("→ \(chapter.title, privacy: .public)")
        do {
            let raw = try await GeminiClient.generateImage(prompt: prompt)
            // Trim the heavy whitespace margin Gemini leaves around its subject
            // so the stored blob renders at the right size in the constellation
            // + small chapter glyph.
            let bytes = IconCropping.croppedPNGData(raw) ?? raw
            chapter.iconData = bytes
            chapter.iconSourceTitle = chapter.title
            chapter.touch()
            do {
                try context.save()
                log.info("✓ \(chapter.title, privacy: .public) — saved \(bytes.count) bytes")
                return nil
            } catch {
                log.error("save failed for \(chapter.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return "save failed: \(error.localizedDescription)"
            }
        } catch {
            log.error("✗ \(chapter.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    static func needsIcon(_ c: Chapter) -> Bool {
        if c.iconData == nil { return true }
        if c.iconSourceTitle != c.title { return true }
        return false
    }

    /// Clears all cached icons so the next `generateMissing` regenerates them
    /// (used after a prompt change so the user can re-roll).
    @MainActor
    static func clearAllIcons(in context: ModelContext) {
        let descriptor = FetchDescriptor<Chapter>()
        guard let chapters = try? context.fetch(descriptor) else { return }
        for c in chapters {
            c.iconData = nil
            c.iconSourceTitle = nil
        }
        try? context.save()
        log.info("cleared all icons (\(chapters.count) chapters)")
    }

    /// The pictogram prompt. Important: phrasing skews toward "icon" / "mark"
    /// rather than "illustration" or "drawing" — Gemini interprets those
    /// differently. We also push HARD on the negative constraints (no text,
    /// no scenes) because the model loves to add them otherwise.
    private static func prompt(for chapter: Chapter) -> String {
        let subject = chapter.title
        return """
        Create a single bold pictogram — one iconic black symbol on a pure \
        white background. The mark should be as confident and impactful as \
        an italic serif letterform: one gesture, no fuss.

        Subject to symbolize (translate into a single recognizable icon, \
        not a scene): \(subject)

        STYLE — Noun Project icon meets sumi-e brushstroke. Thick confident \
        strokes 6–10 pixels wide, deep ink black (#0d141a) on pure white. \
        Geometric, clean, monoline silhouette.

        ABSOLUTE RULES (the image MUST follow these — failure to follow \
        means the image is wrong):
        • NO text, NO letters, NO words, NO writing, NO labels
        • NO scenery, NO landscapes, NO backgrounds
        • NO people, NO faces, NO figures
        • NO multiple objects — ONE central symbol only
        • NO fine detail, NO hatching, NO shading, NO gradients
        • NO color — only black ink on white

        LAYOUT — Subject centered in a 1024×1024 square. Massive whitespace \
        around the symbol so it feels like a single impactful mark, not a \
        crowded illustration. The symbol should occupy roughly the middle \
        50% of the canvas.
        """
    }
}
