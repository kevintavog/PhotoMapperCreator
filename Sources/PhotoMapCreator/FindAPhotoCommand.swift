import Files
import SwiftCLI

class FindAPhotoCommand: Command {
    let name = "findaphoto"
    let shortDescription = "Generate a photo map from a query to a FindAPhoto host"

    let host = Parameter()
    let query = Parameter()

    func execute() throws {
        try confirmGlobals()

        FindAPhotoProcessor.instance.setHost(host.value)
        FindAPhotoProcessor.instance.setQuery(query.value)
        
        do {
            try FindAPhotoProcessor.instance.execute(outputFolder: outputFolder)
        } catch {
            throw CLI.Error(message: "Failed processing: \(error)")
        }
    }
}
