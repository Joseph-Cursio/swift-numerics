//===--- ShiftTests.swift -------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import IntegerUtilities
import XCTest
import _TestSupport

final class IntegerUtilitiesShiftTests: XCTestCase {

  /// How a shift relates to rounding.
  enum ShiftKind: CaseIterable {
    /// `count <= 0`: a left shift (or none), which is always exact.
    case nonPositiveCount
    /// `count > 0` and no bits are lost.
    case exact
    /// `count > 0` and bits are lost, so the rounding rule applies.
    case inexact
  }

  /// The bit pattern of `x`, with leading zeros, for failure messages.
  func binary<T: FixedWidthInteger>(_ x: T) -> String {
    let digits = String(T.Magnitude(truncatingIfNeeded: x), radix: 2)
    return String(repeating: "0", count: T.bitWidth - digits.count) + digits
  }

  func testRoundingShift<T, C>(
    _ value: T, _ count: C, rounding rule: RoundingRule,
    checks: CheckCounter<ShiftKind>, replay: String
  ) where T: FixedWidthInteger, C: BinaryInteger {
    let floor = value >> count
    let lost = value &- floor << count
    let exact = count <= 0 || lost == 0
    let ceiling = exact ? floor : floor &+ 1
    let expected: T
    if exact { expected = floor }
    else {
      switch rule {
      case .down:
        expected = floor
      case .up:
        expected = ceiling
      case .towardZero:
        expected = value < 0 ? ceiling : floor
      case .awayFromZero:
        expected = value > 0 ? ceiling : floor
      case .toOdd:
        expected = floor | (exact ? 0 : 1)
      case .toNearestOrDown:
        let step = value.shifted(rightBy: count - 2, rounding: .toOdd)
        switch step & 0b11 {
        case 0b01: expected = floor
        case 0b10: expected = floor
        case 0b11: expected = ceiling
        default: preconditionFailure()
        }
      case .toNearestOrUp:
        let step = value.shifted(rightBy: count - 2, rounding: .toOdd)
        switch step & 0b11 {
        case 0b01: expected = floor
        case 0b10: expected = ceiling
        case 0b11: expected = ceiling
        default: preconditionFailure()
        }
      case .toNearestOrZero:
        let step = value.shifted(rightBy: count - 2, rounding: .toOdd)
        switch step & 0b11 {
        case 0b01: expected = floor
        case 0b10: expected = value > 0 ? floor : ceiling
        case 0b11: expected = ceiling
        default: preconditionFailure()
        }
      case .toNearestOrAway:
        let step = value.shifted(rightBy: count - 2, rounding: .toOdd)
        switch step & 0b11 {
        case 0b01: expected = floor
        case 0b10: expected = value > 0 ? ceiling : floor
        case 0b11: expected = ceiling
        default: preconditionFailure()
        }
      case .toNearestOrEven:
        let step = value.shifted(rightBy: count - 2, rounding: .toOdd)
        switch step & 0b11 {
        case 0b01: expected = floor
        case 0b10: expected = floor & 1 == 0 ? floor : ceiling
        case 0b11: expected = ceiling
        default: preconditionFailure()
        }
      case .requireExact:
        preconditionFailure()
      }
    }
    let observed = value.shifted(rightBy: count, rounding: rule)
    let kind: ShiftKind = count <= 0 ? .nonPositiveCount : exact ? .exact : .inexact
    checks.expectEqual(observed, expected, kind, """
      \(T.self)(\(value)).shifted(rightBy: \(count), rounding: .\(rule)): \
      expected \(expected), observed \(observed)
         value: \(binary(value))
      expected: \(binary(expected))
      observed: \(binary(observed))
      \(replay)
      """)
  }
    
    func testRoundingShift<T: FixedWidthInteger>(
      _ type: T.Type, rounding rule: RoundingRule
    ) {
      var rng = TestRandomNumberGenerator(label: "testRoundingShift \(T.self) \(rule)")
      let replay = rng.replayInstructions(filter: String(reflecting: Self.self))
      let checks = CheckCounter<ShiftKind>()
      for count in -2*T.bitWidth ... 2*T.bitWidth {
        // zero shifted by anything is always zero
        XCTAssertEqual(0, (0 as T).shifted(rightBy: count, rounding: rule))
        for _ in 0 ..< 100 {
          testRoundingShift(
            T.random(in: .min ... .max, using: &rng), count, rounding: rule,
            checks: checks, replay: replay)
        }
      }

      for count in Int8.min ... .max {
        testRoundingShift(
          T.random(in: .min ... .max, using: &rng), count, rounding: rule,
          checks: checks, replay: replay)
      }
      checks.require("\(T.self) \(rule)")
    }

