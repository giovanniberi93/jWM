import Foundation

enum BundleIDs {
    static let releaseBundleID = "com.giovanniberi93.janzowm"
    static let integrationTestBundleID = "com.giovanniberi93.janzowm.debug"

    /// Bundle IDs of the AppKit stub apps built by
    /// `integration-tests/stubs/build.sh`. The integration-test abort hotkey
    /// (ctrl+cmd+S) terminates exactly these. Hardcoded so an accidental
    /// `integrationTestMode` flag in someone's UserDefaults can never cause
    /// janzowm to quit a user-owned app — only known-stub bundle IDs are eligible.
    static let integrationTestStubBundleIDs: [String] = [
        "com.giovanniberi93.janzowm.stub1",
        "com.giovanniberi93.janzowm.stub2",
        "com.giovanniberi93.janzowm.stub3",
        "com.giovanniberi93.janzowm.problematic",
        "com.giovanniberi93.janzowm.overlay",
    ]
}
