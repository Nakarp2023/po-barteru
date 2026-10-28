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
    @State private var dragPosition: CGFloat? = nil

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
        GeometryReader { geometry in
            let tabs = AppTab.allCases
            let slot = geometry.size.width / CGFloat(tabs.count)
            let selectedIndex = CGFloat(tabs.firstIndex(of: selectedTab) ?? 0)
            let lens = dragPosition ?? selectedIndex

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.7))

                Capsule()
                    .fill(.clear)
                    .frame(width: max(44, slot - 5), height: 53)
                    .modifier(NativeLensMaterial())
                    .offset(x: lens * slot + 2.5)
                    .animation(dragPosition == nil ? .spring(response: 0.34, dampingFraction: 0.76) : nil, value: lens)

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let proximity = max(0, 1 - abs(CGFloat(index) - lens))
                        Button {
                            guard selectedTab != tab else { return }
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 19 + proximity * 1.5, weight: proximity > 0.5 ? .semibold : .regular))
                                    .symbolVariant(selectedTab == tab ? .fill : .none)
                                    .frame(height: 23)
                                Text(tab.title)
                                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(proximity > 0.55 ? Color(red: 0.08, green: 0.35, blue: 0.28) : Color.secondary)
                            .scaleEffect(1 + proximity * 0.08)
                            .offset(y: -proximity * 1.5)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        dragPosition = min(CGFloat(tabs.count - 1), max(0, value.location.x / slot - 0.5))
                    }
                    .onEnded { value in
                        let position = min(CGFloat(tabs.count - 1), max(0, value.location.x / slot - 0.5))
                        selectedTab = tabs[Int(position.rounded())]
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                            dragPosition = nil
                        }
                    }
            )
        }
        .frame(height: 64)
        .padding(.horizontal, 7)
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
    }
