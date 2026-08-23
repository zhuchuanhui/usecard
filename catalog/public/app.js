const STORAGE_KEY = "usecard.web.holdings.v1";
const merchants = {
  general: { label: "指定なし", categoryIDs: [], channel: "inStore" },
  "seven-eleven": { label: "セブン-イレブン", categoryIDs: ["convenience-store"], channel: "inStore" },
  lawson: { label: "ローソン", categoryIDs: ["convenience-store"], channel: "inStore" },
  amazon: { label: "Amazon", categoryIDs: ["online-shopping"], channel: "online" },
  "rakuten-market": { label: "楽天市場", categoryIDs: ["online-shopping"], channel: "online" },
  "aeon-group": { label: "イオングループ", categoryIDs: ["supermarket"], channel: "inStore" },
  "jr-east-rail": { label: "JR東日本の鉄道", categoryIDs: ["transport"], channel: "inStore" },
  mcdonalds: { label: "マクドナルド", categoryIDs: ["restaurant"], channel: "inStore" },
  "mos-burger": { label: "モスバーガー", categoryIDs: ["restaurant"], channel: "inStore" },
  kfc: { label: "ケンタッキーフライドチキン", categoryIDs: ["restaurant"], channel: "inStore" },
  yoshinoya: { label: "吉野家", categoryIDs: ["restaurant"], channel: "inStore" },
  saizeriya: { label: "サイゼリヤ", categoryIDs: ["restaurant"], channel: "inStore" },
  gusto: { label: "ガスト", categoryIDs: ["restaurant"], channel: "inStore" },
  sukiya: { label: "すき家", categoryIDs: ["restaurant"], channel: "inStore" },
  hamazushi: { label: "はま寿司", categoryIDs: ["restaurant"], channel: "inStore" },
  doutor: { label: "ドトール", categoryIDs: ["restaurant"], channel: "inStore" }
};
const methodLabels = { physical: "カード払い", contactless: "カードのタッチ決済", mobileContactless: "スマホのタッチ決済", applePay: "Apple Pay", mobileOrder: "モバイルオーダー", online: "オンライン決済", qr: "QRコード決済" };
const state = { cards: [], alternatives: [], holdings: new Set(JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")) };
const $ = (id) => document.getElementById(id);
const normalize = (value) => String(value || "").normalize("NFKC").toLocaleLowerCase("ja").replace(/[\s・･()（）]/g, "");
const yen = (value) => new Intl.NumberFormat("ja-JP", { style: "currency", currency: "JPY", maximumFractionDigits: 0 }).format(value);
const escapeHTML = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));

function saveHoldings() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify([...state.holdings]));
  renderAll();
}

function openTab(name) {
  document.querySelectorAll(".tab-panel").forEach((panel) => { panel.hidden = panel.id !== name; panel.classList.toggle("active", panel.id === name); });
  document.querySelectorAll(".tab-button").forEach((button) => { const active = button.dataset.tab === name; button.classList.toggle("active", active); button.setAttribute("aria-current", active ? "page" : "false"); });
  history.replaceState(null, "", `#${name}`);
}

function highlight(text, query) {
  if (!query) return escapeHTML(text);
  const source = String(text); const index = source.toLocaleLowerCase("ja").indexOf(String(query).toLocaleLowerCase("ja"));
  if (index < 0) return escapeHTML(source);
  return `${escapeHTML(source.slice(0, index))}<mark>${escapeHTML(source.slice(index, index + query.length))}</mark>${escapeHTML(source.slice(index + query.length))}`;
}

function matches(card, query) { return normalize(`${card.name} ${card.issuerName || ""} ${card.eligibilityNote || ""}`).includes(normalize(query)); }

function cardRow(card, query = "") {
  const fragment = $("card-template").content.cloneNode(true); const row = fragment.querySelector(".card-row"); const held = state.holdings.has(card.id);
  row.classList.toggle("is-held", held); row.querySelector("h3").innerHTML = highlight(card.name, query); row.querySelector(".issuer").innerHTML = highlight(card.issuerName || "発行元情報なし", query);
  const fee = card.annualFeeYen === 0 ? "年会費無料" : card.annualFeeYen == null ? "年会費情報なし" : `年会費 ${yen(card.annualFeeYen)}`;
  row.querySelector(".card-meta").innerHTML = `<span>${escapeHTML(fee)}</span><span>${escapeHTML((card.networks || []).join(" / ").toUpperCase() || "決済ブランド未登録")}</span>`;
  const button = row.querySelector(".holding-button"); button.textContent = held ? "保有から外す" : "保有に追加"; button.classList.toggle("is-held", held);
  button.addEventListener("click", () => { held ? state.holdings.delete(card.id) : state.holdings.add(card.id); saveHoldings(); });
  const link = row.querySelector(".official-link"); if (card.applicationURL) link.href = card.applicationURL; else link.remove();
  return fragment;
}

