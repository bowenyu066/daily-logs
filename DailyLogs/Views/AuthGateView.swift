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
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("每天只记几件事")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("起床、入睡、三餐、洗澡")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await appViewModel.handleAppleSignIn(result)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 56)

                Button {
                    Task {
                        await appViewModel.continueAsGuest()
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                        Text("跳过登录，先用游客模式")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.84))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(24)
        }
        .alert("提示", isPresented: .constant(appViewModel.errorMessage != nil), actions: {
            Button("知道了") {
                appViewModel.errorMessage = nil
            }
        }, message: {
            Text(appViewModel.errorMessage ?? "")
        })
    }
}
