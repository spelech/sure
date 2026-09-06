import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dimensionBtn", "tableBody", "dataStore"];

  connect() {
    this.currentDimension = "categories";
    this.sortKey = "total";
    this.sortAsc = false;

    try {
      this.payload = JSON.parse(this.dataStoreTarget.textContent || "{}");
    } catch (e) {
      console.error("Failed to parse pivot table data:", e);
      this.payload = {};
    }

    this.updateSortIndicators();
    this.render();
  }

  switchDimension(event) {
    const dimension = event.currentTarget.dataset.dimension;
    if (!dimension) return;

    this.currentDimension = dimension;
    this.dimensionBtnTargets.forEach(btn => {
      const active = btn.dataset.dimension === this.currentDimension;
      btn.classList.toggle("bg-primary", active);
      btn.classList.toggle("text-container", active);
      btn.classList.toggle("text-secondary", !active);
    });

    this.render();
  }

  sortBy(event) {
    const key = event.currentTarget.dataset.sort;
    if (!key) return;

    if (this.sortKey === key) {
      this.sortAsc = !this.sortAsc;
    } else {
      this.sortKey = key;
      this.sortAsc = false;
    }

    this.updateSortIndicators();
    this.render();
  }

  updateSortIndicators() {
    const indicators = this.element.querySelectorAll("[data-sort-indicator]");
    indicators.forEach(el => {
      const field = el.getAttribute("data-sort-indicator");
      if (field === this.sortKey) {
        el.textContent = this.sortAsc ? "↑" : "↓";
        el.classList.add("text-primary");
      } else {
        el.textContent = "↕";
        el.classList.remove("text-primary");
      }
    });
  }

  escapeHtml(text) {
    if (text == null) return "";
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  render() {
    const rows = [...(this.payload[this.currentDimension] || [])];
    const currencySymbol = this.payload.currency_symbol || "$";

    if (rows.length === 0) {
      this.tableBodyTarget.innerHTML = `
        <tr>
          <td colspan="6" class="py-8 text-center text-secondary">
            <p class="text-xs">No outflow transactions found for this dimension in the selected period.</p>
          </td>
        </tr>
      `;
      return;
    }

    rows.sort((a, b) => {
      const valA = a[this.sortKey] ?? 0;
      const valB = b[this.sortKey] ?? 0;
      if (typeof valA === "string" || typeof valB === "string") {
        const strA = String(valA);
        const strB = String(valB);
        return this.sortAsc ? strA.localeCompare(strB) : strB.localeCompare(strA);
      }
      return this.sortAsc ? valA - valB : valB - valA;
    });

    this.tableBodyTarget.innerHTML = rows.map(r => {
      const count = Number(r.count || 0);
      const avg = Number(r.avg || 0);
      const max = Number(r.max || 0);
      const total = Number(r.total || 0);
      const percentage = Number(r.percentage || 0);
      const widthPct = Math.min(100, Math.max(0, percentage));

      return `
        <tr class="border-b border-primary/20 hover:bg-surface-hover transition-colors">
          <td class="py-3 px-4 font-medium text-primary text-xs">${this.escapeHtml(r.key)}</td>
          <td class="py-3 px-4 text-center font-mono text-secondary text-xs">${count.toLocaleString()}</td>
          <td class="py-3 px-4 text-right font-mono text-secondary text-xs">${currencySymbol}${avg.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
          <td class="py-3 px-4 text-right font-mono text-secondary text-xs">${currencySymbol}${max.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
          <td class="py-3 px-4 text-right font-bold text-destructive text-xs">${currencySymbol}${total.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
          <td class="py-3 px-4 text-right text-xs">
            <div class="flex items-center justify-end gap-2">
              <span class="font-mono text-secondary">${percentage.toFixed(1)}%</span>
              <div class="w-16 h-1.5 bg-surface-inset rounded-full overflow-hidden hidden sm:block">
                <div class="h-full bg-destructive rounded-full" style="width: ${widthPct}%"></div>
              </div>
            </div>
          </td>
        </tr>
      `;
    }).join("");
  }
}
