import AuthenticationServices
import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

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

                SignInWithAppleButton(.signIn) { request in
                    appViewModel.prepareAppleSignIn(request)
                } onCompletion: { result in
                    Task {
                        await appViewModel.handleAppleSignIn(result)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)

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
}
