import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["grid", "dataStore", "merchantSelect", "summaryStats", "tooltip"];

  connect() {
    this.selectedMerchant = "all";

    try {
      this.data = JSON.parse(this.dataStoreTarget.textContent || "{}");
    } catch (e) {
      console.error("Failed to parse temporal heatmap data:", e);
      this.data = { days: [], top_merchants: [], total_year_spend: 0.0, currency_symbol: "$" };
    }

    this.populateMerchantSelect();
    this.render();
  }

  populateMerchantSelect() {
    if (!this.hasMerchantSelectTarget) return;

    const merchants = this.data.top_merchants || [];
    const currency = this.data.currency_symbol || "$";

    // Keep the "all" option and append top merchants if not already present
    this.merchantSelectTarget.innerHTML = `
      <option value="all">All Outflows (Consolidated)</option>
      ${merchants.map(m => `
        <option value="${this.escapeHtml(m.id || m.name)}">
          ${this.escapeHtml(m.name)} (${currency}${Number(m.total || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })})
        </option>
      `).join("")}
    `;
  }

  filterMerchant(event) {
    this.selectedMerchant = event.target.value;
    this.render();
  }

  escapeHtml(text) {
    if (text == null) return "";
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  getCellTierClass(total) {
    if (total <= 0.001) {
      return "bg-surface-inset opacity-40 border border-primary/10";
    }
    if (total < 25) {
      return "bg-emerald-950/70 border border-emerald-800/40 text-emerald-300";
    }
    if (total < 75) {
      return "bg-emerald-700/80 border border-emerald-600/50 text-emerald-100";
    }
    if (total < 200) {
      return "bg-emerald-500 border border-emerald-400 text-white";
    }
    return "bg-purple-600 border border-purple-400 text-white shadow-[0_0_8px_rgba(168,85,247,0.4)]";
  }

  render() {
    const rawDays = this.data.days || [];
    const currency = this.data.currency_symbol || "$";
    const selectedMerchantObj = this.selectedMerchant === "all"
      ? null
      : (this.data.top_merchants || []).find(m => (m.id === this.selectedMerchant || m.name === this.selectedMerchant));

    // Calculate effective day amounts based on active filter
    let totalSpend = 0.0;
    let activeDays = 0;
    let maxSpend = 0.0;

    const mappedDays = rawDays.map(day => {
      let dayTotal = 0.0;
      let dayCount = 0;

      if (selectedMerchantObj) {
        dayTotal = selectedMerchantObj.daily_totals?.[day.date] || 0.0;
        dayCount = dayTotal > 0 ? 1 : 0;
      } else {
        dayTotal = Number(day.total || 0);
        dayCount = Number(day.count || 0);
      }

      if (dayTotal > 0.001) {
        totalSpend += dayTotal;
        activeDays += 1;
        if (dayTotal > maxSpend) maxSpend = dayTotal;
      }

      return {
        ...day,
        total: dayTotal,
        count: dayCount
      };
    });

    const avgActiveSpend = activeDays > 0 ? (totalSpend / activeDays) : 0.0;

    // 1. Update Summary Stats KPI Target
    this.renderSummaryStats({
      totalSpend,
      activeDays,
      maxSpend,
      avgActiveSpend,
      currency,
      totalDays: mappedDays.length
    });

    // 2. Build 53-week calendar matrix
    this.renderGrid(mappedDays, currency);
  }

  renderSummaryStats({ totalSpend, activeDays, maxSpend, avgActiveSpend, currency, totalDays }) {
    if (!this.hasSummaryStatsTarget) return;

    this.summaryStatsTarget.innerHTML = `
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="bg-surface-inset/60 border border-primary/20 rounded-xl p-3.5">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-secondary">365-Day Total Spend</p>
          <p class="text-lg font-bold font-mono text-destructive mt-1">${currency}${totalSpend.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</p>
          <p class="text-[10px] text-secondary mt-0.5">${activeDays} spend days / ${totalDays} total</p>
        </div>

        <div class="bg-surface-inset/60 border border-primary/20 rounded-xl p-3.5">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-secondary">Active Spend Days</p>
          <p class="text-lg font-bold font-mono text-primary mt-1">${activeDays} <span class="text-xs font-normal text-secondary">days</span></p>
          <p class="text-[10px] text-secondary mt-0.5">${((activeDays / Math.max(1, totalDays)) * 100).toFixed(1)}% of the year</p>
        </div>

        <div class="bg-surface-inset/60 border border-primary/20 rounded-xl p-3.5">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-secondary">Single-Day High</p>
          <p class="text-lg font-bold font-mono text-primary mt-1">${currency}${maxSpend.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</p>
          <p class="text-[10px] text-secondary mt-0.5">Peak single-day outflow</p>
        </div>

        <div class="bg-surface-inset/60 border border-primary/20 rounded-xl p-3.5">
          <p class="text-[10px] font-semibold uppercase tracking-wider text-secondary">Avg Active Day Spend</p>
          <p class="text-lg font-bold font-mono text-primary mt-1">${currency}${avgActiveSpend.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</p>
          <p class="text-[10px] text-secondary mt-0.5">Average when spend occurs</p>
        </div>
      </div>
    `;
  }

  renderGrid(days, currency) {
    if (!this.hasGridTarget) return;

    if (days.length === 0) {
      this.gridTarget.innerHTML = `
        <div class="py-12 text-center text-secondary text-xs">
          No spending data recorded in the last 365 days.
        </div>
      `;
      return;
    }

    // Group into 53 weeks (columns) x 7 days (rows, Sun=0 to Sat=6)
    const weeks = [];
    let currentWeek = [];

    const firstDay = days[0];
    const firstWday = firstDay.day_of_week; // 0 = Sun, 6 = Sat

    // Pad beginning of first week
    for (let i = 0; i < firstWday; i++) {
      currentWeek.push({ empty: true, day_of_week: i });
    }

    days.forEach(day => {
      currentWeek.push({ ...day, empty: false });
      if (day.day_of_week === 6) {
        weeks.push(currentWeek);
        currentWeek = [];
      }
    });

    // Pad end of last week
    if (currentWeek.length > 0) {
      while (currentWeek.length < 7) {
        currentWeek.push({ empty: true, day_of_week: currentWeek.length });
      }
      weeks.push(currentWeek);
    }

    // Month headers
    const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const monthHeaders = [];
    let lastMonth = null;

    weeks.forEach((week, colIdx) => {
      const firstValid = week.find(d => !d.empty);
      if (firstValid && firstValid.month !== lastMonth) {
        monthHeaders.push({
          label: monthNames[firstValid.month - 1] || "",
          colIdx
        });
        lastMonth = firstValid.month;
      }
    });

    // Day of week labels (left column)
    const dayLabels = [
      { label: "Sun", show: true },
      { label: "Mon", show: false },
      { label: "Tue", show: true },
      { label: "Wed", show: false },
      { label: "Thu", show: true },
      { label: "Fri", show: false },
      { label: "Sat", show: true }
    ];

    const cellWidthPx = 13;
    const gapPx = 3;
    const stepPx = cellWidthPx + gapPx;

    const monthHeaderHtml = monthHeaders.map(m => {
      const leftPos = m.colIdx * stepPx;
      return `
        <span class="absolute text-[10px] font-medium text-secondary uppercase tracking-wider" style="left: ${leftPos}px;">
          ${m.label}
        </span>
      `;
    }).join("");

    const dayLabelsHtml = dayLabels.map(d => `
      <div class="h-[13px] flex items-center text-[9px] font-semibold text-secondary select-none leading-none">
        ${d.show ? d.label : ""}
      </div>
    `).join("");

    const weeksGridHtml = weeks.map((week, wIdx) => {
      const daysHtml = week.map(cell => {
        if (cell.empty) {
          return `<div class="w-[13px] h-[13px] rounded-[2px] bg-transparent"></div>`;
        }

        const tierClass = this.getCellTierClass(cell.total);
        const formattedAmount = `${currency}${cell.total.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
        const dateObj = new Date(cell.date + "T00:00:00");
        const formattedDate = dateObj.toLocaleDateString(undefined, {
          weekday: "short",
          month: "short",
          day: "numeric",
          year: "numeric"
        });
        const titleText = `${formattedDate}: ${formattedAmount} (${cell.count} ${cell.count === 1 ? 'transaction' : 'transactions'})`;

        return `
          <div
            class="w-[13px] h-[13px] rounded-[2px] cursor-pointer transition-all hover:scale-125 hover:z-10 relative ${tierClass}"
            title="${this.escapeHtml(titleText)}"
            data-date="${cell.date}"
            data-total="${cell.total}"
            data-count="${cell.count}"
            data-action="mouseenter->forensics--heatmap#showTooltip mouseleave->forensics--heatmap#hideTooltip"
          ></div>
        `;
      }).join("");

      return `<div class="flex flex-col gap-[3px]">${daysHtml}</div>`;
    }).join("");

    this.gridTarget.innerHTML = `
      <div class="min-w-max select-none pb-1">
        <!-- Month Header Row -->
        <div class="flex items-center mb-2">
          <div class="w-8 shrink-0"></div>
          <div class="relative h-4 flex-1">
            ${monthHeaderHtml}
          </div>
        </div>

        <!-- Heatmap Body: Day Labels + Week Columns -->
        <div class="flex items-start gap-2">
          <div class="flex flex-col gap-[3px] w-8 shrink-0 pt-0.5">
            ${dayLabelsHtml}
          </div>
          <div class="flex items-center gap-[3px]">
            ${weeksGridHtml}
          </div>
        </div>
      </div>
    `;
  }

  showTooltip(event) {
    const el = event.currentTarget;
    const date = el.dataset.date;
    const total = Number(el.dataset.total || 0);
    const count = Number(el.dataset.count || 0);
    const currency = this.data.currency_symbol || "$";

    if (!date || !this.hasTooltipTarget) return;

    const dateObj = new Date(date + "T00:00:00");
    const formattedDate = dateObj.toLocaleDateString(undefined, {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric"
    });

    this.tooltipTarget.innerHTML = `
      <div class="font-semibold text-primary">${formattedDate}</div>
      <div class="text-destructive font-mono font-bold">${currency}${total.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
      <div class="text-secondary text-[10px]">${count} ${count === 1 ? 'transaction' : 'transactions'}</div>
    `;

    this.tooltipTarget.classList.remove("hidden");

    // Position tooltip relative to viewport/cell
    const rect = el.getBoundingClientRect();
    const tooltipRect = this.tooltipTarget.getBoundingClientRect();
    const top = rect.top - tooltipRect.height - 8;
    const left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);

    this.tooltipTarget.style.top = `${Math.max(10, top)}px`;
    this.tooltipTarget.style.left = `${Math.max(10, Math.min(window.innerWidth - tooltipRect.width - 10, left))}px`;
  }

  hideTooltip() {
    if (!this.hasTooltipTarget) return;
    this.tooltipTarget.classList.add("hidden");
  }
}
