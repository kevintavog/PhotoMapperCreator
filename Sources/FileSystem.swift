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
}