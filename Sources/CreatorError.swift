enum CreatorError: Error {
    case invalidOutputPath(String)
    case badFile(String)
    case failedWriting(String)
    case noMediaFound(String)
}