import SwiftUI

struct EmptyStateView: View {
  let title: String
  let systemImage: String
  let description: String?

  init(title: String, systemImage: String, description: String? = nil) {
    self.title = title
    self.systemImage = systemImage
    self.description = description
  }

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(.secondary)

      Text(title)
        .font(.title3)
        .fontWeight(.semibold)

      if let description, !description.isEmpty {
        Text(description)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

