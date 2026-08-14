import XCTest

@testable import EasyBarCtl

final class SemanticVersionTests: XCTestCase {
  func testParserAcceptsCanonicalSemanticVersions() throws {
    XCTAssertEqual(try XCTUnwrap(SemanticVersion("1.2.3")).description, "1.2.3")
    XCTAssertEqual(
      try XCTUnwrap(SemanticVersion("1.2.3-alpha.1+build.7")).description,
      "1.2.3-alpha.1+build.7"
    )
  }

  func testParserRejectsMalformedSemanticVersions() {
    let invalidVersions = [
      "",
      "1.2",
      "1.2.3-",
      "1.2.3-alpha..1",
      "1.2.3+",
      "1.2.3+build..1",
      "01.2.3",
      "1.02.3",
      "1.2.03",
      "1.2.3-01",
      "1.2.3-alpha_beta",
      " 1.2.3",
      "1.2.3 ",
    ]

    for version in invalidVersions {
      XCTAssertNil(SemanticVersion(version), version)
    }
  }

  func testPrereleaseOrderingFollowsSemanticVersionPrecedence() throws {
    let versions = try [
      "1.0.0-alpha",
      "1.0.0-alpha.1",
      "1.0.0-alpha.beta",
      "1.0.0-beta",
      "1.0.0-beta.2",
      "1.0.0-beta.11",
      "1.0.0-rc.1",
      "1.0.0",
    ].map { try XCTUnwrap(SemanticVersion($0)) }

    XCTAssertEqual(versions.sorted(), versions)
  }

  func testHugeNumericPrereleaseIdentifiersCompareWithoutIntegerOverflow() throws {
    let lower = try XCTUnwrap(SemanticVersion("1.0.0-999999999999999999999999999999"))
    let higher = try XCTUnwrap(SemanticVersion("1.0.0-1000000000000000000000000000000"))

    XCTAssertLessThan(lower, higher)
  }

  func testBuildMetadataDoesNotAffectPrecedence() throws {
    let first = try XCTUnwrap(SemanticVersion("1.2.3+build.1"))
    let second = try XCTUnwrap(SemanticVersion("1.2.3+build.2"))

    XCTAssertEqual(first, second)
    XCTAssertFalse(first < second)
    XCTAssertFalse(second < first)
  }

  func testVersionConstraintsRejectLegacyEqualsPrefix() {
    XCTAssertNil(VersionConstraint("=1.2.3"))
    XCTAssertNil(VersionConstraint("==1.2.3"))
    XCTAssertNil(VersionConstraint(" 1.2.3"))
    XCTAssertNil(VersionConstraint("^1.2.3 "))
  }

  func testCaretConstraintsRemainSafeAtIntegerLimits() throws {
    let maximum = String(Int.max)
    let majorConstraint = try XCTUnwrap(VersionConstraint("^\(maximum).0.0"))
    let minorConstraint = try XCTUnwrap(VersionConstraint("^0.\(maximum).0"))
    let patchConstraint = try XCTUnwrap(VersionConstraint("^0.0.\(maximum)"))

    XCTAssertTrue(
      majorConstraint.contains(try XCTUnwrap(SemanticVersion("\(maximum).1.0")))
    )
    XCTAssertTrue(
      minorConstraint.contains(try XCTUnwrap(SemanticVersion("0.\(maximum).1")))
    )
    XCTAssertTrue(
      patchConstraint.contains(try XCTUnwrap(SemanticVersion("0.0.\(maximum)")))
    )
  }
}
