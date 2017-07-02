import SwiftCLI

struct CreatorGlobalOptions: GlobalOptionsSource {
    static let outputFolder = Key<String>("-o", usage: "The directory to write output files")
    static let excludedFiles = Key<String>("-x", usage: "Comma separated list of file names to exclude")

    static var options: [Option] {
        return [outputFolder, excludedFiles]
    }
}

extension Command {
    var outputFolderKey: Key<String> {
        return CreatorGlobalOptions.outputFolder
    }

    var outputFolder: String {
        return CreatorGlobalOptions.outputFolder.value!
    }

    var excludedFilesKey: Key<String> {
        return CreatorGlobalOptions.excludedFiles
    }

    var excludedFileNames: [String] {
        if CreatorGlobalOptions.excludedFiles.value == nil { return [] }
        return CreatorGlobalOptions.excludedFiles.value!.components(separatedBy: ",")
    }

    func confirmGlobals() throws {
        if outputFolderKey.value == nil {
            throw CLIError.error("The output folder was not specified")
        }        
    }
}
