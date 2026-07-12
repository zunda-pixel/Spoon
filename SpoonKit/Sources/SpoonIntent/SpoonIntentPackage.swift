public import AppIntents

/// Makes this package's intents visible to the App Intents metadata
/// extractor. The app registers it through its own `AppIntentsPackage`
/// conformance (`includedPackages`).
public struct SpoonIntentPackage: AppIntentsPackage {}
