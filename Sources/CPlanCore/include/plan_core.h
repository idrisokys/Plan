// Plan çekirdeği (Rust) — C ABI. Kaynak: rust/plan_core/src/ffi.rs
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

// Girdi: kayıtlar [kind u8][path: u32 uzunluk + bayt][title: u32 uzunluk + bayt]  (kind 0=.url 1=.txt 2=klasör)
// Çıktı: [sayı u32] + isabetler [indeks u32][bayrak u8: 1=not, 2=başlıkta][detay: u32 uzunluk + bayt]
// alive (boş olabilir) false dönerse arama bırakılır; farklı iş parçacıklarından çağrılır.
uint8_t *plan_search(const uint8_t *items, size_t items_len,
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

#ifdef __cplusplus
}
#endif

#endif
