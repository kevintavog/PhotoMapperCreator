import Foundation

import Unbox

public struct ExifToolItem {
    static let imageDateFormatter = DateFormatter()
    static let quickTimeDateFormatter = DateFormatter()
    static var formattersInitialized = false


    init(_ other: ExifToolItem) {
        filename = other.filename
        mimeType = other.mimeType
        createDate = other.createDate
        gpsLatitudeRef = other.gpsLatitudeRef
        gpsLatitude = other.gpsLatitude
        gpsLongitudeRef = other.gpsLongitudeRef
        gpsLongitude = other.gpsLongitude
        imageWidth = other.imageWidth
        imageHeight = other.imageHeight
        quickTimeCreateDate = other.quickTimeCreateDate
        quickTimeWidth = other.quickTimeWidth
        quickTimeHeight = other.quickTimeHeight
        quickTimeDuration = other.quickTimeDuration
        directLatitude = other.directLatitude
        directLongitude = other.directLongitude
    }

    let filename: String
    let mimeType: String?
    let createDate: String?

    let gpsLatitudeRef: String?
    let gpsLatitude: String?
    let gpsLongitudeRef: String?
    let gpsLongitude: String?

    let imageWidth: Int?
    let imageHeight: Int?

    // Video specific data
    let quickTimeCreateDate: String?
    let quickTimeWidth: Int?
    let quickTimeHeight: Int?
    let quickTimeDuration: String?

    var directLatitude: Double?
    var directLongitude: Double?




    var hasDimensions: Bool {
        return (imageWidth != nil && imageHeight != nil)
                ||
                (quickTimeWidth != nil && quickTimeHeight != nil)
    }

    var hasLocation: Bool {
        return 
            (directLatitude != nil && directLongitude != nil)
            || 
            (gpsLatitudeRef != nil && gpsLatitude != nil
            && gpsLongitudeRef != nil && gpsLongitude != nil)
    }

    var hasTimestamp: Bool {
        return createDate != nil || quickTimeCreateDate != nil
    }

    func getTimestamp() -> Date {
        ExifToolItem.initializeFormatters()

        if createDate != nil {
            return ExifToolItem.imageDateFormatter.date(from: createDate!)!
        } else {
            return ExifToolItem.quickTimeDateFormatter.date(from: quickTimeCreateDate!)!
        }
    }

    func getImageHeight() -> Int {
        if imageHeight != nil {
            return imageHeight!
        } else if quickTimeHeight != nil {
            return quickTimeHeight!
        }
        return 0
    }

    func getImageWidth() -> Int {
        if imageWidth != nil {
            return imageWidth!
        } else if quickTimeWidth != nil {
            return quickTimeWidth!
        }
        return 0
    }

    func getVideoDurationSeconds() -> Double? {
        if quickTimeDuration == nil {
            return nil
        }

        // Duration is either '10.15 s' or '0:00:35'
        let numberFormatter = NumberFormatter()
        let colonTokens = quickTimeDuration!.components(separatedBy: ":")
        if colonTokens.count == 3 {
            let hours = numberFormatter.number(from: colonTokens[0])?.intValue
            let minutes = numberFormatter.number(from: colonTokens[1])?.intValue
            let seconds = numberFormatter.number(from: colonTokens[2])?.intValue
            return Double((hours! * 60 * 60) + (minutes! * 60) + seconds!)
        } else {
            let spaceTokens = quickTimeDuration!.components(separatedBy: " ")
            if spaceTokens.count == 2 {
                return numberFormatter.number(from: spaceTokens[0])?.doubleValue
            }
        }
        return nil
    }

    func getLatitude() -> Double? {
        if directLatitude != nil {
            return directLatitude
        }

        if gpsLatitude != nil && gpsLatitudeRef != nil {
            var latitude = dmsToDouble(gpsLatitude!)
            if latitude == nil {
                print("WARNING: latitude is 0 for \(filename)")
            } else {
                if gpsLatitudeRef == "South" {
                    latitude! *= -1.0
                }
            }
            return latitude
        }

        return nil
    }

    func getLongitude() -> Double? {
        if directLongitude != nil {
            return directLongitude
        }

        if gpsLongitude != nil && gpsLongitudeRef != nil {
            var longitude = dmsToDouble(gpsLongitude!)
            if longitude == nil {
                print("WARNING: longitude is 0 for \(filename)")
            } else {
                if gpsLongitudeRef == "West" {
                    longitude! *= -1.0
                }
            }
            return longitude
        }

        return nil
    }

    func dmsToDouble(_ dms: String) -> Double? {
        // 122 deg 20' 36.60"
        let tokens = dms.components(separatedBy: " ")
        if tokens.count != 4 {
print("invalid DMS tokens: \(dms)")
            return nil
        }

        let degrees: Double? = Double(tokens[0])
        let minutes: Double? = Double(tokens[2].substring(offset:0, end:tokens[2].characters.count - 1))
        let seconds: Double? = Double(tokens[3].substring(offset:0, end:tokens[3].characters.count - 1))
        if degrees != nil && minutes != nil && seconds != nil {
            return degrees! + (minutes! / 60.0) + (seconds! / 3600.0)
        }

print("invalid DMS conversion: \(dms)")
        return nil
    }

    static func initializeFormatters() {
        if !formattersInitialized {
            imageDateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            quickTimeDateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            quickTimeDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            formattersInitialized = true
        }
    }
}

extension ExifToolItem: Unboxable {
    public init(unboxer: Unboxer) throws {
        self.filename = try unboxer.unbox(keyPath: "File.FileName")
        self.mimeType = unboxer.unbox(keyPath: "File.MIMEType")
        self.createDate = unboxer.unbox(keyPath: "EXIF.CreateDate")

        self.gpsLatitudeRef = unboxer.unbox(keyPath: "EXIF.GPSLatitudeRef")
        self.gpsLatitude = unboxer.unbox(keyPath: "EXIF.GPSLatitude")
        self.gpsLongitudeRef = unboxer.unbox(keyPath: "EXIF.GPSLongitudeRef")
        self.gpsLongitude = unboxer.unbox(keyPath: "EXIF.GPSLongitude")

        self.imageWidth = unboxer.unbox(keyPath: "File.ImageWidth")
        self.imageHeight = unboxer.unbox(keyPath: "File.ImageHeight")

        self.quickTimeCreateDate = unboxer.unbox(keyPath: "QuickTime.CreateDate")
        self.quickTimeWidth = unboxer.unbox(keyPath: "QuickTime.ImageWidth")
        self.quickTimeHeight = unboxer.unbox(keyPath: "QuickTime.ImageHeight")
        self.quickTimeDuration = unboxer.unbox(keyPath: "QuickTime.Duration")
    }
}

class ExifToolInvoker
{
    enum Error : Swift.Error {
        case runFailed(error: String)
    }

    static func exifForFolder(_ folder: String) throws -> [ExifToolItem]
    {
        let output = try runExifTool([ "-a", "-j", "-g", folder])

// print("parse output:\n\(output)")
        let result: [ExifToolItem] = try unbox(data: output.data(using: .utf8)!)
        return result
    }


    static var exifToolPath: String { return "/usr/local/bin/exiftool" }

    static fileprivate func runExifTool(_ arguments: [String]) throws -> String
    {
        let process = ProcessInvoker.run(exifToolPath, arguments: arguments)
        if process.exitCode == 0 {
            return process.output
        }

        throw Error.runFailed(error: "exiftool failed: \(process.exitCode); error: '\(process.error)'")
    }
}
