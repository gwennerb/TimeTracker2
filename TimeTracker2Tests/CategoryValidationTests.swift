//
//  CategoryValidationTests.swift
//  TimeTracker2Tests
//

import Testing
import SwiftUI
@testable import TimeTracker2

struct CategoryValidationTests {
    @Test func colorPaletteFallsBackToGrayForUnknownKey() async throws {
        let category = Category(name: "Anything", colorName: "doesNotExist",
                                iconSymbol: "app.fill", order: 0)
        #expect(category.color == .gray)
    }

    @Test func colorPaletteResolvesKnownKey() async throws {
        let category = Category(name: "App", colorName: "blue",
                                iconSymbol: "app.fill", order: 0)
        #expect(category.color == .blue)
    }

    @Test func iconPaletteContainsSeedSymbols() async throws {
        for symbol in ["app.fill", "globe", "building.2.fill", "ellipsis.circle.fill"] {
            #expect(Category.iconPalette.contains(symbol),
                    "Seed icon \(symbol) must remain in the curated palette so migration produces stable output")
        }
    }
}
