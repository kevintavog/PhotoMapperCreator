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
    var timestamp: Date

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

class Processor {
    fileprivate let thumbsFolderName = "thumbs"
    fileprivate let thumbHeight = 100

    fileprivate let popupsFolderName = "popups"
    fileprivate let popupsHeight = 400

    fileprivate let originalsFolderName = "originals"

    fileprivate var asyncErrors: [Swift.Error] = []


    static let instance = Processor()

    static let supportedImageMimeTypes: [String] = ["image/jpeg"]
    static let supportedVideoMimeTypes: [String] = ["video/mp4"]
    static let supportedMimeTypes: [String] = supportedImageMimeTypes + supportedVideoMimeTypes

    private var folderList: [Folder] = []


    func addFolder(folder: String) throws {
        folderList.append(try Files.Folder(path: folder))
    }

    func execute(outputFolder: String) throws {
        let baseOutputFolder: Folder, thumbsFolder: Folder, popupsFolder: Folder, originalsFolder: Folder

        do {
            baseOutputFolder = try FileSystem.ensureFolderExists(folder: outputFolder)
            thumbsFolder = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + thumbsFolderName)
            popupsFolder = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + popupsFolderName)
            originalsFolder = try FileSystem.ensureFolderExists(folder: outputFolder + "/" + originalsFolderName)
        } catch {
            throw CreatorError.invalidOutputPath("Bad output folder: '\(outputFolder)': \(error)")            
        }

        let group = AsyncGroup()
        var photoMapperList: [PhotoMapperItem] = []
        for (index, f) in folderList.enumerated() {
            do {
                let folderPrefix = "\(index + 1)"
                print("Processing \(f.path)")

                let thumbsFolderName = "\(thumbsFolder.path)\(folderPrefix)/"
                let popupsFolderName = "\(popupsFolder.path)\(folderPrefix)/"
                let originalsFolderName = "\(originalsFolder.path)\(folderPrefix)/"
                _ = try FileSystem.ensureFolderExists(folder: thumbsFolderName)
                _ = try FileSystem.ensureFolderExists(folder: popupsFolderName)
                _ = try FileSystem.ensureFolderExists(folder: originalsFolderName)

                // ExifTool doesn't seem to find the locations in my videos; grab that directly
                let exifItems = try ExifToolInvoker.exifForFolder(f.path).map( { (ei) -> (ExifToolItem) in
                    if !ei.hasLocation && ei.mimeType != nil && isSupportedVideoType(ei.mimeType!) {
                        if let videoData = VideoMetadata(f.path + ei.filename) {
                            if videoData.hasLocation {
                                var updated = ExifToolItem(ei)
                                updated.directLatitude = videoData.videoLatitude
                                updated.directLongitude = videoData.videoLongitude
                                return updated
                            }
                        }
                    }
                    return ei
                })

                // Get rid of items that aren't compatible, then convert to the domain model
                // used by the client and filter out those that didn't convert
                let filtered = exifItems.filter( { ei in return isValidExifItem(ei) })
                let mapped = filtered.map( { ei in return mapToPhotoMapperItem(ei, folderPrefix) })
                let finalList = mapped.filter( { pmi in return pmi.latitude != nil && pmi.longitude != nil})
                photoMapperList += finalList

                // Generate thumbs, etc.
                print("  --> found \(filtered.count) items with GPS coordinates; keeping \(finalList.count)")
                if finalList.count > 0 {
                    copyFiles(
                        group,
                        finalList.map( { pmi in return f.path + pmi.fileName}), 
                        originalsFolderName)

                    let imageList = finalList.filter({ pmi in return isSupportedImageType(pmi.mimeType) })
                        .map( { pmi in return f.path + pmi.fileName })
                    runVips(group, imageList, thumbsFolderName, thumbHeight)
                    runVips(group, imageList, popupsFolderName, popupsHeight)
                }
            } catch {
                throw CreatorError.badFile("\(f.path) failed: \(error)")
            }
        }

        group.wait()

        if asyncErrors.count > 0 {
            print("Processing failed: \(asyncErrors)")
            throw asyncErrors[0]
        }

        if photoMapperList.count == 0 {
            throw CreatorError.noMediaFound("No media was found, no photo map was created")
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
            throw CreatorError.failedWriting("Failed writing photos.json: \(error)")
        }
    }

    func runVips(_ group: AsyncGroup, _ fileList: [String], _ folder: String, _ height: Int) {
        group.background {
            do {
                try VipsThumbnailInvoker.scaleImages(fileList, folder, height)
            } catch {
                Async.userInitiated { self.asyncErrors.append(error) }
            }
        }
    }

    func copyFiles(_ group: AsyncGroup, _ fileList: [String], _ folder: String) {
        group.background {
            do {
                try FileSystem.copyFilesToFolder(fileList, folder)
            } catch {
                Async.userInitiated { self.asyncErrors.append(error) }
            }
        }
    }

    func isValidExifItem(_ exifItem: ExifToolItem) -> Bool {
        return exifItem.mimeType != nil 
            && isSupportedMimeType(exifItem.mimeType!)
            && exifItem.hasTimestamp
            && exifItem.hasLocation 
            && exifItem.hasDimensions
    }

    func isSupportedImageType(_ mimeType: String) -> Bool {
        return Processor.supportedImageMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

    func isSupportedVideoType(_ mimeType: String) -> Bool {
        return Processor.supportedVideoMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

    func isSupportedMimeType(_ mimeType: String) -> Bool {
        return Processor.supportedMimeTypes.contains { item  in
            return mimeType.caseInsensitiveCompare(item) == ComparisonResult.orderedSame
        }
    }

    func mapToPhotoMapperItem(_ exifItem: ExifToolItem, _ folderPrefix: String) -> PhotoMapperItem {

        let imageWidth = exifItem.getImageWidth()
        let imageHeight = exifItem.getImageHeight()

        return PhotoMapperItem(
            fileName: exifItem.filename,
            mimeType: exifItem.mimeType!,
            timestamp: exifItem.getTimestamp(),
            latitude: exifItem.getLatitude(),
            longitude: exifItem.getLongitude(),
            originalImage: "static/photodata/originals/\(folderPrefix)/\(exifItem.filename)",
            popupsImage: "static/photodata/popups/\(folderPrefix)/\(exifItem.filename)",
            popupWidth: imageWidth * popupsHeight / imageHeight,
            popupHeight: popupsHeight,
            thumbnail: "static/photodata/thumbs/\(folderPrefix)/\(exifItem.filename)",
            thumbWidth: imageWidth * thumbHeight / imageHeight,
            thumbHeight: thumbHeight,
            videoDurationSeconds: exifItem.getVideoDurationSeconds())
    }
}