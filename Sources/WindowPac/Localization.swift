import Foundation

enum AppLanguage: String, CaseIterable {
    case auto, en, tr
}

/// Tiny in-app localization: English text is the key, Turkish lives in `turkish`. A missing key falls back to
/// English. The language can be changed at runtime (Settings → Features → Language).
enum L {
    /// "en" or "tr" after resolving "automatic" against the system language.
    static var code: String {
        switch Settings.language {
        case .en: return "en"
        case .tr: return "tr"
        case .auto: return (Locale.preferredLanguages.first ?? "en").hasPrefix("tr") ? "tr" : "en"
        }
    }

    static func t(_ key: String) -> String {
        code == "tr" ? (turkish[key] ?? key) : key
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    private static let turkish: [String: String] = [
        // Menu
        "Active": "Etkin",
        "Waiting for Accessibility permission…": "Erişilebilirlik izni bekleniyor…",
        "Accessibility:": "Erişilebilirlik:",
        "✗ missing": "✗ eksik",
        "Hotkeys: ✓ registered": "Kısayollar: ✓ kayıtlı",
        "Hotkeys: ✗ unavailable: ": "Kısayollar: ✗ kullanılamıyor: ",
        "Last snap:": "Son yaslama:",
        "Open Accessibility Settings": "Erişilebilirlik Ayarlarını Aç",
        "Window snapping": "Pencere yaslama",
        "Alt-Tab window switcher": "Alt-Tab pencere değiştirici",
        "Alt-Tab: include apps without windows": "Alt-Tab: penceresi olmayan uygulamaları da göster",
        "Desktop battery widget": "Masaüstü pil widget'ı",
        "Hidden menu bar items…": "Gizli menü çubuğu öğeleri…",
        "Clipboard history": "Pano geçmişi",
        "Show clipboard history…": "Pano geçmişini göster…",
        "Settings…": "Ayarlar…",
        "Launch at login": "Oturum açılışında başlat",
        "Quit WindowPac": "WindowPac'ten Çık",
        "Language": "Dil",
        "Automatic": "Otomatik",

        // Shortcut actions and groups
        "Snap left": "Sola yasla",
        "Snap right": "Sağa yasla",
        "Fill screen": "Ekranı doldur",
        "Restore size / minimize": "Eski boyuta dön / küçült",
        "Move to previous display": "Önceki ekrana taşı",
        "Move to next display": "Sonraki ekrana taşı",
        "Enter full screen": "Tam ekrana gir",
        "Exit full screen": "Tam ekrandan çık",
        "Next window (hold modifier, release to switch)": "Sonraki pencere (tuşu basılı tut, bırakınca geç)",
        "Previous window": "Önceki pencere",
        "Show clipboard history": "Pano geçmişini göster",
        "Show hidden menu bar items": "Gizli menü çubuğu öğelerini göster",
        "Alt-Tab switcher": "Alt-Tab değiştirici",
        "Menu bar": "Menü çubuğu",

        // Settings window
        "WindowPac Settings": "WindowPac Ayarları",
        "Shortcuts": "Kısayollar",
        "Features": "Özellikler",
        "Clipboard": "Pano",
        "Shortcuts need ⌘, ⌥ or ⌃. Esc cancels recording.": "Kısayollar ⌘, ⌥ veya ⌃ içermelidir. Esc kaydı iptal eder.",
        "Reset all": "Tümünü sıfırla",
        "Press keys…": "Tuşlara bas…",
        "Reset to default": "Varsayılana sıfırla",
        "Use ⌘, ⌥ or ⌃": "⌘, ⌥ veya ⌃ kullan",
        "Used by “%@”": "“%@” tarafından kullanılıyor",
        "Windows": "Pencereler",
        "Record copied text": "Kopyalanan metni kaydet",
        "Record images": "Resimleri kaydet",
        "Record copied files (Finder)": "Kopyalanan dosyaları kaydet (Finder)",
        "Keep history after restart (stored on this Mac, owner-only)": "Yeniden başlatınca geçmişi sakla (bu Mac'te, yalnızca sana özel)",
        "Items to keep: %d": "Saklanacak kayıt: %d",
        "Clear unpinned history": "Sabitlenmemiş geçmişi temizle",
        "Pinned items are never removed and always saved. Passwords copied from password managers are not recorded.":
            "Sabitlenen kayıtlar asla silinmez ve her zaman kaydedilir. Şifre yöneticilerinden kopyalanan şifreler kaydedilmez.",
        "Other": "Diğer",
        "Snippets": "Snippet'ler",
        "Named notes that always stay at the top of the clipboard panel and are never removed automatically.":
            "Pano panelinin en üstünde duran, otomatik silinmeyen adlandırılmış notlar.",
        "No snippets yet": "Henüz snippet yok",
        "Edit": "Düzenle",
        "Title": "Başlık",
        "Add snippet": "Snippet ekle",
        "Save changes": "Değişiklikleri kaydet",
        "Cancel": "İptal",
        "Ignored apps": "Yoksayılan uygulamalar",
        "Anything copied while one of these apps is in front is not recorded.":
            "Bu uygulamalar öndeyken kopyalanan hiçbir şey kaydedilmez.",
        "Add app…": "Uygulama ekle…",
        "Reset list": "Listeyi sıfırla",
        "Hidden menu bar items (⌄ button)": "Gizli menü çubuğu öğeleri (⌄ düğmesi)",
        "Turn on “Hide” for an icon: it is covered with the menu bar background and moves into the card that drops down from the ⌄ button. Click it there to open its menu. Needs the Screen Recording permission to show the icons and to match the background; the gap where the icon was stays.":
            "Bir ikon için “Gizle”yi aç: ikon menü çubuğu arka planıyla örtülür ve ⌄ düğmesinden aşağı açılan karta taşınır. Menüsünü açmak için kartta ona tıkla. İkonları göstermek ve arka planı eşleştirmek için Ekran Kaydı izni gerekir; ikonun yeri boş kalır.",
        "Menu bar icons": "Menü çubuğu ikonları",
        "No other menu bar icons right now.": "Şu an başka menü çubuğu ikonu yok.",
        "not running": "çalışmıyor",
        "Hide": "Gizle",
        "Apple's own items (Wi-Fi, battery, clock…) can't be hidden here; manage them in System Settings → Control Center.":
            "Apple'ın kendi öğeleri (Wi-Fi, pil, saat…) buradan gizlenemez; bunları Sistem Ayarları → Denetim Merkezi'nden yönet.",

        // Clipboard panel
        "Search clipboard history…": "Pano geçmişinde ara…",
        "Nothing copied yet": "Henüz bir şey kopyalanmadı",
        "No matches": "Eşleşme yok",
        "↩ paste   ↑↓ select   ⌘P pin   ⎋ close": "↩ yapıştır   ↑↓ seç   ⌘P sabitle   ⎋ kapat",
        "Clear unpinned": "Sabitlenmemişleri temizle",
        "File": "Dosya",
        "%d files": "%d dosya",
        "Image %@": "Resim %@",
        "Unpin": "Sabitlemeyi kaldır",
        "Pin (never deleted)": "Sabitle (asla silinmez)",

        // Hidden menu bar card
        "Hidden menu bar items": "Gizli menü çubuğu öğeleri",
        "Nothing hidden yet. Choose which icons to hide in Settings → Menu bar.":
            "Henüz gizlenen yok. Gizlenecek ikonları Ayarlar → Menü çubuğu'ndan seç.",
        "Choose icons…": "İkon seç…",

        // Battery widget
        "No battery information": "Pil bilgisi yok",
        "Plugged in": "Prize takılı",
        "Case": "Kutu",

        // Alt-Tab list
        "close window": "pencereyi kapat",
        "quit app": "uygulamadan çık",
        "minimize": "küçült",
        "click or hover to pick": "tıkla ya da üstüne gel",
        "no window": "pencere yok",
        "minimized": "küçültüldü",
    ]
}
