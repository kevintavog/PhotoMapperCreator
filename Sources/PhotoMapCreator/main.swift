import Foundation
import SwiftCLI

// < > folder -f input1 input2 -o output
// < > findaphoto -h host -q query -o output

// Take an input folder, require an output folder
let cli = CLI(
    name: "PhotoMapper creator",
    version: "1.1",
    description: "Creates PhotoMapper projects that can be uploaded to a website.")
cli.commands = [FindAPhotoCommand(), FolderCommand()]
cli.globalOptions.append(CreatorGlobalOptions.outputFolder)
cli.globalOptions.append(CreatorGlobalOptions.excludedFiles)

print("Make sure exiftool, vipsthumbnail & ffmpeg are available")
cli.goAndExit()
