//! Küçük resim: premultiplied RGBA tamponunu alan ortalamasıyla (box filtre) küçültür.
//! Çözme/kodlama (JPEG, PNG…) Swift'te ImageIO ile kalır; Rust yalnızca piksel işini yapar.

/// En uzun kenar `max_side`'ı aşmayacak şekilde, oran korunarak boyut. Büyütme yapılmaz.
pub fn fit_within(w: u32, h: u32, max_side: u32) -> (u32, u32) {
    if w == 0 || h == 0 || max_side == 0 {
        return (0, 0);
    }
    if w <= max_side && h <= max_side {
        return (w, h);
    }
    let s = max_side as f64 / w.max(h) as f64;
    (((w as f64 * s).round() as u32).max(1), ((h as f64 * s).round() as u32).max(1))
}

/// Hedef indeks başına (kaynak indeks, ağırlık) listesi; ağırlıklar toplamı 1.
fn weights(src: usize, dst: usize) -> Vec<Vec<(usize, f32)>> {
    let scale = src as f64 / dst as f64;
    (0..dst)
        .map(|i| {
            let (a, b) = (i as f64 * scale, (i + 1) as f64 * scale);
            let mut v: Vec<(usize, f64)> = Vec::new();
            let mut s = a.floor() as usize;
            while (s as f64) < b && s < src {
                let w = b.min(s as f64 + 1.0) - a.max(s as f64);
                if w > 1e-9 {
                    v.push((s, w));
                }
                s += 1;
            }
            let sum: f64 = v.iter().map(|x| x.1).sum();
            v.into_iter().map(|(s, w)| (s, (w / sum) as f32)).collect()
        })
        .collect()
}

/// RGBA8 (4 bayt/piksel) görüntüyü `dw × dh` boyutuna küçültür; satırlar iş parçacıklarına bölünür.
pub fn resize_rgba(src: &[u8], sw: usize, sh: usize, dw: usize, dh: usize) -> Option<Vec<u8>> {
    if sw == 0 || sh == 0 || dw == 0 || dh == 0 || src.len() < sw * sh * 4 {
        return None;
    }
    let wx = weights(sw, dw);
    let wy = weights(sh, dh);
    let mut out = vec![0u8; dw * dh * 4];
    let rows_per = (dh + crate::workers() - 1) / crate::workers();
    std::thread::scope(|s| {
        for (chunk_i, chunk) in out.chunks_mut(rows_per.max(1) * dw * 4).enumerate() {
            let (wx, wy) = (&wx, &wy);
            s.spawn(move || {
                let mut hrow = vec![0f32; dw * 4];
                let mut acc = vec![0f32; dw * 4];
                for (r, dst_row) in chunk.chunks_mut(dw * 4).enumerate() {
                    let y = chunk_i * rows_per.max(1) + r;
                    acc.iter_mut().for_each(|a| *a = 0.0);
                    for &(sy, wyv) in &wy[y] {
                        let line = &src[sy * sw * 4..(sy + 1) * sw * 4];
                        for (x, taps) in wx.iter().enumerate() {
                            let mut px = [0f32; 4];
                            for &(sx, wxv) in taps {
                                for c in 0..4 {
                                    px[c] += line[sx * 4 + c] as f32 * wxv;
                                }
                            }
                            hrow[x * 4..x * 4 + 4].copy_from_slice(&px);
                        }
                        for (a, h) in acc.iter_mut().zip(&hrow) {
                            *a += h * wyv;
                        }
                    }
                    for (d, a) in dst_row.iter_mut().zip(&acc) {
                        *d = (a + 0.5).clamp(0.0, 255.0) as u8;
                    }
                }
            });
        }
    });
    Some(out)
}

/// En uzun kenarı `max_side` olan küçük resim. Dönen: (genişlik, yükseklik, RGBA).
pub fn thumbnail(src: &[u8], sw: u32, sh: u32, max_side: u32) -> Option<(u32, u32, Vec<u8>)> {
    let (dw, dh) = fit_within(sw, sh, max_side);
    if dw == 0 {
        return None;
    }
    if (dw, dh) == (sw, sh) {
        let n = sw as usize * sh as usize * 4;
        return src.get(..n).map(|s| (sw, sh, s.to_vec()));
    }
    resize_rgba(src, sw as usize, sh as usize, dw as usize, dh as usize).map(|v| (dw, dh, v))
}

/// Birçok resmi paralel küçültür: (rgba, w, h) → küçük resim.
pub fn thumbnail_batch(jobs: &[(Vec<u8>, u32, u32)], max_side: u32) -> Vec<Option<(u32, u32, Vec<u8>)>> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;
    let next = AtomicUsize::new(0);
    let out = Mutex::new(vec![None; jobs.len()]);
    let n = crate::workers().min(jobs.len().max(1));
    std::thread::scope(|s| {
        for _ in 0..n {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= jobs.len() {
                    break;
                }
                let r = thumbnail(&jobs[i].0, jobs[i].1, jobs[i].2, max_side);
                out.lock().unwrap()[i] = r;
            });
        }
    });
    out.into_inner().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fit_keeps_aspect_and_never_upscales() {
        assert_eq!(fit_within(4000, 2000, 200), (200, 100));
        assert_eq!(fit_within(100, 50, 200), (100, 50));
        assert_eq!(fit_within(1, 5000, 10), (1, 10));
        assert_eq!(fit_within(0, 5, 10), (0, 0));
    }

    #[test]
    fn solid_color_stays_solid() {
        let (w, h) = (37usize, 23usize);
        let src: Vec<u8> = (0..w * h).flat_map(|_| [10u8, 200, 30, 255]).collect();
        let (dw, dh, out) = thumbnail(&src, w as u32, h as u32, 8).unwrap();
        assert_eq!((dw, dh), (8, 5));
        assert!(out.chunks(4).all(|p| p == [10, 200, 30, 255]));
    }

    #[test]
    fn two_to_one_averages() {
        // 2x1: siyah | beyaz → 1x1 gri
        let src = [0u8, 0, 0, 255, 255, 255, 255, 255];
        let out = resize_rgba(&src, 2, 1, 1, 1).unwrap();
        assert_eq!(out, vec![128, 128, 128, 255]);
    }

    #[test]
    fn rejects_short_buffer_and_batch_works() {
        assert!(resize_rgba(&[0; 8], 4, 4, 2, 2).is_none());
        let a = (vec![50u8; 16 * 16 * 4], 16, 16);
        let r = thumbnail_batch(&[a.clone(), (vec![], 4, 4), a], 4);
        assert_eq!(r.len(), 3);
        assert_eq!(r[0].as_ref().map(|t| (t.0, t.1)), Some((4, 4)));
        assert!(r[1].is_none());
        assert!(r[2].is_some());
    }
}
