import AuthenticationServices
import SwiftUI
import UIKit

struct AuthGateView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var appleSignInCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.background, AppTheme.accentSoft.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Spacer()
                    languageToggle
                }

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("每天只记几件事", tableName: "Localizable")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("起床、入睡、三餐、洗澡", tableName: "Localizable")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(spacing: 12) {
                    Button {
                        startAppleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20, weight: .semibold))
                            Text(LocalizedStringKey("使用 Apple 登录"))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await appViewModel.continueAsGuest()
                        }
                    } label: {
                        Text(LocalizedStringKey("继续作为游客"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.surface.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(24)
        }
        .alert(String(localized: "提示"), isPresented: .constant(appViewModel.errorMessage != nil), actions: {
            Button(String(localized: "知道了")) {
                appViewModel.errorMessage = nil
            }
        }, message: {
            Text(appViewModel.errorMessage ?? "")
        })
    }

    private var languageToggle: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    Task { await appViewModel.updateAppLanguage(lang) }
                } label: {
                    HStack {
                        Text(lang.title)
                        if appViewModel.preferences.appLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 42, height: 42)
                .background(AppTheme.surface)
                .clipShape(Circle())
        }
    }

    private func startAppleSignIn() {
        let coordinator = AppleSignInCoordinator(
            onRequest: { request in
                appViewModel.prepareAppleSignIn(request)
            },
            onCompletion: { result in
                Task {
                    await appViewModel.handleAppleSignIn(result)
                }
                appleSignInCoordinator = nil
            }
        )
        appleSignInCoordinator = coordinator
        coordinator.start()
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    private let onCompletion: (Result<ASAuthorization, Error>) -> Void

    init(
        onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
        onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void
    ) {
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        onRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: \.isKeyWindow) {
                return window
            }
            if let window = windowScene.windows.first {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}
