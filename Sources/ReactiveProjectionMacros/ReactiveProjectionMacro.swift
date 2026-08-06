import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import Foundation

struct ProjectionProperty {
    let name: String
    let keyPathExpr: String     // e.g. "\.title"
    let transformExpr: String?  // e.g. "{ $0 ?? \"\" }" or "ContactsDTO.make", nil if not provided
}

public struct ReactiveProjectionMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return []
        }

        let access = accessModifier(of: classDecl)
        let sourceTypeName = try extractSourceTypeName(from: node, in: context)
        let properties = findProjectedProperties(in: classDecl)

        // MARK: - Feature enum

        let cases = properties
            .map { "case \($0.name)" }
            .joined(separator: "\n")

        let featureEnum: DeclSyntax = """
        \(raw: access)enum Feature: CaseIterable {
            \(raw: cases)

            static let all: Set<Feature> = Set(Feature.allCases)
        }
        """

        // MARK: - Stored properties

        let cancellablesDecl: DeclSyntax = """
        private var cancellables = Set<AnyCancellable>()
        """

        // MARK: - init(item:features:)

        let assignments = properties
            .map { property -> String in
                let transform = property.transformExpr ?? "{ $0 }"
                return """
                self.\(property.name) = Projection((\(transform))(item[keyPath: \(property.keyPathExpr)]))
                """
            }
            .joined(separator: "\n")

        let bindings = properties
            .map { property -> String in
                let publisherExpr = "item.projection(for: \(property.keyPathExpr))"
                let mapped = property.transformExpr.map { transform in
                    "\(publisherExpr).map(\(transform)).eraseToAnyPublisher()"
                } ?? "\(publisherExpr).eraseToAnyPublisher()"

                return """
                if features.contains(.\(property.name)) {
                    bind(\(mapped), into: \\.\(property.name))
                }
                """
            }
            .joined(separator: "\n")

        let initDecl: DeclSyntax = """
        \(raw: access)init(item: \(raw: sourceTypeName), features: Set<Feature> = Feature.all) {
            \(raw: assignments)
            \(raw: bindings)
        }
        """

        // MARK: - bind helper

        let bindDecl: DeclSyntax = """
        private func bind<T>(
            _ publisher: some Publisher<T, Never>,
            into keyPath: ReferenceWritableKeyPath<\(raw: classDecl.name.text), Projection<T>>
        ) {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?[keyPath: keyPath].send(value)
                }
                .store(in: &cancellables)
        }
        """

        return [featureEnum, cancellablesDecl, initDecl, bindDecl]
    }

    // MARK: - source: argument parsing

    private static func extractSourceTypeName(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) throws -> String {

        guard
            case .argumentList(let arguments) = node.arguments,
            let sourceArg = arguments.first(where: { $0.label?.text == "source" })
        else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: ReactiveProjectionDiagnostic.missingSourceArgument
                )
            )
            throw MacroExpansionErrorMessage("Missing 'source' argument")
        }

        // Ожидаем `AGNote.self`
        if
            let memberAccess = sourceArg.expression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "self",
            let base = memberAccess.base
        {
            return base.trimmedDescription
        }

        context.diagnose(
            Diagnostic(
                node: sourceArg.expression,
                message: ReactiveProjectionDiagnostic.sourceMustBeTypeReference
            )
        )
        throw MacroExpansionErrorMessage("'source' must be a type reference, e.g. `AGNote.self`")
    }

    // MARK: - @Projected member scanning

    private static func findProjectedProperties(
        in classDecl: ClassDeclSyntax
    ) -> [ProjectionProperty] {

        var result: [ProjectionProperty] = []

        for member in classDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            guard
                let attribute = projectedAttribute(variable),
                let (keyPathExpr, transformExpr) = extractProjectedArguments(from: attribute)
            else {
                continue
            }

            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }

                result.append(
                    ProjectionProperty(
                        name: identifier.identifier.text,
                        keyPathExpr: keyPathExpr,
                        transformExpr: transformExpr
                    )
                )
            }
        }
        return result
    }

    private static func projectedAttribute(
        _ variable: VariableDeclSyntax
    ) -> AttributeSyntax? {
        for attribute in variable.attributes {
            guard let attribute = attribute.as(AttributeSyntax.self) else {
                continue
            }
            if attribute.attributeName.description == "Projected" {
                return attribute
            }
        }
        return nil
    }

    private static func extractProjectedArguments(
        from attribute: AttributeSyntax
    ) -> (keyPath: String, transform: String?)? {

        guard case .argumentList(let arguments) = attribute.arguments else {
            return nil
        }

        guard let keyPathArg = arguments.first(where: { $0.label == nil }) else {
            return nil
        }
        let keyPathExpr = keyPathArg.expression.trimmedDescription

        let transformExpr = arguments
            .first(where: { $0.label?.text == "transform" })
            .map { $0.expression.trimmedDescription }

        return (keyPathExpr, transformExpr)
    }

    // MARK: - access control

    private static func accessModifier(of classDecl: ClassDeclSyntax) -> String {
        let known: Set<String> = ["public", "internal", "fileprivate", "private", "open"]
        if let modifier = classDecl.modifiers.first(where: { known.contains($0.name.text) }) {
            // "open" классу не соответствует "open" member по умолчанию — сужаем до public
            return modifier.name.text == "open" ? "public " : "\(modifier.name.text) "
        }
        return ""
    }
}

enum ReactiveProjectionDiagnostic: String, DiagnosticMessage {
    case missingSourceArgument
    case sourceMustBeTypeReference

    var message: String {
        switch self {
        case .missingSourceArgument:
            return "Missing 'source' argument"
        case .sourceMustBeTypeReference:
            return "'source' must be a type reference, e.g. `AGNote.self`"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ReactiveProjectionMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}

@main
struct ReactiveProjectionPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ReactiveProjectionMacro.self,
        ProjectedMacro.self
    ]
}

