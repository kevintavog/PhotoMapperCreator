import Files
import Foundation

class FileSystem {
    public enum Error: Swift.Error {
        case unusablePathError(String)
    }
    private init() {}

    static func copyFilesToFolder(_ filePaths: [String], _ folderPath: String) throws {
        let fileManager = FileManager.default
        try filePaths.forEach { path in
            let destName = folderPath + URL(fileURLWithPath: path).lastPathComponent
            if fileManager.fileExists(atPath: destName) {
                try fileManager.removeItem(atPath: destName)
            }

            try fileManager.copyItem(atPath: path, toPath: destName)
        }
    }

    static func ensureFolderExists(folder: String) throws -> Folder {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return try Files.Folder(path: folder)
    }

    static func allFilesExistInFolder(_ folder: String, _ fileList: [String]) -> Bool {
        // Get all folder files without path or extension
        do {
            var folderList = Set<String>()
            for file in try Files.Folder(path: folder).files {
                folderList.insert(file.nameExcludingExtension)
            }

            for f in fileList {
                 if let fileNameWithoutExtension = NSURL(fileURLWithPath: f).deletingPathExtension?.lastPathComponent {
                    if !folderList.contains(fileNameWithoutExtension) {
                        return false
                    }
                } else {
                    return false
                }
            }
        } catch {
            return false
        }
        return true
    }
}