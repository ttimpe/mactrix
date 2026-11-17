import AppKit

/// Where and how a message is drawn when the timeline uses chat bubbles.
struct MessageBubblePlacement: Equatable {
  /// Own messages are drawn on the right in the accent colour.
  let isOwn: Bool
  /// Whether incoming messages leave room for the sender's avatar (group chats only).
  let showsAvatarColumn: Bool
  /// The last message in a run from the same sender shows the time and the sender's avatar.
  let isLastInGroup: Bool

  var showsAvatar: Bool { showsAvatarColumn && isLastInGroup }
}

/// Shared bubble metrics for both rendering and row measurement.
@MainActor
enum MessageBubbleMetrics {
  static var horizontalPadding: CGFloat { TimelineTypography.scaled(12) }
  static var verticalPadding: CGFloat { TimelineTypography.scaled(6) }
  static var cornerRadius: CGFloat { TimelineTypography.scaled(16) }
  static var avatarSize: CGFloat { TimelineTypography.scaled(28) }
  static let avatarGap: CGFloat = 8
  static let sideInset: CGFloat = 16
  /// Space between bubbles of the same group.
  static let groupSpacing: CGFloat = 2
  /// Bubbles never take more than this share of the row.
  static let maximumWidthFraction: CGFloat = 0.75
  static var maximumColumnWidth: CGFloat { TimelineTypography.scaled(640) }

  /// Text and file messages sit in a coloured bubble; media is shown on its own.
  static func usesBackground(_ kind: MessageContentKind) -> Bool {
    switch kind {
    case .text, .file: true
    case .image, .video, .gallery: false
    }
  }

  static func padding(for kind: MessageContentKind) -> NSSize {
    usesBackground(kind) ? NSSize(width: horizontalPadding, height: verticalPadding) : .zero
  }

  static func avatarColumnWidth(_ placement: MessageBubblePlacement) -> CGFloat {
    placement.showsAvatarColumn ? avatarSize + avatarGap : 0
  }

  /// The width available to a message and its reply preview, reactions and receipts.
  static func columnWidth(rowWidth: CGFloat, placement: MessageBubblePlacement) -> CGFloat {
    let available = rowWidth - 2 * sideInset - avatarColumnWidth(placement)
    return max(1, min(available * maximumWidthFraction, maximumColumnWidth))
  }

  /// The column's distance from the row's leading edge.
  static func columnLeading(rowWidth: CGFloat, placement: MessageBubblePlacement) -> CGFloat {
    if placement.isOwn {
      return rowWidth - sideInset - columnWidth(rowWidth: rowWidth, placement: placement)
    }
    return sideInset + avatarColumnWidth(placement)
  }

  /// Leading inset of sender names, aligned with incoming bubbles in group chats.
  static var incomingNameInset: CGFloat {
    sideInset + avatarSize + avatarGap + horizontalPadding
  }

  static func backgroundColor(isOwn: Bool) -> NSColor {
    isOwn ? .controlAccentColor : incomingBackground
  }

  private static let incomingBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.9, alpha: 1)
  }

  static var timeFont: NSFont {
    .systemFont(ofSize: TimelineTypography.scaled(NSFont.smallSystemFontSize))
  }

  /// Height added below the last bubble of a group for its time label.
  static var timeLabelHeight: CGFloat {
    ceil(timeFont.boundingRectForFont.height) + 3
  }
}
