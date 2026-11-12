/// The shipped schema versions, pinned by hand: each one's fingerprint as the stores on
/// users' devices were written with it, keyed by its version identifier.
/// `SchemaMigrationTests` compares every version in `AppMigrationPlan.schemas` with its
/// row here. A shipped version is never edited, so this table only ever grows: a new
/// version adds its row, written out from its `@Model` classes, never copied from the
/// test's output.
enum ShippedSchema {
    static let fingerprints: [String: SchemaFingerprint] = [
        "1.0.0": SchemaFingerprint(
            version: "1.0.0",
            entities: [
                SchemaFingerprint.Entity(
                    name: "TodoRecord",
                    attributes: [
                        attribute("createdAt", "Foundation.Date"),
                        uniqueAttribute("id", "Foundation.UUID"),
                        attribute("isDone", "Swift.Bool"),
                        attribute("title", "Swift.String"),
                    ],
                    relationships: [],
                    uniquenessConstraints: [["id"]],
                ),
            ],
        ),
    ]

    /// A stored, non-optional attribute with no uniqueness constraint, no transformer or
    /// coding, and no rename or hash modifier.
    private static func attribute(_ name: String, _ type: String) -> SchemaFingerprint.Attribute {
        stored(name, type, isUnique: false)
    }

    /// The same, under `@Attribute(.unique)`.
    private static func uniqueAttribute(
        _ name: String,
        _ type: String,
    ) -> SchemaFingerprint.Attribute {
        stored(name, type, isUnique: true)
    }

    private static func stored(
        _ name: String,
        _ type: String,
        isUnique: Bool,
    ) -> SchemaFingerprint.Attribute {
        SchemaFingerprint.Attribute(
            name: name,
            originalName: "",
            type: type,
            isOptional: false,
            isUnique: isUnique,
            isTransient: false,
            isTransformable: false,
            isCodable: false,
            hashModifier: nil,
        )
    }
}
