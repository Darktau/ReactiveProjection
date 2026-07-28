import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest


#if canImport(ReactiveProjectionMacros)
@testable import ReactiveProjectionMacros

let testMacros: [String: Macro.Type] = [
    "ReactiveProjection": ReactiveProjectionMacro.self,
    "Projected": ProjectedMacro.self
]

final class ReactiveProjectionTests: XCTestCase {
    func testProjectedProperties() {
        assertMacroExpansion(
"""
@ReactiveProjection(source: AGNote.self)
final class Person {

  @Projected(\\.name, transform: { $0 ?? "" })
  var name: ProjectedValue<String>

  @Projected(\\.contacts, transform: ContactsDTO.make)
  var Contacts: ProjectedValue<[ContactDTO]>

}
""",
        expandedSource:
"""
""",
        macros: testMacros
        )
    }
}
#endif
