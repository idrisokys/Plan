// Plan çekirdeği (Rust) — C ABI. Kaynak: rust/plan_core/src/ffi.rs, ffi_share.rs
// Tüm dönüş tamponları plan_free(ptr, len) ile serbest bırakılır. Hata/panik durumunda NULL döner.
// Sayılar little-endian.
#ifndef PLAN_CORE_H
#define PLAN_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void plan_free(uint8_t *ptr, size_t len);

// UTF-8 metni sadeleştirir (küçük harf, Türkçe i/ı/İ/I, aksan atma).
uint8_t *plan_fold(const uint8_t *s, size_t len, size_t *out_len);

// Klasör ağacını dolaşır (.order.txt / .pinned.txt sırası, NFC ad eşleştirme) ve paralel arar.
// Çıktı: [sayı u32] + her isabet için
//   [bayrak u8: 1=not, 2=başlıkta][detay: str][öğe][üst klasör sayısı u32][üst klasörler: öğe…]
// str = u32 uzunluk + bayt;  öğe = [ad: str][yol: str][klasör u8][sabit u8]
// alive (boş olabilir) false dönerse arama bırakılır; farklı iş parçacıklarından çağrılır.
uint8_t *plan_search_tree(const uint8_t *root, size_t root_len,
                          const uint8_t *query, size_t query_len,
                          bool (*alive)(void *), void *ctx,
                          size_t *out_len);

// Girdi: [yol: u32 uzunluk + bayt]…   Çıktı: yol başına 49 bayt [durum u8][boyut u64][mtime i64][sha256 32 bayt]
uint8_t *plan_analyze_files(const uint8_t *paths, size_t len, size_t *out_len);

// Çıktı: kayıtlar [tür u8: 0=dosya 1=klasör 2=diğer][boyut u64][mtime i64][yol: u32 uzunluk + bayt]
uint8_t *plan_scan(const uint8_t *root, size_t root_len, bool include_hidden, size_t *out_len);

// Premultiplied RGBA8 → en uzun kenarı max_side olan küçük resim (aynı biçim, büyütme yok).
uint8_t *plan_thumbnail(const uint8_t *rgba, uint32_t width, uint32_t height, uint32_t max_side,
                        uint32_t *out_w, uint32_t *out_h, size_t *out_len);

// ---- Hızlı Paylaş / Notlarım eşitlemesi (qshare_core/src/share — Android'le ortak, köprü: ffi_share.rs) ----

// Rust'tan dönen hata/özet metinlerinin dili (true = İngilizce, false = Türkçe).
void plan_qs_set_lang(bool english);

// Olay türleri: 1 = alınıyor (text=ad), 2 = alındı (text=ad, path=klasör),
// 3 = alma yarım kaldı (text=ad), 4 = Link içeriği eşitlemeyle değişti.
// Farklı iş parçacıklarından çağrılır.
typedef void (*plan_qs_event_cb)(void *ctx, uint8_t kind, const uint8_t *text, size_t text_len,
                                 const uint8_t *path, size_t path_len);
typedef void (*plan_qs_progress_cb)(void *ctx, uint32_t file_index, uint64_t sent, uint64_t total);

// Alma sunucusunu başlatır (düz TCP; POST /u, GET /m, GET /f, DELETE /x, POST /d). port=0 → boş port,
// out_port'a yazılır. link_root_len=0 ise eşitleme uç noktaları kapalı. Hata: NULL.
void *plan_qs_server_start(const uint8_t *recv_dir, size_t recv_len,
                           const uint8_t *link_root, size_t link_len,
                           uint16_t port, plan_qs_event_cb cb, void *ctx, uint16_t *out_port);
void plan_qs_server_stop(void *handle);

// Girdi: [yol: u32 uzunluk + bayt]…  addr = "ip:port". Klasörler zip'lenir. Engelleyici.
// Dönüş: başarıyla giden dosya sayısı, panikte -1.
int32_t plan_qs_send(const uint8_t *addr, size_t addr_len, const uint8_t *paths, size_t paths_len,
                     plan_qs_progress_cb progress, void *ctx);

// mode: 0 iki cihazda aynı, 1 bu cihaza göre, 2 karşıdakine göre. Engelleyici.
// peers = [ad: str][adres: str]…   Çıktı: [hatasız u8][gönderilen u32][alınan u32][silinen u32][cihaz u32]
//   [özet: str][hata sayısı u32][hata: str…]
uint8_t *plan_qs_sync(uint32_t mode, const uint8_t *link_root, size_t link_len,
                      const uint8_t *peers, size_t peers_len, size_t *out_len);

// Göreli yolu root içinde güvenli yola çevirir; geçersizse NULL.
uint8_t *plan_qs_resolve(const uint8_t *rel, size_t rel_len, const uint8_t *root, size_t root_len,
                         bool dir, size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif
