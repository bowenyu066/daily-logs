import FirebaseCore
import UIKit

final class FirebaseAppDelegate: UIResponder, UIApplicationDelegate {
    override init() {
        super.init()
        FirebaseBootstrap.prepareForLaunch()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configureIfPossible()
        return true
    }
}

enum FirebaseBootstrap {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var didConfigureLogging = false

    static func prepareForLaunch() {
        configureLoggingIfNeeded()
        configureIfPossible()
    }

    static func configureIfPossible() {
        configureLoggingIfNeeded()

        lock.lock()
        defer { lock.unlock() }

        guard FirebaseApp.app() == nil else { return }
        let optionsURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist")

        guard let optionsURL else {
            #if DEBUG
            print("FirebaseBootstrap: GoogleService-Info.plist not found in bundle \(Bundle.main.bundlePath)")
            #endif
            return
        }

        guard let options = FirebaseOptions(contentsOfFile: optionsURL.path) else {
            #if DEBUG
            print("FirebaseBootstrap: Failed to load FirebaseOptions from \(optionsURL.path)")
            #endif
            return
        }

        FirebaseApp.configure(options: options)

        #if DEBUG
        print("FirebaseBootstrap: configured Firebase with \(options.googleAppID)")
        #endif
    }

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    private static func configureLoggingIfNeeded() {
        lock.lock()
        defer { lock.unlock() }

        guard !didConfigureLogging else { return }
        if isRunningTests {
            FirebaseConfiguration.shared.setLoggerLevel(.min)
        }
        didConfigureLogging = true
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
