import Testing
@testable import PortWatcherCore

struct AppBundleLocatorTests {
    @Test func findsEnclosingAppBundle() {
        let path = "/Applications/Steam.app/Contents/MacOS/steam_osx"
        #expect(AppBundleLocator.appBundlePath(forExecutable: path) == "/Applications/Steam.app")
    }

    @Test func returnsInnermostBundleWhenNested() {
        let path = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
        #expect(AppBundleLocator.appBundlePath(forExecutable: path)
                == "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app")
    }

    @Test func returnsNilOutsideAnyBundle() {
        #expect(AppBundleLocator.appBundlePath(forExecutable: "/usr/sbin/lsof") == nil)
    }
}
