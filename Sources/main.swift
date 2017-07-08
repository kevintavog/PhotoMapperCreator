import Foundation
import SwiftCLI

// < > folder -f input1 input2 -o output
// < > findaphoto -h host -q query -o output

// Take an input folder, require an output folder
CLI.setup(
    name: "PhotoMapper creator",
    version: "1.0",
    description: "Creates PhotoMapper projects that can be uploaded to a website.")
CLI.register(commands: [FindAPhotoCommand(), FolderCommand()])
GlobalOptions.source(CreatorGlobalOptions.self)

print("Make sure exiftool, vipsthumbnail & ffmpeg are available")
let result = CLI.go()
exit(result)
