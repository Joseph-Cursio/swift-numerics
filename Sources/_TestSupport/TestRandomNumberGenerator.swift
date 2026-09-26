//===--- TestRandomNumberGenerator.swift ----------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(ucrt)
import ucrt
#endif

/// A seedable random number generator for tests (SplitMix64).
///
/// Each test process picks a fresh base seed, so every run still explores new
/// inputs. To replay a run, set `SWIFT_NUMERICS_TEST_SEED` to the base seed
/// printed in its failure messages.
///
/// A generator's stream depends only on the base seed and its label, so a test
/// replayed on its own with `swift test --filter` sees the same inputs it saw
/// in the full run.
public struct TestRandomNumberGenerator: RandomNumberGenerator {
  public static let baseSeed: UInt64 = {
    guard let raw = getenv("SWIFT_NUMERICS_TEST_SEED") else {
      return UInt64.random(in: .min ... .max)
    }
    let text = String(cString: raw)
    let value = text.hasPrefix("0x")
      ? UInt64(text.dropFirst(2), radix: 16)
      : UInt64(text)
    guard let value else {
      fatalError("SWIFT_NUMERICS_TEST_SEED must be a UInt64, got '\(text)'")
    }
    return value
  }()

  /// A line for failure messages that tells the reader how to replay them.
  public static func replayInstructions(filter: String) -> String {
    let seed = "0x" + String(baseSeed, radix: 16)
    return "Replay: SWIFT_NUMERICS_TEST_SEED=\(seed) swift test --filter \(filter)"
  }

  private var state: UInt64

  public init(label: String) {
    // FNV-1a, so that streams are stable across processes (unlike Hasher,
    // which is randomly seeded per process).
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in label.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    state = Self.baseSeed ^ hash
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z &>> 31)
  }
}
