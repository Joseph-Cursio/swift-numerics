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
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported platform")
#endif

/// A seedable random number generator for tests (SplitMix64).
///
/// Each test process picks a fresh base seed, so every run explores new
/// inputs. A generator's stream depends on the base seed, its label, and how
/// many generators with that label the process created before it, so a test
/// repeated within one process (as Xcode's "Run Repeatedly" does) also gets
/// new inputs each time.
///
/// Each generator has a `replaySeed`: in a new process with
/// `SWIFT_NUMERICS_TEST_SEED` set to that value, the first generator created
/// with the same label reproduces its stream, so rerunning just the failing
/// test replays it. Every replay seed is written to standard error when it is
/// first used, so it is available even if the test later traps.
public struct TestRandomNumberGenerator: RandomNumberGenerator {
  /// The value of `SWIFT_NUMERICS_TEST_SEED` that reproduces this
  /// generator's stream when the test is rerun on its own.
  public let replaySeed: UInt64

  private var state: UInt64

  public init(label: String) {
    let occurrence = Registry.shared.nextOccurrence(of: label)
    // mix(0) == 0, so the first generator with a label uses the base seed.
    replaySeed = Self.baseSeed ^ Self.mix(UInt64(occurrence))
    Registry.shared.announce(replaySeed)
    // FNV-1a, so that streams are stable across processes (unlike Hasher,
    // which is randomly seeded per process).
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in label.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    state = replaySeed ^ hash
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    return Self.mix(state)
  }

  /// A line for failure messages that tells the reader how to rerun `filter`
  /// with this generator's stream.
  public func replayInstructions(filter: String) -> String {
    "Replay: " + Self.replayCommand(seed: replaySeed, filter: filter)
  }

  static func replayCommand(seed: UInt64, filter: String) -> String {
    let seed = "0x" + String(seed, radix: 16)
    #if os(Windows)
    return "$env:SWIFT_NUMERICS_TEST_SEED=\"\(seed)\"; swift test --filter \(filter)"
    #else
    return "SWIFT_NUMERICS_TEST_SEED=\(seed) swift test --filter \(filter)"
    #endif
  }

  /// The SplitMix64 output function.
  private static func mix(_ x: UInt64) -> UInt64 {
    var z = x
    z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z &>> 31)
  }

  /// SWIFT_NUMERICS_TEST_SEED (decimal or 0x-prefixed hex, surrounding
  /// whitespace ignored) if it is set and not empty, otherwise a fresh
  /// random value.
  private static let baseSeed: UInt64 = {
    guard let raw = environmentVariable("SWIFT_NUMERICS_TEST_SEED"),
          let first = raw.firstIndex(where: { !$0.isWhitespace }),
          let last = raw.lastIndex(where: { !$0.isWhitespace }) else {
      return UInt64.random(in: .min ... .max)
    }
    let text = raw[first ... last].lowercased()
    let value = text.hasPrefix("0x")
      ? UInt64(text.dropFirst(2), radix: 16)
      : UInt64(text)
    guard let value else {
      fatalError("SWIFT_NUMERICS_TEST_SEED must be a UInt64, got '\(raw)'")
    }
    return value
  }()

  /// Per-process bookkeeping. Test methods run one at a time within a
  /// process, so this state needs no locking.
  private final class Registry: @unchecked Sendable {
    static let shared = Registry()
    private var occurrences: [String: Int] = [:]
    private var announced: Set<UInt64> = []

    func nextOccurrence(of label: String) -> Int {
      defer { occurrences[label, default: 0] += 1 }
      return occurrences[label, default: 0]
    }

    func announce(_ seed: UInt64) {
      guard announced.insert(seed).inserted else { return }
      let command = TestRandomNumberGenerator.replayCommand(
        seed: seed, filter: "<test>")
      writeToStandardError(
        "TestRandomNumberGenerator: to replay a failing test, run \(command)\n")
    }
  }
}

private func environmentVariable(_ name: String) -> String? {
  #if os(Windows)
  // getenv is deprecated in the Windows CRT.
  var count = 0
  var pointer: UnsafeMutablePointer<CChar>? = nil
  withUnsafeMutablePointer(to: &pointer) { buffer in
    _ = _dupenv_s(buffer, &count, name)
  }
  defer { if let pointer { free(pointer) } }
  guard count > 0, let pointer else { return nil }
  return String(cString: pointer)
  #else
  guard let value = getenv(name) else { return nil }
  return String(cString: value)
  #endif
}

/// Writes `message` to standard error unbuffered, so that it is not lost if
/// the process traps afterwards.
private func writeToStandardError(_ message: String) {
  #if os(Windows)
  fputs(message, stderr)
  #else
  var message = message
  message.withUTF8 { bytes in
    _ = write(2, bytes.baseAddress, bytes.count)
  }
  #endif
}
