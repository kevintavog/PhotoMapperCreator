import Unbox

public struct ExifToolItem {
    let filename: String
    let mimeType: String?
    let createDate: String?

    let gpsLatitudeRef: String?
    let gpsLatitude: String?
    let gpsLongitudeRef: String?
    let gpsLongitude: String?

    let imageWidth: Int?
    let imageHeight: Int?
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
