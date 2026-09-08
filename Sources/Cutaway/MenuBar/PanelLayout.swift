import CoreGraphics

/// The panel's vertical arithmetic, as values rather than as hope.
///
/// A `ScrollView` is greedy: `.frame(maxHeight: 176)` gave the project list
/// 176 points whether it held six projects or two, so a panel with two
/// projects showed roughly 90 points of empty list above the footer and read
/// as unfinished. The list should be as tall as it needs and no taller.
enum PanelLayout {

    /// One project row. Fixed so the list height is a multiple of something
    /// known — a row that sizes itself makes the list's height a guess.
    static let rowHeight: CGFloat = 50

    /// The tallest the list may get before it scrolls.
    ///
    /// Deliberately not a whole number of rows: stopping mid-row is what
    /// tells the eye there is more below. Three and a half rows.
    static let maxListHeight: CGFloat = 176

    /// As tall as the rows need, capped.
    static func listHeight(rowCount: Int) -> CGFloat {
        min(CGFloat(max(rowCount, 0)) * rowHeight, maxListHeight)
    }
}
