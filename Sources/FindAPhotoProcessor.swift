import Foundation

import Alamofire
import Unbox

class FindAPhotoProcessor : BaseProcessor {
    static let instance = FindAPhotoProcessor()

    var host: String = ""
    var query: String = ""
    let perQueryCount = 100

    var groupIndex = 0


    func setHost(_ host: String) {
        if host.characters.last != "/" {
            self.host = host + "/"
        } else {
            self.host = host
        }
    }

    func setQuery(_ query: String) {
        self.query = query
    }

    override func runProcessor(outputPath: String) throws -> [PhotoMapperItem] {

        var photoMapperList: [PhotoMapperItem] = []

        var resultCount = 1
        var totalMatches = 0

        var currentGroupName = ""
        var groupItems: [FindAPhotoItem] = []
        repeat {
            let response = try getSearchResults(resultCount)
            if 0 == totalMatches {
                totalMatches = response.totalMatches
            }
            resultCount += response.resultCount

            // Go through each group, using "name" as the equivalent of a folder,
            // which is aliased to an incrementing number
            for group in response.groups {
                if group.name != currentGroupName {
                    photoMapperList += try processGroupItems(outputPath, groupItems)
                    groupItems = []
                    currentGroupName = group.name
                    print("Processing \(currentGroupName)")
                }
                groupItems += group.items
            }
        } while resultCount <= totalMatches

        if totalMatches == 0 {
            print("No search results found")
        }

        photoMapperList += try processGroupItems(outputPath, groupItems)
        return photoMapperList
    }

    func processGroupItems(_ outputPath: String, _ items: [FindAPhotoItem]) throws -> [PhotoMapperItem] {
        if items.count == 0 {
            return []
        }

        groupIndex += 1
        let folderPrefix = "\(groupIndex)"
        let mapped = items.map( { js in return mapToPhotoMapperItem(js, folderPrefix) })
        let finalList = mapped.filter( { pmi in return isValidPhotoMapperItem(pmi)})

        print("  --> found \(items.count) items; keeping \(finalList.count)")
        if finalList.count == 0 {
            return []
        }

        try preparePrefixedFolder(outputPath, folderPrefix)
        let fullOutputFolder = getOriginalsFolder(outputPath, folderPrefix)
        try items.forEach { fpi in 
            let srcUrl = host + fpi.mediaURL.substringFromOffset(1)
            let destName = fullOutputFolder + fpi.imageName
            try downloadToFile(URL(string: srcUrl)!, destName)
        }

        processOriginals(outputFolder: outputPath, folderPrefix: folderPrefix, items: finalList)
        return finalList
    }

    func downloadToFile(_ url: URL, _ filename: String) throws {
        if FileManager.default.fileExists(atPath: filename) {
            return
        }

        let queue = DispatchQueue.global(qos: .background)
        let responseCompleted = DispatchSemaphore(value: 0)
        var downloadError: Swift.Error? = nil
        Alamofire.download(url, method: .get) { _, _ in
            return (destinationURL: URL(fileURLWithPath: filename), options: [.removePreviousFile])
        }
        .validate()
        .response(queue: queue) { response in
            downloadError = response.error
            responseCompleted.signal()
        }

        responseCompleted.wait()
        if downloadError != nil {
            throw downloadError!
        }
    }

    func mapToPhotoMapperItem(_ fpi: FindAPhotoItem, _ folderPrefix: String) -> PhotoMapperItem {

        let filename = fpi.imageName
        let generatedName = (filename as NSString).deletingPathExtension + ".JPG"
        let imageWidth = fpi.width
        let imageHeight = fpi.height

        return PhotoMapperItem(
            fileName: filename,
            mimeType: fpi.mimeType,
            timestamp: fpi.getTimestampString(),
            latitude: fpi.latitude,
            longitude: fpi.longitude,
            originalImage: "static/photodata/originals/\(folderPrefix)/\(filename)",
            popupsImage: "static/photodata/popups/\(folderPrefix)/\(generatedName)",
            popupWidth: imageWidth * BaseProcessor.popupHeight / imageHeight,
            popupHeight: BaseProcessor.popupHeight,
            thumbnail: "static/photodata/thumbs/\(folderPrefix)/\(generatedName)",
            thumbWidth: imageWidth * BaseProcessor.thumbHeight / imageHeight,
            thumbHeight: BaseProcessor.thumbHeight,
            videoDurationSeconds: nil) // exifItem.getVideoDurationSeconds())        
    }

    func getSearchResults(_ first:Int) throws -> FindAPhotoResponse {
        let responseCompleted = DispatchSemaphore(value: 0)

        let parameters = [
            "q": "\(query)",
            "first": "\(first)",
            "count": "\(perQueryCount)",
            "properties": "createdDate,height,id,imageName,latitude,longitude,mediaURL,mimeType,width"
        ]

        var error: Swift.Error? = nil
        var resultData: Data? = nil
        Alamofire.request(host + "api/search", parameters: parameters)
            .validate()
            .responseJSON(queue: DispatchQueue.global(qos: .utility)) { response in
                if response.error != nil {
                    error = response.error
                } else {
                    resultData = response.data
                }

            responseCompleted.signal()
        }

        responseCompleted.wait()
        if error != nil {
            throw error!
        }

        let result: FindAPhotoResponse = try unbox(data: resultData!)
        return result
    }
}