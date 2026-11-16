// Araç çubuğu simgesine tıklanınca (veya sağ tık menüsünden) linki Mac uygulamasına
// notlarim://add?t=... adresiyle iletir. Adres, sayfanın içinden değil Chrome'un kendi
// sekme API'siyle açılır; böylece "kullanıcı etkileşimi yok" engeline takılmaz.

const tr = (chrome.i18n.getUILanguage() || '').startsWith('tr');

function encode(s) {
  return encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

function badge(tabId, text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: '', tabId }), 2000);
}

async function send(url, tabId, title) {
  if (!url || !/^https?:\/\//i.test(url)) { badge(tabId, '!', '#c0392b'); return; }
  let target = 'notlarim://add?t=' + encode(url);
  if (title && title !== url) target += '&s=' + encode(title);   // sayfa başlığı (tarayıcının bildiği)
  try {
    // Sayfa değişmez: harici uygulama adresleri sekmede açılmaz, doğrudan uygulamaya devredilir.
    await chrome.tabs.update(tabId, { url: target });
    badge(tabId, '✓', '#2e8b57');
  } catch (e) {
    // Yedek yol: geçici sekme açıp kapat
    try {
      const t = await chrome.tabs.create({ url: target, active: false });
      setTimeout(() => chrome.tabs.remove(t.id).catch(() => {}), 1500);
      badge(tabId, '✓', '#2e8b57');
    } catch (e2) { badge(tabId, '!', '#c0392b'); }
  }
}

chrome.action.onClicked.addListener(tab => send(tab.url, tab.id, tab.title));

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'page', title: tr ? "Notlarım'a gönder" : 'Send to My Notes', contexts: ['page'] });
  chrome.contextMenus.create({ id: 'link', title: tr ? "Linki Notlarım'a gönder" : 'Send link to My Notes', contexts: ['link'] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === 'link') send(info.linkUrl, tab.id);          // başlık bilinmez: uygulama sayfadan alır
  else send(info.pageUrl || tab.url, tab.id, tab.title);
});