function renderCatalog() {
  const query = $("catalog-search").value.trim(); const sort = $("catalog-sort").value;
  const cards = state.cards.filter((card) => matches(card, query));
  cards.sort((a, b) => {
    if (sort === "issuer") return (a.issuerName || "").localeCompare(b.issuerName || "", "ja");
    if (sort === "fee-low") return (a.annualFeeYen ?? Infinity) - (b.annualFeeYen ?? Infinity);
    if (sort === "fee-high") return (b.annualFeeYen ?? -1) - (a.annualFeeYen ?? -1);
    if (sort === "held") return Number(state.holdings.has(b.id)) - Number(state.holdings.has(a.id)) || a.name.localeCompare(b.name, "ja");
    return a.name.localeCompare(b.name, "ja");
  });
  const list = $("catalog-list"); list.replaceChildren(...cards.map((card) => cardRow(card, query)));
  $("catalog-summary").textContent = `${state.cards.length}枚の公式確認済みカード · 検索結果 ${cards.length}枚`;
}

function renderHoldings() {
  const query = $("holding-search").value.trim(); const held = state.cards.filter((card) => state.holdings.has(card.id) && matches(card, query));
  $("holdings-list").replaceChildren(...held.map((card) => cardRow(card, query))); $("holdings-empty").hidden = state.holdings.size > 0;
  $("holding-count-badge").textContent = state.holdings.size;
  const candidates = state.cards.filter((card) => !state.holdings.has(card.id) && matches(card, query)).slice(0, query ? 30 : 8);
  $("holding-candidates").innerHTML = candidates.length ? `<h2>${query ? "検索結果から追加" : "よく使われるカードから追加"}</h2><div class="card-list"></div>` : (query ? "<h2>一致するカードがありません</h2><p class=warning>カード一覧は公式確認済みデータです。未収録カードは今後の自動更新対象になります。</p>" : "");
  const target = $("holding-candidates").querySelector(".card-list"); if (target) target.replaceChildren(...candidates.map((card) => cardRow(card, query)));
}

function conditionMatches(condition, merchantID, merchant, method, amount) {
  if ((condition.merchantIDs || []).length && !condition.merchantIDs.includes(merchantID)) return false;
  if ((condition.categoryIDs || []).length && !condition.categoryIDs.some((id) => merchant.categoryIDs.includes(id))) return false;
  if ((condition.paymentMethods || []).length && !condition.paymentMethods.includes(method)) return false;
  if ((condition.channels || []).length && !condition.channels.includes(merchant.channel)) return false;
  if ((condition.eligibleDaysOfMonth || []).length && !condition.eligibleDaysOfMonth.includes(new Date().getDate())) return false;
  if (condition.minimumPurchaseYen != null && amount < condition.minimumPurchaseYen) return false;
  if (condition.maximumPurchaseYen != null && amount > condition.maximumPurchaseYen) return false;
  if (condition.enrollmentKey || condition.minimumAnnualSpendYen != null) return false;
  const today = new Date().toISOString().slice(0, 10); if (condition.activeFrom && today < condition.activeFrom) return false; if (condition.activeUntil && today > condition.activeUntil) return false;
  return true;
}

function rewardValue(reward, amount) {
  if (reward.kind === "cashbackRate") return amount * reward.ratePercent / 100;
  if (reward.kind === "pointsPerUnit") return Math.floor(amount / reward.unitAmountYen) * reward.pointsPerUnit * (reward.defaultPointValueYen || 1);
  if (reward.kind === "fixedYen") return reward.amountYen || 0;
  return 0;
}

function evaluate(product, merchantID, amount, isAlternative = false) {
  const merchant = merchants[merchantID]; const methods = merchant.channel === "online" ? ["online", "applePay"] : ["physical", "contactless", "mobileContactless", "applePay", "mobileOrder", "qr"];
  const explicitlyLimited = isAlternative && (product.benefitRules || []).some((rule) => (rule.conditions?.merchantIDs || []).length);
  const unavailableHere = explicitlyLimited && merchantID !== "general" && !(product.benefitRules || []).some((rule) => (rule.conditions?.merchantIDs || []).includes(merchantID));
  const routes = methods.map((method) => {
    const groups = new Map();
    for (const rule of product.benefitRules || []) {
      if (!conditionMatches(rule.conditions || {}, merchantID, merchant, method, amount)) continue;
      const value = rewardValue(rule.reward || {}, amount); const group = rule.stackingGroup || rule.id;
      if (!groups.has(group) || groups.get(group).value < value) groups.set(group, { value, title: rule.title });
    }
    return { method, value: [...groups.values()].reduce((sum, item) => sum + item.value, 0), benefits: [...groups.values()].filter((item) => item.value > 0).map((item) => item.title) };
  });
  const best = routes.sort((a, b) => b.value - a.value)[0];
  return { ...product, ...best, value: unavailableHere ? 0 : best.value, isAlternative, acceptanceUnverified: isAlternative && !explicitlyLimited, rate: amount && !unavailableHere ? best.value / amount * 100 : 0, applicationURL: product.applicationURL || product.sources?.[0]?.url };
}

