import Foundation

enum BundleIDs {
    static let releaseBundleID = "com.giovanniberi93.jwm"
    static let integrationTestBundleID = "com.giovanniberi93.jwm.debug"

    /// Bundle IDs of the AppKit stub apps built by
    /// `integration-tests/stubs/build.sh`. The integration-test abort hotkey
    /// (ctrl+cmd+S) terminates exactly these. Hardcoded so an accidental
    /// `integrationTestMode` flag in someone's UserDefaults can never cause
    /// jwm to quit a user-owned app — only known-stub bundle IDs are eligible.
    static let integrationTestStubBundleIDs: [String] = [
        "com.giovanniberi93.jwm.stub1",
        "com.giovanniberi93.jwm.stub2",
        "com.giovanniberi93.jwm.stub3",
        "com.giovanniberi93.jwm.problematic",
        "com.giovanniberi93.jwm.overlay",
    ]
}
