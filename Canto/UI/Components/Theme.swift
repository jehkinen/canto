import SwiftUI

/// Canto's colors: violet-to-blue while listening, never alarm red.
enum Theme {
    static let violet = Color(red: 0.49, green: 0.36, blue: 1.00)
    static let blue = Color(red: 0.23, green: 0.51, blue: 1.00)
    static let listening = violet
    static let listeningGradient = LinearGradient(colors: [violet, blue], startPoint: .leading, endPoint: .trailing)
}
