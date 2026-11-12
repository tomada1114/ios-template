import SwiftData

/// The stored shape of one schema version, as SwiftData reads it from the version's
/// `@Model` classes: what a store on a user's device was written with, and so what a
/// shipped version must keep describing. `SchemaMigrationTests` pins each shipped
/// version's fingerprint as a literal.
///
/// Swift names that never reach the store — the schema's and the plan's type names, a
/// record's methods — are deliberately absent, so renaming them changes nothing here.
struct SchemaFingerprint: Equatable, CustomStringConvertible {
    struct Entity: Equatable {
        var name: String
        var attributes: [Attribute]
        var relationships: [Relationship]
        var uniquenessConstraints: [[String]]
    }

    struct Attribute: Equatable {
        var name: String
        /// The fully qualified Swift type, such as `Foundation.UUID`.
        var type: String
        var isOptional: Bool
        var isUnique: Bool
    }

    struct Relationship: Equatable {
        var name: String
        var destination: String
        var isOptional: Bool
    }

    var version: String
    var entities: [Entity]

    var description: String {
        var lines = ["version \(version)"]
        for entity in entities {
            lines.append("\(entity.name) unique: \(entity.uniquenessConstraints)")
            lines += entity.attributes.map(\.description)
            lines += entity.relationships.map(\.description)
        }
        return lines.joined(separator: "\n")
    }
}

extension SchemaFingerprint.Attribute: CustomStringConvertible {
    var description: String {
        let optional = isOptional ? "?" : ""
        let unique = isUnique ? " unique" : ""
        return "  \(name): \(type)\(optional)\(unique)"
    }
}

extension SchemaFingerprint.Relationship: CustomStringConvertible {
    var description: String {
        let optional = isOptional ? "?" : ""
        return "  \(name) -> \(destination)\(optional)"
    }
}

extension SchemaFingerprint {
    /// Reads `version`'s fingerprint through `Schema(versionedSchema:)`, the same schema
    /// ``MyAppPlatform/PersistenceStore`` hands a `ModelContainer`. Entities and their
    /// properties come out sorted by name: SwiftData keeps attributes in a `Set`.
    init(_ version: any VersionedSchema.Type) {
        let schema = Schema(versionedSchema: version)
        self.init(
            version: "\(schema.version)",
            entities: schema.entities.sorted { $0.name < $1.name }.map(Entity.init),
        )
    }
}

extension SchemaFingerprint.Entity {
    init(_ entity: Schema.Entity) {
        self.init(
            name: entity.name,
            attributes: entity.attributes.sorted { $0.name < $1.name }.map { attribute in
                SchemaFingerprint.Attribute(
                    name: attribute.name,
                    type: String(reflecting: attribute.valueType),
                    isOptional: attribute.isOptional,
                    isUnique: attribute.isUnique,
                )
            },
            relationships: entity.relationships.sorted { $0.name < $1.name }.map { relationship in
                SchemaFingerprint.Relationship(
                    name: relationship.name,
                    destination: relationship.destination,
                    isOptional: relationship.isOptional,
                )
            },
            uniquenessConstraints: entity.uniquenessConstraints,
        )
    }
}
