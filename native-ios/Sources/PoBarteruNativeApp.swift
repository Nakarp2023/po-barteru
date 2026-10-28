import SwiftUI
import WebKit

@main
struct PoBarteruNativeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case home, favorites, myListings = "my-listings", chats, profile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Главная"
        case .favorites: return "Избранное"
        case .myListings: return "Мои"
        case .chats: return "Сообщения"
        case .profile: return "Профиль"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .favorites: return "heart"
        case .myListings: return "square.grid.2x2"
        case .chats: return "bubble.left.and.bubble.right"
        case .profile: return "person.crop.circle"
        }
    }
}

final class WebViewStore: ObservableObject {
    @Published var webView: WKWebView?
}

struct ContentView: View {
    @StateObject private var store = WebViewStore()
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.97, blue: 0.95).ignoresSafeArea()

            NativeSiteWebView(store: store)
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    nativeTabBar
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 5)
                }
        }
        .statusBarHidden(false)
        .onChange(of: selectedTab) { _, tab in
            let rawTab = tab.rawValue
            let js = """
            (() => {
              const tab = document.querySelector('.bottom .nav[data-page="\(rawTab)"]');
              if (tab) tab.click();
              else if (typeof window.setPage === 'function') window.setPage('\(rawTab)');
            })();
            """
            store.webView?.evaluateJavaScript(js)
        }
    }

    private var nativeTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 19, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolVariant(selectedTab == tab ? .fill : .none)
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == tab ? Color(red: 0.08, green: 0.35, blue: 0.28) : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 7)
            }
        }
        .overlay {
            if #available(iOS 26.0, *) {
                Capsule().strokeBorder(.white.opacity(0.36), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct NativeSiteWebView: UIViewRepresentable {
    @ObservedObject var store: WebViewStore
    private let siteURL = URL(string: "https://po-barteru.onrender.com")!

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let css = """
        const style = document.createElement('style');
        style.id = 'po-barteru-native-shell';
        style.textContent = '.bottom{display:none!important} body{padding-bottom:calc(92px + env(safe-area-inset-bottom))!important}';
        (document.head || document.documentElement).appendChild(style);
        """
        controller.addUserScript(WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.95, green: 0.97, blue: 0.95, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: siteURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        store.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
