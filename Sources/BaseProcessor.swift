import Foundation

import Async
import Files
import Wrap

struct PhotoMapper {
    var dateCreated: Date
    var photos: [PhotoMapperItem]
    var bounds: PhotoBounds
}

struct PhotoBounds {
    var minLatitude: Double
    var minLongitude: Double
    var maxLatitude: Double
    var maxLongitude: Double
}

struct PhotoMapperItem {
    var fileName: String
    var mimeType: String
    var timestamp: String

    // Optional in case of conversion errors; these items will be filtered out
    var latitude: Double?
    var longitude: Double?

    var originalImage: String

    var popupsImage: String
    var popupWidth: Int
    var popupHeight: Int

    var thumbnail: String
    var thumbWidth: Int
    var thumbHeight: Int

    var videoDurationSeconds: Double?
}

class BaseProcessor {
    enum Error: Swift.Error {
        case invalidOutputPath(String)
        case badFile(String)
        case failedWriting(String)
        case noMediaFound(String)
    }


    var asyncErrors: [Swift.Error] = []
    let asyncGroup = AsyncGroup()


    static let thumbsFolderName = "thumbs"
    static let thumbHeight = 100

    static let popupsFolderName = "popups"
    static let popupHeight = 400

    static let originalsFolderName = "originals"
    static let supportedImageMimeTypes: [String] = ["image/jpeg"]
    static let supportedVideoMimeTypes: [String] = ["video/mp4"]
    static let supportedMimeTypes: [String] = supportedImageMimeTypes + supportedVideoMimeTypes

    private var excludedFileNames: [String] = []


