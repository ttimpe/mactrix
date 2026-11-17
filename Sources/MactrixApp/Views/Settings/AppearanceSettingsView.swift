import SwiftUI

struct AppearanceSettingsView: View {
  @AppStorage("fontSize") var fontSize: Int = 13
  @AppStorage(ImageAnimationPolicy.defaultsKey) private var imageAnimationPolicy:
    ImageAnimationPolicy = .always
  @AppStorage(MessageLayoutStyle.defaultsKey) private var messageStyle = MessageLayoutStyle.standard

  var body: some View {
    Form {
      Picker("Message style", selection: $messageStyle) {
        ForEach(MessageLayoutStyle.allCases, id: \.self) { style in
          Text(style.title).tag(style)
        }
      }
      Picker("Image animation", selection: $imageAnimationPolicy) {
        ForEach(ImageAnimationPolicy.allCases, id: \.self) { policy in
          Text(policy.title).tag(policy)
        }
      }
      Picker("Font size", selection: $fontSize) {
        ForEach(8..<25) {
          Text("\($0)")
            .tag($0)
        }
      }
    }
  }
}
