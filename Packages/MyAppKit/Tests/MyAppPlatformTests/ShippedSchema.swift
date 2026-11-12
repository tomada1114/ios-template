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

    /// A non-optional attribute with no uniqueness constraint.
    private static func attribute(_ name: String, _ type: String) -> SchemaFingerprint.Attribute {
        SchemaFingerprint.Attribute(name: name, type: type, isOptional: false, isUnique: false)
    }

    /// A non-optional `@Attribute(.unique)` attribute.
    private static func uniqueAttribute(
        _ name: String,
        _ type: String,
    ) -> SchemaFingerprint.Attribute {
        SchemaFingerprint.Attribute(name: name, type: type, isOptional: false, isUnique: true)
    }
}
