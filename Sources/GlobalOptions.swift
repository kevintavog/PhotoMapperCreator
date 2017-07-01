import SwiftCLI

struct CreatorGlobalOptions: GlobalOptionsSource {
    static let outputFolder = Key<String>("-o", usage: "The directory to write output files")
    static var options: [Option] {
        return [outputFolder]
    }
}

extension Command {
    var outputFolderKey: Key<String> {
        return CreatorGlobalOptions.outputFolder
    }

    var outputFolder: String {
        return CreatorGlobalOptions.outputFolder.value!
    }

    func confirmGlobals() throws {
        if outputFolderKey.value == nil {
            throw CLIError.error("The output folder was not specified")
        }        
    }
}
