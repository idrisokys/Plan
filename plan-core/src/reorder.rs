//! Düzenleme modunda yukarı / aşağı / başa / sona alma (saf mantık; sıra kaydı store::save_order ile).

use crate::entry::Entry;
use std::collections::HashSet;

fn selected_indices(list: &[Entry], sel: &HashSet<String>) -> Vec<usize> {
    (0..list.len()).filter(|&i| sel.contains(&list[i].key)).collect()
}

/// Yukarı alınabilir mi? (işaretliler başa toplanmışsa pasif)
pub fn can_move_up(list: &[Entry], sel: &HashSet<String>) -> bool {
    selected_indices(list, sel).iter().enumerate().any(|(off, &i)| i != off)
}

pub fn can_move_down(list: &[Entry], sel: &HashSet<String>) -> bool {
    let s = selected_indices(list, sel);
    let n = s.len();
    s.iter().enumerate().any(|(off, &i)| i != list.len() - n + off)
}

/// mode: -1 bir yukarı, 1 bir aşağı, -2 başa al, 2 sona al. Sıra değiştiyse true.
pub fn move_selected(list: &mut Vec<Entry>, sel: &HashSet<String>, mode: i32) -> bool {
    if sel.is_empty() || list.len() < 2 {
        return false;
    }
    let before: Vec<String> = list.iter().map(|e| e.key.clone()).collect();
    match mode {
        -1 => {
            for i in 1..list.len() {
                if sel.contains(&list[i].key) && !sel.contains(&list[i - 1].key) {
                    list.swap(i, i - 1);
                }
            }
        }
        1 => {
            for i in (0..list.len() - 1).rev() {
                if sel.contains(&list[i].key) && !sel.contains(&list[i + 1].key) {
                    list.swap(i, i + 1);
                }
            }
        }
        -2 | 2 => {
            let (a, b): (Vec<Entry>, Vec<Entry>) = list.drain(..).partition(|e| sel.contains(&e.key));
            *list = if mode == -2 { a.into_iter().chain(b).collect() } else { b.into_iter().chain(a).collect() };
        }
        _ => return false,
    }
    list.iter().map(|e| e.key.clone()).collect::<Vec<_>>() != before
}
