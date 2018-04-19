import Foundation

import Async
import Files
import Wrap

struct PhotoMapper {
    var dateCreated: Date
    var photos: [PhotoMapperItem]
    var bounds: PhotoBounds
    var filters: [PhotoFilter]
}

struct PhotoFilter {
    var name: String
    var field: String
    var values: [PhotoFilterValue]
}

struct PhotoFilterValue: Hashable {
    var value: String
    var selected: Bool

    var hashValue: Int {
        return value.hashValue
    }

    static func == (lhs: PhotoFilterValue, rhs: PhotoFilterValue) -> Bool {
        return lhs.value == rhs.value
    }
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
    var year: String?
    var monthName: String?
    var date: String?

    // Optional in case of conversion errors; these items will be filtered out
    var latitude: Double?
    var longitude: Double?

    var city: String?
    var country: String?

    var originalImage: String

    var popupsImage: String
    var popupWidth: Int
    var popupHeight: Int

    var thumbnail: String
    var thumbWidth: Int
    var thumbHeight: Int

    var videoDurationSeconds: Double?
}

struct MonthNameAndNumber: Hashable {
    var name: String
    var number: Int

    var hashValue: Int {
        return number.hashValue
    }

    static func == (lhs: MonthNameAndNumber, rhs: MonthNameAndNumber) -> Bool {
        return lhs.number == rhs.number
    }
}

class BaseProcessor {
    let citiesFilter = "Cities"
    let countriesFilter = "Countries"
    let yearsFilter = "Years"
    let monthsFilter = "Months"
    let datesFilter = "Dates"

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

        let photodataFolder = outputFolder + "/photodata"

        do {
            baseOutputFolder = try FileSystem.ensureFolderExists(folder: photodataFolder)
            _ = try FileSystem.ensureFolderExists(folder: photodataFolder + "/" + BaseProcessor.thumbsFolderName)
            _ = try FileSystem.ensureFolderExists(folder: photodataFolder + "/" + BaseProcessor.popupsFolderName)
            _ = try FileSystem.ensureFolderExists(folder: photodataFolder + "/" + BaseProcessor.originalsFolderName)
        } catch {
            throw Error.invalidOutputPath("Bad output folder: '\(outputFolder)': \(error)")            
        }

        var photoMapperList = try runProcessor(outputPath: baseOutputFolder.path)
        asyncGroup.wait()

        if asyncErrors.count > 0 {
            throw asyncErrors[0]
        }

        if photoMapperList.count == 0 {
            throw Error.noMediaFound("No media was found, no photo map was created")
        }

        let calculated = calculateBoundsAndFilters(&photoMapperList)
        let photoMapper = PhotoMapper(
            dateCreated: Date(),
            photos: photoMapperList.sorted { $0.timestamp < $1.timestamp },
            bounds: calculated.bounds,
            filters: calculated.filters)
        let wrapped: Data = try wrap(photoMapper)

        do {
            try wrapped.write(to: URL(fileURLWithPath: baseOutputFolder.path + "photos.json"))
        } catch {
            throw Error.failedWriting("Failed writing photos.json: \(error)")
        }
    }

    func calculateBoundsAndFilters(_ photoMapperList: inout [PhotoMapperItem]) -> (bounds: PhotoBounds, filters: [PhotoFilter]) {
        let first = photoMapperList[0]
        var bounds = PhotoBounds(
            minLatitude: first.latitude!, minLongitude: first.longitude!,
            maxLatitude: first.latitude!, maxLongitude: first.longitude!)

        let timestampDateFormatter = DateFormatter()
        timestampDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        timestampDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let monthNameDateFormatter = DateFormatter()
        monthNameDateFormatter.dateFormat = "LLLL"
        let calendar = Calendar.current

        var rawMonthsFilter = Set<MonthNameAndNumber>()
        var rawFilters = [
            citiesFilter: Set<PhotoFilterValue>(),
            countriesFilter: Set<PhotoFilterValue>(),
            yearsFilter: Set<PhotoFilterValue>(),
            datesFilter: Set<PhotoFilterValue>()
        ]
        for (index, pmi) in photoMapperList.enumerated() {
            bounds.minLatitude = min(bounds.minLatitude, pmi.latitude!)
            bounds.minLongitude = min(bounds.minLongitude, pmi.longitude!)
            bounds.maxLatitude = max(bounds.maxLatitude, pmi.latitude!)
            bounds.maxLongitude = max(bounds.maxLongitude, pmi.longitude!)

            if pmi.city != nil && !pmi.city!.isEmpty {
                rawFilters[citiesFilter]!.insert(PhotoFilterValue(value: pmi.city!, selected: false))
            }
            if pmi.country != nil && !pmi.country!.isEmpty {
                rawFilters[countriesFilter]!.insert(PhotoFilterValue(value: pmi.country!, selected: false))
            }

            if let date = timestampDateFormatter.date(from: pmi.timestamp) {
                let year = calendar.component(.year, from: date)
                rawFilters[yearsFilter]!.insert(PhotoFilterValue(value: "\(year)", selected: false))

                let month = calendar.component(.month, from: date)
                let monthName = monthNameDateFormatter.string(from: date)
                rawMonthsFilter.insert(MonthNameAndNumber(name: "\(monthName)", number: month))

                let day = calendar.component(.day, from: date)
                let date = "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
                rawFilters[datesFilter]!.insert(PhotoFilterValue(value: date, selected: false))

                photoMapperList[index].year = "\(year)"
                photoMapperList[index].monthName = monthName
                photoMapperList[index].date = date
            }
        }

        // Keep either the year & month names OR the dates
        if rawFilters[datesFilter]!.count > 20 {
            rawFilters[datesFilter] = nil
        } else {
            rawFilters[yearsFilter] = nil
            rawFilters[monthsFilter] = nil
        }

        let filterNameToFieldMap = [
            citiesFilter: "city",
            countriesFilter: "country",
            yearsFilter: "year",
            monthsFilter: "monthName",
            datesFilter: "date"
        ]

        var filters: [PhotoFilter] = []
        for (key, values) in rawFilters {
            if values.count > 1 {
                filters.append(
                    PhotoFilter(
                        name: key, 
                        field: filterNameToFieldMap[key]!, 
                        values: values.sorted(by: { (a, b) -> Bool in
                            return a.value <= b.value
                        })))
            }
        }

        let sortedMonths = rawMonthsFilter.sorted(by: { (a, b) -> Bool in 
            return a.number <= b.number
        }).map { m in PhotoFilterValue(value: m.name, selected: false) }
        filters.append(PhotoFilter(name: monthsFilter, field: filterNameToFieldMap[monthsFilter]!, values: sortedMonths))

        return (bounds, filters)
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
        if FileSystem.allFilesExistInFolder(folder, fileList) {
            return
        }

        do {
            try VipsThumbnailInvoker.scaleImages(fileList, folder, height)
        } catch {
            Async.userInitiated { self.asyncErrors.append(error) }
        }
    }

    func generateVideoFrames(_ group: AsyncGroup, _ fileList: [String], _ thumbsFolderName: String, _ popupsFolderName: String) {
        if fileList.count == 0 { return }
        if FileSystem.allFilesExistInFolder(thumbsFolderName, fileList) 
            && FileSystem.allFilesExistInFolder(popupsFolderName, fileList) {
            return
        }

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