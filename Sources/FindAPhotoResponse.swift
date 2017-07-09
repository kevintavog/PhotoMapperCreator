import Foundation

import Unbox

public struct FindAPhotoResponse {
    let resultCount: Int
    let totalMatches: Int
    let groups: [FindAPhotoGroup]
}

public struct FindAPhotoGroup {
    let name: String
    let items: [FindAPhotoItem]
}

public struct FindAPhotoItem {
    let createdDate: String
    let imageName: String

    let latitude: Double?
    let longitude: Double?

    let city: String?
    let country: String?

    let mimeType: String
    let mediaURL: String

    let height: Int
    let width: Int
}

extension FindAPhotoResponse: Unboxable {
    public init(unboxer: Unboxer) throws {
        self.resultCount = try unboxer.unbox(keyPath: "resultCount")
        self.totalMatches = try unboxer.unbox(keyPath: "totalMatches")
        self.groups = try unboxer.unbox(keyPath: "groups")
    }
}

extension FindAPhotoGroup: Unboxable {
    public init(unboxer: Unboxer) throws {
        self.name = try unboxer.unbox(keyPath: "name")
        self.items = try unboxer.unbox(keyPath: "items")
    }
}

extension FindAPhotoItem: Unboxable {
    static let inputDateFormatter = DateFormatter()
    static let outputDateFormatter = DateFormatter()
    static var formattersInitialized = false

    public init(unboxer: Unboxer) throws {
        self.createdDate = try unboxer.unbox(keyPath: "createdDate")
        self.imageName = try unboxer.unbox(keyPath: "imageName")

        self.latitude = unboxer.unbox(keyPath: "latitude")
        self.longitude = unboxer.unbox(keyPath: "longitude")

        self.city = unboxer.unbox(keyPath: "city")
        self.country = unboxer.unbox(keyPath: "country")

        self.mimeType = try unboxer.unbox(keyPath: "mimeType")
        self.mediaURL = try unboxer.unbox(keyPath: "mediaURL")

        self.width = try unboxer.unbox(keyPath: "width")
        self.height = try unboxer.unbox(keyPath: "height")
    }

    func getTimestampString() -> String {
        FindAPhotoItem.initializeFormatters()

        let date = FindAPhotoItem.inputDateFormatter.date(from: createdDate)!
        let val = FindAPhotoItem.outputDateFormatter.string(from: date)
        return val
    }

    static func initializeFormatters() {
        if !formattersInitialized {
            inputDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            outputDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            outputDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            formattersInitialized = true
        }
    }
}
