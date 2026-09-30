# SwiftFormat and SwiftLint agreement

Read from [SKILL.md's `.swiftformat` section](../SKILL.md#swiftformat) before changing
`--decimalgrouping`, `number_separator`, or `trailing_comma`.

`--decimalgrouping 3,4` is the same agreement as `trailing_comma` in the other
direction: SwiftLint's `number_separator` requires separators from four digits, so
SwiftFormat is set to group by three from four digits up rather than SwiftLint being
relaxed — otherwise `just fmt` strips a separator from a four-digit literal that
`swiftlint --strict` then demands back. `scripts/tests/lint_test.sh`'s number-separator
case (a 4- and a 5-digit literal pass both linters) runs the pinned tools against each
other and fails if they drift, for example on a SwiftLint or SwiftFormat bump.