    func execute(outputFolder: String) throws {
        let baseOutputFolder: Folder

        do {
            baseOutputFolder = try FileSystem.ensureFolderExists(folder: outputFolder)
            _ = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + BaseProcessor.thumbsFolderName)
            _ = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + BaseProcessor.popupsFolderName)
            _ = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + BaseProcessor.originalsFolderName)
        } catch {
            throw Error.invalidOutputPath("Bad output folder: '\(outputFolder)': \(error)")            
        }

        let photoMapperList = try runProcessor(outputPath: baseOutputFolder.path)

        asyncGroup.wait()

        if asyncErrors.count > 0 {
            throw asyncErrors[0]
        }

        if photoMapperList.count == 0 {
            throw Error.noMediaFound("No media was found, no photo map was created")
        }

        let first = photoMapperList[0]
        var bounds = PhotoBounds(
            minLatitude: first.latitude!, minLongitude: first.longitude!,
            maxLatitude: first.latitude!, maxLongitude: first.longitude!)

        photoMapperList.forEach { pmi in 
            bounds.minLatitude = min(bounds.minLatitude, pmi.latitude!)
            bounds.minLongitude = min(bounds.minLongitude, pmi.longitude!)
            bounds.maxLatitude = max(bounds.maxLatitude, pmi.latitude!)
            bounds.maxLongitude = max(bounds.maxLongitude, pmi.longitude!)
        }

        let photoMapper = PhotoMapper(
            dateCreated: Date(),
            photos: photoMapperList.sorted { $0.timestamp < $1.timestamp },
            bounds: bounds)
        let wrapped: Data = try wrap(photoMapper)

        do {
            try wrapped.write(to: URL(fileURLWithPath: baseOutputFolder.path + "photos.json"))
        } catch {
            throw Error.failedWriting("Failed writing photos.json: \(error)")
        }
    }

    func runProcessor(outputPath: String) throws -> [PhotoMapperItem] {
        preconditionFailure("The runProcessor method must be overridden")
    }

    func addExcludedFileNames(_ list: [String]) {
        excludedFileNames = list
    }

    func isExcludedFileName(_ filename: String) -> Bool {
        return excludedFileNames.contains { $0.caseInsensitiveCompare(filename) == ComparisonResult.orderedSame }
    }

    func runVips(_ group: AsyncGroup, _ fileList: [String], _ folder: String, _ height: Int) {
        if fileList.count == 0 { return }

        group.background {
            self.runVips(fileList, folder, height)
        }
    }

    func runVips(_ fileList: [String], _ folder: String, _ height: Int) {
        if fileList.count == 0 { return }

        do {
            try VipsThumbnailInvoker.scaleImages(fileList, folder, height)
        } catch {
            Async.userInitiated { self.asyncErrors.append(error) }
        }
    }

    func generateVideoFrames(_ group: AsyncGroup, _ fileList: [String], _ thumbsFolderName: String, _ popupsFolderName: String) {
        if fileList.count == 0 { return }

        group.background {
            do {
                // Generate a frame to a temporary location
                let tempDir = NSTemporaryDirectory() + "rangic.PhotoMetadataCreator/" + NSUUID().uuidString
                _ = try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
                defer {
                    do {
                        try FileManager.default.removeItem(atPath: tempDir)
                    } catch {
                        Async.userInitiated { self.asyncErrors.append(error) }
                    }
                }

                try FfmpegInvoker.generateFrameCapture(fileList, tempDir)

                // Create thumbs & popups
                let fileList = try Folder(path: tempDir).files.map { f in f.path }
                self.runVips(fileList, thumbsFolderName, BaseProcessor.thumbHeight)
                self.runVips(fileList, popupsFolderName, BaseProcessor.popupHeight)
            } catch {
                Async.userInitiated { self.asyncErrors.append(error) }
            }
        }
    }

    func copyFiles(_ fileList: [String], _ folder: String) throws {
        try FileSystem.copyFilesToFolder(fileList, folder)
    }

    func preparePrefixedFolder(_ outputPath: String, _ folderPrefix: String) throws {
        let thumbsFolderName = "\(outputPath)\(BaseProcessor.thumbsFolderName)/\(folderPrefix)/"
        let popupsFolderName = "\(outputPath)\(BaseProcessor.popupsFolderName)/\(folderPrefix)/"
        let originalsFolderName = getOriginalsFolder(outputPath, folderPrefix)
        _ = try FileSystem.ensureFolderExists(folder: thumbsFolderName)
        _ = try FileSystem.ensureFolderExists(folder: popupsFolderName)
        _ = try FileSystem.ensureFolderExists(folder: originalsFolderName)        
    }

    func processOriginals(outputFolder: String, folderPrefix: String, items: [PhotoMapperItem]) {

        let thumbsFolderName = "\(outputFolder)\(BaseProcessor.thumbsFolderName)/\(folderPrefix)/"
        let popupsFolderName = "\(outputFolder)\(BaseProcessor.popupsFolderName)/\(folderPrefix)/"
        let originalsFolderName = getOriginalsFolder(outputFolder, folderPrefix)

        let imageList = items.filter({ pmi in return isSupportedImageType(pmi.mimeType) })
            .map( { pmi in return originalsFolderName + pmi.fileName })
        runVips(asyncGroup, imageList, thumbsFolderName, BaseProcessor.thumbHeight)
        runVips(asyncGroup, imageList, popupsFolderName, BaseProcessor.popupHeight)

        let videoList = items.filter({ pmi in return isSupportedVideoType(pmi.mimeType) })
            .map( { pmi in return originalsFolderName + pmi.fileName })
        generateVideoFrames(asyncGroup, videoList, thumbsFolderName, popupsFolderName)
    }

    func getOriginalsFolder(_ outputPath: String, _ folderPrefix: String) -> String {
        return "\(outputPath)\(BaseProcessor.originalsFolderName)/\(folderPrefix)/"
    }

    func isValidExifItem(_ exifItem: ExifToolItem) -> Bool {
        return exifItem.mimeType != nil 
            && isSupportedMimeType(exifItem.mimeType!)
            && exifItem.hasTimestamp
            && exifItem.hasLocation 
            && exifItem.hasDimensions
    }

    func isValidPhotoMapperItem(_ pmi: PhotoMapperItem) -> Bool {
        return pmi.latitude != nil && pmi.longitude != nil
    }

    func isSupportedImageType(_ mimeType: String) -> Bool {
        return BaseProcessor.supportedImageMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

    func isSupportedVideoType(_ mimeType: String) -> Bool {
        return BaseProcessor.supportedVideoMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

    func isSupportedMimeType(_ mimeType: String) -> Bool {
        return BaseProcessor.supportedMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

}