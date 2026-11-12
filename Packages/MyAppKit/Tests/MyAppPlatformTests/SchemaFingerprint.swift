import SwiftData

/// The stored shape of one schema version, as SwiftData reads it from the version's
/// `@Model` classes: what a store on a user's device was written with, and so what a
/// shipped version must keep describing. `SchemaMigrationTests` pins each shipped
/// version's fingerprint as a literal in `ShippedSchema`.
///
/// Swift names that never reach the store are deliberately absent, so renaming them
/// changes nothing here: the schema's and the plan's type names, the app's module names
/// (a bootstrap renames them), and a record's methods.
struct SchemaFingerprint: Equatable, CustomStringConvertible {
    struct Entity: Equatable {
        var name: String
        var attributes: [Attribute]
        var relationships: [Relationship]
        var uniquenessConstraints: [[String]]
    }

    /// Everything `Schema.Attribute` exposes about how the attribute is stored.
    struct Attribute: Equatable {
        var name: String
        /// The name the attribute had in the version before, for a renaming migration;
        /// SwiftData answers an empty string when there is none.
        var originalName: String
        /// The Swift type with the app's module names and the enclosing schema type
        /// removed: `Foundation.UUID` and `Swift.String` keep their module, and a
        /// `Status` enum nested in the schema reads `Status`, under any module or schema
        /// name. Generic arguments are normalized the same way (`Swift.Optional<Status>`).
        var type: String
        var isOptional: Bool
        var isUnique: Bool
        /// Not stored at all (`@Transient`).
        var isTransient: Bool
        var isTransformable: Bool
        var isCodable: Bool
        var hashModifier: String?
    }

    /// Everything `Schema.Relationship` exposes about how the relationship is stored.
    struct Relationship: Equatable {
        var name: String
        var originalName: String
        /// The destination entity's name.
        var destination: String
        var isToOne: Bool
        var isOptional: Bool
        var isUnique: Bool
        /// `Schema.Relationship.DeleteRule`'s raw value: `noAction`, `nullify`,
        /// `cascade`, or `deny`.
        var deleteRule: String
        var inverseName: String?
        var minimumModelCount: Int?
        var maximumModelCount: Int?
        var hashModifier: String?
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
        var flags: [String] = []
        if isOptional {
            flags.append("optional")
        }
        if isUnique {
            flags.append("unique")
        }
        if isTransient {
            flags.append("transient")
        }
        if isTransformable {
            flags.append("transformable")
        }
        if isCodable {
            flags.append("codable")
        }
        if !originalName.isEmpty {
            flags.append("originalName \(originalName)")
        }
        if let hashModifier {
            flags.append("hashModifier \(hashModifier)")
        }
        return "  \(name): \(type) \(flags)"
    }
}

extension SchemaFingerprint.Relationship: CustomStringConvertible {
    var description: String {
        let cardinality = isToOne ? "to-one" : "to-many"
        let counts = "\(minimumModelCount.map(String.init) ?? "nil")..."
            + (maximumModelCount.map(String.init) ?? "nil")
        let inverse = inverseName ?? "nil"
        let hash = hashModifier ?? "nil"
        let flags = "optional \(isOptional), unique \(isUnique), originalName \(originalName)"
        return "  \(name) -> \(destination) \(cardinality) \(deleteRule) inverse \(inverse) "
            + "count \(counts) hashModifier \(hash), \(flags)"
    }
}

extension SchemaFingerprint {
    /// Reads `version`'s fingerprint through `Schema(versionedSchema:)`, the same schema
    /// ``MyAppPlatform/PersistenceStore`` hands a `ModelContainer`. Entities and their
    /// properties come out sorted by name: SwiftData keeps attributes in a `Set`.
    init(_ version: any VersionedSchema.Type) {
        let schema = Schema(versionedSchema: version)
        let names = TypeNames(version)
        self.init(
            version: "\(schema.version)",
            entities: schema.entities.sorted { $0.name < $1.name }.map { entity in
                Entity(entity, names: names)
            },
        )
    }
}

extension SchemaFingerprint.Entity {
    init(_ entity: Schema.Entity, names: TypeNames) {
        self.init(
            name: entity.name,
            attributes: entity.attributes.sorted { $0.name < $1.name }.map { attribute in
                SchemaFingerprint.Attribute(
                    name: attribute.name,
                    originalName: attribute.originalName,
                    type: names.normalized(attribute.valueType),
                    isOptional: attribute.isOptional,
                    isUnique: attribute.isUnique,
                    isTransient: attribute.isTransient,
                    isTransformable: attribute.isTransformable,
                    isCodable: attribute.isCodable,
                    hashModifier: attribute.hashModifier,
                )
            },
            relationships: entity.relationships.sorted { $0.name < $1.name }.map { relationship in
                SchemaFingerprint.Relationship(
                    name: relationship.name,
                    originalName: relationship.originalName,
                    destination: relationship.destination,
                    isToOne: relationship.isToOneRelationship,
                    isOptional: relationship.isOptional,
                    isUnique: relationship.isUnique,
                    deleteRule: relationship.deleteRule.rawValue,
                    inverseName: relationship.inverseName,
                    minimumModelCount: relationship.minimumModelCount,
                    maximumModelCount: relationship.maximumModelCount,
                    hashModifier: relationship.hashModifier,
                )
            },
            uniquenessConstraints: entity.uniquenessConstraints,
        )
    }
}
