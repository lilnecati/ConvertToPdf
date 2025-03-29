# ConvertToPdf

macOS için çoklu format dönüştürücü uygulaması. Çeşitli dosya türlerini PDF ve diğer formatlara dönüştürün.

![ConvertToPdf Screenshot](screenshot.png)

## Özellikler

- Office (DOCX, PPT, XLS) dosyalarını PDF'e dönüştürme
- Görüntü (JPG, PNG) dosyalarını PDF'e dönüştürme
- PDF dosyalarını görüntü formatlarına dönüştürme
- Sürükle ve bırak dosya ekleme
- Toplu dönüştürme işlemleri
- Son dönüştürmeleri kaydetme ve hızlı erişim
- Çoklu dil desteği (Türkçe, İngilizce)
- Dönüştürme tamamlandığında sesli bildirim

## Gereksinimler

Bu uygulamayı kullanmak için aşağıdaki bileşenlerin yüklü olması gerekir:

- **LibreOffice** - Office dosyalarını dönüştürmek için
- **Tesseract OCR** - Metin tanıma işlemleri için
- **ImageMagick** - Görüntü işleme için

Uygulama, eksik bileşenleri tespit edip kurulum yönergelerini gösterecektir.

## Kurulum

1. Son sürümü [Releases](https://github.com/username/ConvertToPdf/releases) sayfasından indirin
2. `ConvertToPdf.app` dosyasını Uygulamalar klasörüne sürükleyin
3. Uygulama ilk kez açıldığında gerekli bileşenlerin kurulum kılavuzunu göreceksiniz

### Gerekli Bileşenlerin Kurulumu

Uygulama içindeki "Gereksinimler" bölümünden tüm gerekli bileşenleri kurabilirsiniz:

#### Homebrew ile Kurulum:

```bash
# Homebrew kurulumu (önceden kurulu değilse)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# LibreOffice kurulumu
brew install --cask libreoffice

# Tesseract OCR kurulumu
brew install tesseract tesseract-lang

# ImageMagick kurulumu
brew install imagemagick
```

## Kullanım

1. Dosyaları dönüştürmek için sürükle-bırak alanına dosya bırakın veya "Dosya Seç" düğmesini kullanın
2. İstediğiniz çıktı formatını seçin
3. "Dönüştür" düğmesine tıklayın
4. Dönüştürülen dosyalar Son Dönüşümler bölümünde görüntülenecektir

### Toplu Dönüştürme

Birden fazla dosyayı dönüştürmek için:

1. Birden fazla dosyayı sürükle-bırak alanına sürükleyin
2. İstediğiniz çıktı formatını seçin
3. "Toplu Dönüştürmeyi Başlat" düğmesine tıklayın
4. Tüm işlemler tamamlandığında bir bildirim alacaksınız

## Katkıda Bulunma

Projeye katkıda bulunmak isterseniz:

1. Bu depoyu (fork) çatallayın
2. Yeni bir özellik dalı (branch) oluşturun (`git checkout -b yeni-ozellik`)
3. Değişikliklerinizi commit edin (`git commit -m 'Yeni özellik eklendi'`)
4. Dalınızı uzak depoya itin (`git push origin yeni-ozellik`)
5. Bir Pull Request açın

## Lisans

Bu proje MIT lisansı altında lisanslanmıştır - ayrıntılar için [LICENSE](LICENSE) dosyasına bakın.

## İletişim

Sorularınız veya geri bildirimleriniz için [issues](https://github.com/username/ConvertToPdf/issues) bölümünü kullanabilirsiniz. 