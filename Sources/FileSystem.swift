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
        let theFolder: Folder
        do {
            theFolder = try Files.Folder(path: folder)
        } catch {
            // If the folder can be created, use it
            let parentFolderName = (folder as NSString).deletingLastPathComponent
            let folderName = (folder as NSString).lastPathComponent
            do {
                let parentFolder = try Files.Folder(path: parentFolderName)
                theFolder = try parentFolder.createSubfolder(named: folderName)
            } catch {
                throw Error.unusablePathError("'\(folder)': \(error)")            
            }
        }

        return theFolder
    }
}