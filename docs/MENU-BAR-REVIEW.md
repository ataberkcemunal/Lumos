# Lumos menü çubuğu incelemesi — 18 Ekim 2026

## Sonuç ve kanıt sınırı

Kaynak incelemesinde Lumos'un diğer uygulamaların simgelerini gizlediği, sıraladığı,
menü çubuğunun sistem tercihlerini değiştirdiği veya MenuBarAgent/WindowServer'ı
yeniden başlattığı bir kod yolu bulunmadı. Önceki uygulama da tek, kare genişlikte
bir NSStatusItem tutuyordu. Bu nedenle **Lumos diğer simgelerin kaybının nedenidir**
sonucu desteklenmiyor. Mevcut kayıtlar 10 Eylül'deki sağlıklı ekran geçişlerinden;
hatalı anı veya Lumos açık/kapalı karşılaştırmasını içermiyor.

Bununla birlikte etkileşimli SwiftUI içeriğinin NSMenuItem.view üzerinden macOS'un
menü takip döngüsünde çalıştırılması gereksiz bir etkileşim alanıydı. Bu katman
NSPopover ile yeniden kuruldu. Bu bir uygulama mimarisi düzeltmesidir; macOS'un
harici ekran sahnelerindeki bir hatayı kesin olarak çözdüğü iddia edilmiyor.

## İncelenen yollar

- Başlatma, accessory activation policy, uygulama menüsü ve kapanış.
- NSStatusItem oluşturma, simge güncellemeleri ve Observation aboneliği.
- NSMenu özel görünümü, boyut ölçümü, açılış yenilemesi ve SwiftUI görevleri.
- Ana pencereye geçiş ve activation policy'nin sabit kalması.
- Uyku/uyanış, ekran parametreleri ve aktif Space bildirimleri.
- Menü satırlarındaki parlaklık önizleme görevinin yaşam döngüsü.
- WiZ yenilemesinin eşzamanlı çağrılara karşı mevcut isRefreshing koruması.

## Önceki yapıda saptanan sorunlar

1. Panel SwiftUI kontrollerini NSMenu takip döngüsünün içinde çalıştırıyordu;
   menü öğesini etkin tutmak için boş target/action gerekiyordu.
2. Görünümün .task yenilemesi ile menuWillOpen yenilemesi aynı sorumluluğu
   paylaşıyordu. Store koruması örtüşmeyi sınırlandırsa da sahiplik belirsizdi.
3. Ekran ve Space değişiminde açık sunum için açık bir kapanış yolu yoktu.
4. Menü içeriği 720 puanla sınırlandığında uzun içerik için kaydırma yoktu.
5. Store değişiminde simge aynı kalsa bile yeni NSImage atanıyordu.
6. Status item'ın açık bir kaldırma ve abonelik temizleme yolu yoktu.
7. Menü satırı kaybolduğunda bekleyen parlaklık önizlemesi iptal edilmiyordu.

Bu maddeler tek başına başka uygulamaların simgelerinin kaybını kanıtlamaz.

## Yeni yapı

MenuBarPanelController, uygulama boyunca tek bir NSStatusItem tutar. Genişlik
squareLength olarak sabittir; panelin 280 puan genişliği status item'a taşınmaz.
Kararlı autosaveName macOS'un uygulama simgesinin konumunu saklamasını sağlar.
Yalnız aggregate açık/kapalı durumu değiştiğinde template simge güncellenir.

Tıklama, o anki status button'a bağlanan transient NSPopover açar. Ekran konumu
ve display ID önbelleğe alınmaz. Kapatma davranışını AppKit yönetir; global fare
izleyicisi, AX erişimi veya özel API eklenmez. Uzun içerik NSScrollView içinde,
640 puanı ve mevcut ekranın kullanılabilir yüksekliğini aşmadan gösterilir.

Ekran, Space ve uyku geçişleri paneli kapatır. Uyanış, paneli kapatıp ağ durumunu
yeniler. Bu bildirimler simgeyi kaldırıp tekrar eklemez. Açılışta, panel açılırken
ve uyanışta ağ yenilemesinin sahibi controller'dır. Aynı controller'ın yenileme
görevleri birleştirilir; store'un mevcut koruması diğer ekranlarla örtüşmeyi sınırlar.

Panel kapandığında SwiftUI içeriği bırakılır. Kapanışta bildirimler kaldırılır,
görev iptal edilir ve yalnız Lumos'un status item'ı kaldırılır. Store Observation
callback'i kapanmış controller üzerinde yeniden abonelik başlatmaz.

## Doğrulama

`sh scripts/test-menu-bar.sh` bir macOS grafik oturumu gerektirir. Test kendi
UserDefaults alanında sentetik cihazlar kullanır; gerçek lambalara komut göndermez.
Gerçek AppKit panelinde yinelenen aç/kapat, aynı status item'ın korunması,
ekran/Space/uyku/uyanış bildirimleri, uzun listenin kaydırılması ve idempotent
kapanış kontrol edilir. Bildirimler sentetiktir; fiziksel ekran bağlantısı veya
makinenin gerçekten uyutulması bu testin parçası değildir.

Gerçek sorunun giderildiğini doğrulamak için aynı ekran düzeninde günlük kullanımda
uyku/uyanış ve monitör bağlantısı sonrasında iki ekrandaki simgeler karşılaştırılmalı.
Tekrar olursa saat, hangi ekran ve hangi simgelerin kaybolduğu kaydedilmeli. Lumos'u
kapatınca düzelme de tek başına nedensellik kanıtı değildir; menü yerleşimini yeniden
tetiklemiş olabilir. Sistem süreçlerini yeniden başlatmak bu değişikliğin parçası değil.

## API referansları

- [Apple: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)
- [Apple: NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- [Apple: ekran değişikliği bildirimi](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification)
