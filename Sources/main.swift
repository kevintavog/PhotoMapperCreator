import Foundation
import SwiftCLI

// < > folder -f input1 input2 -o output
// < > findaphoto -h host -q query -o output

// Take an input folder, require an output folder
CLI.setup(
    name: "PhotoMapper creator",
    version: "1.0",
    description: "Creates PhotoMapper projects that can be uploaded to a website.")
CLI.register(command: FolderCommand())
GlobalOptions.source(CreatorGlobalOptions.self)

let result = CLI.go()
exit(result)