    /// `.requireExact` traps on inexact shifts, so it gets only exact inputs.
    func testRequireExactShift<T: FixedWidthInteger>(_ type: T.Type) {
      var rng = TestRandomNumberGenerator(label: "testRequireExactShift \(T.self)")
      let replay = rng.replayInstructions(filter: String(reflecting: Self.self))
      let checks = CheckCounter<ShiftKind>()
      for count in -2*T.bitWidth ... 2*T.bitWidth {
        for _ in 0 ..< 100 {
          var value = T.random(in: .min ... .max, using: &rng)
          // Clear the bits that the shift would lose.
          if count > 0 { value = (value >> count) << count }
          testRoundingShift(
            value, count, rounding: .requireExact,
            checks: checks, replay: replay)
        }
      }
      checks.require(
        "\(T.self) requireExact", categories: [.nonPositiveCount, .exact])
    }

    func testRequireExactShifts() {
      testRequireExactShift(Int8.self)
      testRequireExactShift(UInt8.self)
      testRequireExactShift(Int.self)
      testRequireExactShift(UInt.self)
    }
    
    func testRoundingShifts() {
      testRoundingShift(Int8.self, rounding: .down)
      testRoundingShift(Int8.self, rounding: .up)
      testRoundingShift(Int8.self, rounding: .towardZero)
      testRoundingShift(Int8.self, rounding: .awayFromZero)
      testRoundingShift(Int8.self, rounding: .toNearestOrUp)
      testRoundingShift(Int8.self, rounding: .toNearestOrDown)
      testRoundingShift(Int8.self, rounding: .toNearestOrZero)
      testRoundingShift(Int8.self, rounding: .toNearestOrAway)
      testRoundingShift(Int8.self, rounding: .toNearestOrEven)
      testRoundingShift(Int8.self, rounding: .toOdd)
      
      testRoundingShift(UInt8.self, rounding: .down)
      testRoundingShift(UInt8.self, rounding: .up)
      testRoundingShift(UInt8.self, rounding: .towardZero)
      testRoundingShift(UInt8.self, rounding: .awayFromZero)
      testRoundingShift(UInt8.self, rounding: .toNearestOrUp)
      testRoundingShift(UInt8.self, rounding: .toNearestOrDown)
      testRoundingShift(UInt8.self, rounding: .toNearestOrZero)
      testRoundingShift(UInt8.self, rounding: .toNearestOrAway)
      testRoundingShift(UInt8.self, rounding: .toNearestOrEven)
      testRoundingShift(UInt8.self, rounding: .toOdd)
      
      testRoundingShift(Int.self, rounding: .down)
      testRoundingShift(Int.self, rounding: .up)
      testRoundingShift(Int.self, rounding: .towardZero)
      testRoundingShift(Int.self, rounding: .awayFromZero)
      testRoundingShift(Int.self, rounding: .toNearestOrUp)
      testRoundingShift(Int.self, rounding: .toNearestOrDown)
      testRoundingShift(Int.self, rounding: .toNearestOrZero)
      testRoundingShift(Int.self, rounding: .toNearestOrAway)
      testRoundingShift(Int.self, rounding: .toNearestOrEven)
      testRoundingShift(Int.self, rounding: .toOdd)
      
      testRoundingShift(UInt.self, rounding: .down)
      testRoundingShift(UInt.self, rounding: .up)
      testRoundingShift(UInt.self, rounding: .towardZero)
      testRoundingShift(UInt.self, rounding: .awayFromZero)
      testRoundingShift(UInt.self, rounding: .toNearestOrUp)
      testRoundingShift(UInt.self, rounding: .toNearestOrDown)
      testRoundingShift(UInt.self, rounding: .toNearestOrZero)
      testRoundingShift(UInt.self, rounding: .toNearestOrAway)
      testRoundingShift(UInt.self, rounding: .toNearestOrEven)
      testRoundingShift(UInt.self, rounding: .toOdd)
    }
  }
