public enum AppBundleLocator {
    /// lsof reports the executable inside the bundle; the icon lives on the .app.
    public static func appBundlePath(forExecutable path: String) -> String? {
        var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while let last = components.last {
            if last.hasSuffix(".app") { return components.joined(separator: "/") }
            components.removeLast()
        }
        return nil
    }
}
