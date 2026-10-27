import AppKit
import Testing
@testable import Inkey

@Suite("Preset color management", .serialized)
@MainActor
struct PresetColorTests {
    @Test func plusAddsASeventhPresetInOnePickerAndSelectsIt() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let plus = try #require(palette.subviews.compactMap { $0 as? SwatchButton }.first { $0.isCustom })
            #expect(plus.action == #selector(PaletteView.addColor))
            _ = palette.makeColorPopover(purpose: .add)
            let picker = try #require(palette.popover?.contentViewController as? ColorPanelController)
            #expect(picker.purpose == .add)
            #expect(picker.view.subviews.compactMap { $0 as? NSButton }.filter {
                $0.action == #selector(ColorPanelController.cancel) || $0.action == #selector(ColorPanelController.addPreset)
            }.map(\.title) == ["取消", "添加"])
            picker.hexField.stringValue = "#123456"
            let add = try #require(picker.view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "添加" })
            add.performClick(nil)
            #expect(palette.popover == nil && palette.colors.count == 7)
            #expect(palette.current == InkColor("123456") && palette.slot == 6)
            #expect(preferences.ink(dark: false)?.slot == 6)
            #expect(palette.bounds.height == 118 && palette.bounds.width == 320)
            #expect(palette.subviews.filter { !$0.isHidden }.allSatisfy { palette.bounds.contains($0.frame) })
            let seventh = try #require(palette.subviews.compactMap { $0 as? SwatchButton }.first { $0.reorderGroup == "colors" && $0.tag == 6 })
            #expect(seventh.toolTip?.contains("⌥") == false)
            let restored = PaletteView(frame: .zero, preferences: preferences)
            restored.paperIsDark = false; restored.refreshAppearance()
            #expect(restored.colors == palette.colors && restored.slot == 6 && restored.current == palette.current)
        }
    }

    @Test func cancellingOrClickingOutsideAddPickerRestoresInkAndPresets() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let original = palette.colors
            palette.choose(2)
            let ink = palette.current
            for outside in [false, true] {
                _ = palette.makeColorPopover(purpose: .add)
                let picker = try #require(palette.popover?.contentViewController as? ColorPanelController)
                picker.update(InkColor("ABCDEF"), syncSquare: true)
                #expect(palette.current == InkColor("ABCDEF"))
                if outside { palette.closePicker(accept: true) }
                else { picker.cancelOperation(nil) }
                #expect(palette.popover == nil && palette.current == ink && palette.colors == original)
            }
            _ = palette.makeColorPopover(purpose: .add)
            let picker = try #require(palette.popover?.contentViewController as? ColorPanelController)
            picker.hexField.stringValue = "invalid"
            picker.addPreset()
            #expect(palette.hasPopover && palette.colors == original)
            picker.cancel()
        }
    }

    @Test func additionalRowsPersistAndCompactAfterDeletionAndKeepShortcuts() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            for index in 0..<7 { palette.addPreset(InkColor(String(format: "%06X", 0x123400 + index))) }
            #expect(palette.colors.count == 13 && palette.bounds.height == 156)
            #expect(palette.subviews.filter { !$0.isHidden }.allSatisfy { palette.bounds.contains($0.frame) })
            let restored = PaletteView(frame: .zero, preferences: preferences)
            restored.paperIsDark = false; restored.refreshAppearance()
            #expect(restored.colors == palette.colors && restored.slot == 12)
            restored.paperIsDark = true; restored.refreshAppearance()
            #expect(restored.colors == InkColor.dark && restored.bounds.height == 80)
            restored.paperIsDark = false; restored.refreshAppearance()
            #expect(restored.colors.count == 13 && restored.slot == 12)
            while palette.colors.count > 6 { palette.deletePreset(palette.colors.count - 1) }
            #expect(palette.bounds.size == NSSize(width: 320, height: 80))
            for index in 0..<6 {
                palette.choose(index)
                #expect(palette.current == InkColor.light[index])
            }
            let before = palette.colors
            palette.addPreset(palette.colors[2])
            #expect(palette.colors == before && palette.slot == 2)
        }
    }

    @Test func presetsReorderAcrossRowsAndCancelledDragsRestoreBothAxes() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            for index in 0..<3 { palette.addPreset(InkColor(String(format: "%06X", 0x123400 + index))) }
            let buttons = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }.sorted { $0.tag < $1.tag }
            let before = palette.colors
            let frames = buttons.map(\.frame)
            let source = buttons[8]
            let start = NSPoint(x: source.frame.midX, y: source.frame.midY)
            let target = NSPoint(x: buttons[0].frame.midX, y: buttons[0].frame.midY)
            palette.beginReordering(source, at: start)
            palette.updateReordering(at: target)
            palette.cancelActiveGesture()
            #expect(buttons.map(\.frame) == frames && palette.colors == before)
            palette.beginReordering(source, at: start)
            palette.endReordering(at: target)
            #expect(palette.colors == [before[8]] + Array(before.prefix(8)))
            #expect(source.tag == 0 && palette.slot == 0 && palette.current == before[8])
            #expect(source.frame == frames[0])
            let dropBack = NSPoint(x: frames[8].midX, y: frames[8].midY)
            palette.beginReordering(source, at: target)
            palette.endReordering(at: dropBack)
            #expect(palette.colors == before && source.tag == 8 && palette.slot == 8)
        }
    }
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
            #expect(palette.bounds.width == 272)
            #expect(eraser.frame.minX - custom.frame.maxX == 8)
            #expect(palette.bounds.contains(custom.frame) && palette.bounds.contains(eraser.frame))
            #expect(palette.subviews.filter { !$0.isHidden }.allSatisfy { palette.bounds.contains($0.frame) })
        }
    }
}
