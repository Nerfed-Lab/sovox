import Foundation
import UIKit

/// Phase 15a. Which model app is on this phone.
///
/// canOpenURL answers only for schemes declared in LSApplicationQueriesSchemes,
/// and it answers false both for "not installed" and for "wrong scheme". Those
/// are not the same thing, and treating the second as the first would tell a
/// user to install an app they are already holding. So a negative result is
/// only believed once a scheme has been seen to work.
enum ModelAppAvailability: Equatable, Sendable {
    case none
    case only(AIDestination)
    case both
    /// Nothing detected, and the schemes have never been confirmed against a
    /// real installation. Treated as "show both and let the user say", never as
    /// "you have neither".
    case unknown

    var detectedAny: Bool {
        switch self {
        case .none, .unknown: return false
        case .only, .both: return true
        }
    }
}

@MainActor
enum ModelAppProbe {

    /// Flipped on once a probe has returned true for a scheme on a real device,
    /// which is proof the scheme string is right. Until then a negative is
    /// ambiguous and the wizard offers both.
    /// Per scheme, not one flag for both. A scheme that has been seen to work
    /// says nothing about the other one: if the claude string were wrong, a
    /// confirmed chatgpt would make claude look definitively absent, and the
    /// user would be locked out of a model they have installed. 15a forbids
    /// exactly that.
    private static func verifiedKey(_ destination: AIDestination) -> String {
        "sovox.modelSchemeVerified.\(destination.rawValue)"
    }

    static func isInstalled(_ destination: AIDestination) -> Bool {
        guard let url = URL(string: "\(destination.appScheme)://") else { return false }
        let installed = UIApplication.shared.canOpenURL(url)
        if installed { UserDefaults.standard.set(true, forKey: verifiedKey(destination)) }
        return installed
    }

    static func schemeConfirmed(_ destination: AIDestination) -> Bool {
        UserDefaults.standard.bool(forKey: verifiedKey(destination))
    }

    /// Only when every scheme has proven itself at least once is a clean sweep
    /// of negatives believable.
    static var schemesEverConfirmed: Bool {
        AIDestination.allCases.allSatisfy(schemeConfirmed)
    }

    /// Re-probed on every call. Apps get installed after first launch, and a
    /// wizard that cached this at startup would keep telling the user to
    /// install something they just installed.
    static func availability() -> ModelAppAvailability {
        let installed = AIDestination.allCases.filter { isInstalled($0) }
        switch installed.count {
        case 0: return schemesEverConfirmed ? .none : .unknown
        case 1: return .only(installed[0])
        default: return .both
        }
    }
}
