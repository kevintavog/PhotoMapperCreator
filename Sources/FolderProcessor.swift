import Foundation
import Files

class FolderProcessor : BaseProcessor {
    static let instance = FolderProcessor()

    private var folderList: [Folder] = []

    func addFolder(folder: String) throws {
        folderList.append(try Files.Folder(path: folder))
    }

    override func runProcessor(outputPath: String) throws -> [PhotoMapperItem] {
        var photoMapperList: [PhotoMapperItem] = []
        for (index, f) in folderList.enumerated() {
            do {
                let folderPrefix = "\(index + 1)"
                print("Processing \(f.path)")

                try preparePrefixedFolder(outputPath, folderPrefix)

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
                let filtered = exifItems.filter( { ei in return isValidExifItem(ei) && !isExcludedFileName(ei.filename) })
                let mapped = filtered.map( { ei in return mapToPhotoMapperItem(ei, folderPrefix) })
                let finalList = mapped.filter( { pmi in return isValidPhotoMapperItem(pmi)})
                photoMapperList += finalList

                // Generate thumbs, etc.
                print("  --> found \(filtered.count) items with GPS coordinates; keeping \(finalList.count)")
                if finalList.count > 0 {
                    try copyFiles(
                        finalList.map( { pmi in return f.path + pmi.fileName}), 
                        getOriginalsFolder(outputPath, folderPrefix))

                    processOriginals(outputFolder: outputPath, folderPrefix: folderPrefix, items: finalList)
                }
            } catch {
                throw Error.badFile("\(f.path) failed: \(error)")
            }
        }

        return photoMapperList
    }

    func mapToPhotoMapperItem(_ exifItem: ExifToolItem, _ folderPrefix: String) -> PhotoMapperItem {

        let imageWidth = exifItem.getImageWidth()
        let imageHeight = exifItem.getImageHeight()

        let generatedName = (exifItem.filename as NSString).deletingPathExtension + ".JPG"

        return PhotoMapperItem(
            fileName: exifItem.filename,
            mimeType: exifItem.mimeType!,
            timestamp: exifItem.getTimestampString(),
            latitude: exifItem.getLatitude(),
            longitude: exifItem.getLongitude(),
            originalImage: "static/photodata/originals/\(folderPrefix)/\(exifItem.filename)",
            popupsImage: "static/photodata/popups/\(folderPrefix)/\(generatedName)",
            popupWidth: imageWidth * BaseProcessor.popupHeight / imageHeight,
            popupHeight: BaseProcessor.popupHeight,
            thumbnail: "static/photodata/thumbs/\(folderPrefix)/\(generatedName)",
            thumbWidth: imageWidth * BaseProcessor.thumbHeight / imageHeight,
            thumbHeight: BaseProcessor.thumbHeight,
            videoDurationSeconds: exifItem.getVideoDurationSeconds())
    }
}