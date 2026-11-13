import Foundation

/// Every fixed piece of wording the About sheet (``AppSheet/about``) and the button that
/// presents it show, from Core's String Catalog.
///
/// The sheet's close button is the system's (`Button(role: .close)`), which brings its
/// own localized label, so it has no entry here.
public enum AboutStrings {
    /// The toolbar button that presents the About sheet; the toolbar shows its glyph, and
    /// VoiceOver reads this.
    public static var show: LocalizedStringResource {
        LocalizedStringResource(
            "about.show",
            defaultValue: "Show About",
            bundle: .module,
            comment: "Toolbar button on the to-do list that opens the About sheet.",
        )
    }

    /// The About sheet's navigation title.
    public static var title: LocalizedStringResource {
        LocalizedStringResource(
            "about.title",
            defaultValue: "About",
            bundle: .module,
            comment: "Navigation title of the sheet that says what the app is.",
        )
    }

    /// What the app is, in one sentence, on the About sheet.
    public static var description: LocalizedStringResource {
        LocalizedStringResource(
            "about.description",
            defaultValue: "Keep a list of what you need to do, and check each item off when it is done.",
            bundle: .module,
            comment: "Body text of the About sheet: what the app is for, in one sentence.",
        )
    }
}
