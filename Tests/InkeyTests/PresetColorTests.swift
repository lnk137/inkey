import AppKit
import Testing
@testable import Inkey

@Suite("Preset color management", .serialized)
@MainActor
struct PresetColorTests {
    @Test func deletionCompactsToolsAndShrinksTheToolbarWithoutChangingInk() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let custom = try #require(palette.subviews.compactMap { $0 as? SwatchButton }.first { $0.isCustom })
            let eraser = try #require(palette.subviews.compactMap { $0 as? ToolButton }.first { $0.reorderGroup == nil && $0.onRightClick != nil })
            palette.choose(2)
            let ink = palette.current
            let originalWidth = palette.bounds.width
            palette.deletePreset(2)
            #expect(palette.current == ink)
            #expect(palette.bounds.width < originalWidth)
            #expect(eraser.frame.minX - custom.frame.maxX == 8)
            while !palette.colors.isEmpty { palette.deletePreset(0) }
            #expect(palette.bounds.width == 240)
            #expect(eraser.frame.minX - custom.frame.maxX == 8)
            #expect(palette.bounds.contains(custom.frame) && palette.bounds.contains(eraser.frame))
            #expect(palette.subviews.filter { !$0.isHidden }.allSatisfy { palette.bounds.contains($0.frame) })
        }
    }
}
