import SwiftCLI


struct CreatorGlobalOptions {
    static let outputFolder = Key<String>("-o", description: "The directory to write output files")
    static let excludedFiles = Key<String>("-x", description: "Comma separated list of file names to exclude")
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
            throw CLI.Error(message: "The output folder was not specified")
        }        
    }
}
