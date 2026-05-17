import Foundation

extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
