import Foundation

/// How messages are laid out in the timeline.
enum MessageLayoutStyle: String, CaseIterable {
  /// Full-width rows with a time column, grouped under the sender's name.
  case standard
  /// Chat bubbles: your own messages on the right, everyone else's on the left.
  case bubbles

  static let defaultsKey = "messageLayoutStyle"

  static var current: MessageLayoutStyle {
    UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .standard
  }

  var title: String {
    switch self {
    case .standard: String(localized: "Standard")
    case .bubbles: String(localized: "Bubbles")
    }
  }
}
