//===--- CheckCounter.swift -----------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest

/// Counts how often each category of check actually ran, so that a test can
/// fail when a category it means to cover never runs (compare QuickCheck's
/// `cover`).
final class CheckCounter {
  private(set) var counts: [String: Int] = [:]

  func record(_ category: String) {
    counts[category, default: 0] += 1
  }

  func require(
    _ categories: [String], atLeast minimum: Int = 1, _ context: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for category in categories where counts[category, default: 0] < minimum {
      XCTFail("""
        \(context): "\(category)" checks ran \(counts[category, default: 0]) \
        times, expected at least \(minimum) (counts: \(counts))
        """, file: file, line: line)
    }
  }
}