function resultCard(item, rank, amount) {
  const net = item.isAlternative ? item.value : item.value - (item.annualFeeYen || 0);
  const feeNote = !item.isAlternative && !state.holdings.has(item.id) && item.annualFeeYen > 0 ? `初年度比較値 ${yen(net)}（年会費差引）` : "";
  return `<article class="result-card ${rank === 1 ? "best" : ""}"><div class="rank">${rank === 1 ? "BEST" : `#${rank}`}</div><h3>${escapeHTML(item.name)}</h3><p class="saving">${yen(item.value)}相当</p><p class="rate">実質 ${item.rate.toFixed(2)}% · ${yen(amount)}利用時</p><p class="method">${escapeHTML(item.paymentLabel || methodLabels[item.method] || item.method)}</p><p class="benefits">${escapeHTML(item.benefits.join(" ＋ ") || "適用可能な確定特典なし")}</p>${item.acceptanceUnverified ? `<p class="warning">この店舗で利用できるか確認が必要です</p>` : ""}${feeNote ? `<p class="warning">${escapeHTML(feeNote)}</p>` : ""}${item.applicationURL ? `<a href="${escapeHTML(item.applicationURL)}" target="_blank" rel="noopener noreferrer">公式情報を確認 ↗</a>` : ""}</article>`;
}

function resultSection(title, items, amount, emptyText) {
  return `<section class="result-section"><h2>${escapeHTML(title)}</h2>${items.length ? `<div class="result-grid">${items.slice(0, 3).map((item, index) => resultCard(item, index + 1, amount)).join("")}</div>` : `<div class="empty-state compact"><span>−</span><p>${escapeHTML(emptyText)}</p></div>`}</section>`;
}

function recommend() {
  const merchantID = $("merchant-select").value; const amount = Number($("amount-input").value); if (!amount || amount < 1) return;
  const evaluated = state.cards.map((card) => evaluate(card, merchantID, amount));
  const held = evaluated.filter((item) => state.holdings.has(item.id)).sort((a, b) => b.value - a.value);
  const available = evaluated.filter((item) => !state.holdings.has(item.id) && item.applicationStatus === "open").sort((a, b) => (b.value - (b.annualFeeYen || 0)) - (a.value - (a.annualFeeYen || 0)));
  const alternatives = state.alternatives.map((item) => evaluate(item, merchantID, amount, true)).filter((item) => item.value > 0).sort((a, b) => b.value - a.value);
  $("recommend-empty").hidden = true; $("recommend-results").hidden = false;
  $("recommend-results").innerHTML = `<p class="warning">${escapeHTML(merchants[merchantID].label)}での確定条件だけを比較。要登録・年間利用額条件など未設定の特典は除外しています。</p>${resultSection("手持ちカードのおすすめ", held, amount, "手持ちカードを追加すると、ここに最適なカードが表示されます。")}${resultSection("カード以外の支払い方", alternatives, amount, "この利用先に適用できる登録済み支払い方法はありません。")}${resultSection("持っていないカードも含む", available, amount, "申込受付中の比較対象がありません。")}`;
}

function renderAll() { renderCatalog(); renderHoldings(); }

document.querySelectorAll(".tab-button").forEach((button) => button.addEventListener("click", () => openTab(button.dataset.tab)));
document.querySelectorAll("[data-open-tab]").forEach((button) => button.addEventListener("click", () => openTab(button.dataset.openTab)));
$("catalog-search").addEventListener("input", renderCatalog); $("catalog-sort").addEventListener("change", renderCatalog); $("holding-search").addEventListener("input", renderHoldings);
$("recommend-form").addEventListener("submit", (event) => { event.preventDefault(); recommend(); });

Promise.all([fetch("latest.json").then((response) => response.json()), fetch("payment-alternatives.json").then((response) => response.json())]).then(([catalog, alternatives]) => {
  state.cards = catalog.products || []; state.alternatives = alternatives.products || []; renderAll();
  $("catalog-status").textContent = `${state.cards.length}枚 · ${new Date(catalog.generatedAt).toLocaleDateString("ja-JP")}更新`; document.querySelector(".status-dot").classList.add("ready");
}).catch(() => { $("catalog-status").textContent = "カード情報を読み込めません"; });
openTab(location.hash.slice(1) && $(location.hash.slice(1)) ? location.hash.slice(1) : "recommend");
if ("serviceWorker" in navigator) navigator.serviceWorker.register("service-worker.js").catch(() => {});
