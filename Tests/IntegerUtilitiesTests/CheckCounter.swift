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

/// Makes checks and counts how many of each category ran, so that a test can
/// fail when a category it means to cover never runs (compare QuickCheck's
/// `cover`).
///
/// A check is counted when `expectEqual` makes it, so a check that is skipped
/// is not counted.
final class CheckCounter<Category: Hashable & CaseIterable> {
  private var counts: [Category: Int] = [:]

  /// Checks that `observed == expected`, counting the check under `category`.
  func expectEqual<T: Equatable>(
    _ observed: T, _ expected: T, _ category: Category,
    _ message: @autoclosure () -> String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    counts[category, default: 0] += 1
    if observed != expected {
      XCTFail(message(), file: file, line: line)
    }
  }

  /// Fails unless each of `categories` (by default, every category) has been
  /// checked at least `minimum` times.
  func require(
    _ context: @autoclosure () -> String,
    categories: [Category] = Array(Category.allCases),
    atLeast minimum: Int = 1,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for category in categories where counts[category, default: 0] < minimum {
      XCTFail("""
        \(context()): \(category) checks ran \(counts[category, default: 0]) \
        times, expected at least \(minimum) (counts: \(counts))
        """, file: file, line: line)
    }
  }
}
