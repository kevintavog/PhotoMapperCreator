import Files
import SwiftCLI

class FolderCommand: Command {
    let name = "folder"
    let shortDescription = "One or more folders to include in the photo map"

    let folders = CollectedParameter()

    func execute() throws {
        try confirmGlobals()

print("Make sure exiftool, vipsthumbnail & ffmpeg are available")

        for f in folders.value {
            do {
                try Processor.instance.addFolder(folder: f)
            } catch {
                throw CLIError.error("Bad input folder: \(error)")
            }

            do {
                try Processor.instance.execute(outputFolder: outputFolder)
            } catch {
                throw CLIError.error("Failed processing: \(error)")
            }
        }
    }
}
