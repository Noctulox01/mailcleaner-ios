import Foundation

enum Config {
    static let siteURL = URL(string: "http://192.168.137.1:5002/app")!
    static let internalHost = siteURL.host ?? ""
}
