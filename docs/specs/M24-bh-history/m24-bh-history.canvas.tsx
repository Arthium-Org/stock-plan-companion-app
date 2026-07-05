/**
 * M24 ESPP History — visual mock (§A–F).
 *
 * Git copy for reviewers and Claude. Live Canvas preview uses the same file under:
 * ~/.cursor/projects/Users-kirandev-Projects-wealth-management-stock-plan/canvases/
 *
 * Spec: ux-design.md · When editing UX, update both copies (or re-copy from canvases/).
 */
import {
  Button,
  Callout,
  Card,
  CardBody,
  Grid,
  H1,
  H2,
  Pill,
  Row,
  Select,
  Spacer,
  Stack,
  Stat,
  Table,
  Text,
  Toggle,
  useCanvasState,
  useHostTheme,
  type CanvasHostTheme,
} from "cursor/canvas";

type Currency = "INR" | "USD";
type Plan = "RSU" | "ESPP";
type Scenario = "empty" | "loaded";
type Density = "normal" | "dense";

type EsppLot = {
  purchaseDate: string;
  gross: string;
  net: string;
  buyPrice: string;
  fmv: string;
  discPct: string;
  sold: string;
  held: string;
  realPnl: string;
  unrealPnl: string;
  netBuyPriceNum: number;
  soldQty: number;
  heldQty: number;
  returnPct: number | null;
};

type SoldBar = { label: string; returnPct: number; pnl: number; partial: boolean };
type UnsoldDot = {
  label: string;
  netBuyPrice: number;
  unrealizedPnl: number;
  unrealizedPct: number;
  heldQty: number;
};

type EsppData = {
  currentPrice: number;
  grossPurchased: number;
  netReceived: number;
  taxWithheld: number;
  purchaseValue: number;
  currentlyHeld: number;
  netDiscountValue: number;
  realizedProceeds: number;
  realizedPnl: number;
  unrealizedPnl: number;
  totalPnl: number;
  totalReturnPct: string;
  xirr: string;
  day1Gain: number;
  opportunityExtra: number;
  holdingBetter: boolean;
  qualifyingCount: number;
  disqualifyingCount: number;
  qualifyingProceeds: number;
  disqualifyingProceeds: number;
  lots: EsppLot[];
  soldBars: SoldBar[];
  unsoldDots: UnsoldDot[];
};

type SymbolData = { price: string; espp: EsppData };

const FX = 83;
const MONTHS = ["Jun", "Dec"] as const;

function ReturnPct({ value }: { value: string }) {
  const theme = useHostTheme();
  const positive = value.startsWith("+");
  const negative = value.startsWith("-");
  return (
    <span
      style={{
        color: positive
          ? theme.palette.diffStripAdded
          : negative
            ? theme.palette.diffStripRemoved
            : theme.text.primary,
        fontWeight: 600,
      }}
    >
      {value}
    </span>
  );
}

function fmtMoney(amount: number, currency: Currency): string {
  const scaled = currency === "INR" ? amount * FX : amount;
  if (currency === "USD") {
    if (Math.abs(scaled) >= 1_000_000) return `$${(scaled / 1_000_000).toFixed(2)}M`;
    if (Math.abs(scaled) >= 10_000) return `$${(scaled / 1_000).toFixed(1)}k`;
    return `$${Math.round(scaled).toLocaleString()}`;
  }
  if (Math.abs(scaled) >= 10_000_000) return `₹${(scaled / 10_000_000).toFixed(2)} Cr`;
  if (Math.abs(scaled) >= 100_000) return `₹${(scaled / 100_000).toFixed(1)} L`;
  return `₹${Math.round(scaled).toLocaleString("en-IN")}`;
}

function scaleMoney(amount: number, currency: Currency): number {
  return currency === "INR" ? amount * FX : amount;
}

function fmtSignedMoney(amount: number, currency: Currency): string {
  const sign = amount >= 0 ? "+" : "";
  return `${sign}${fmtMoney(amount, currency)}`;
}

function lotRow(
  date: string,
  gross: number,
  net: number,
  buy: number,
  fmv: number,
  sold: number,
  held: number,
  current: number,
): EsppLot {
  const netBuy = (buy * gross) / net;
  const realPnl = sold > 0 ? (fmv * 0.95 - netBuy) * sold : 0;
  const unrealPnl = held > 0 ? (current - netBuy) * held : 0;
  const returnPct = sold > 0 ? (realPnl / (netBuy * sold)) * 100 : null;
  return {
    purchaseDate: date,
    gross: gross.toFixed(1),
    net: net.toFixed(1),
    buyPrice: `$${buy.toFixed(2)}`,
    fmv: `$${fmv.toFixed(2)}`,
    discPct: `${(((fmv - buy) / buy) * 100).toFixed(1)}%`,
    sold: sold > 0 ? sold.toFixed(1) : "—",
    held: held > 0 ? held.toFixed(1) : "—",
    realPnl: sold > 0 ? fmtSignedMoney(realPnl, "USD") : "—",
    unrealPnl: held > 0 ? fmtSignedMoney(unrealPnl, "USD") : "—",
    netBuyPriceNum: netBuy,
    soldQty: sold,
    heldQty: held,
    returnPct,
  };
}

function buildAdbeLots(dense: boolean, currentPrice: number): EsppLot[] {
  if (!dense) {
    return [
      lotRow("30-Jun-2023", 42.1, 40.8, 127.5, 150.0, 28.3, 12.5, currentPrice),
      lotRow("31-Dec-2023", 38.6, 37.2, 145.2, 170.8, 37.2, 0, currentPrice),
      lotRow("28-Jun-2024", 45.0, 43.5, 168.4, 198.1, 0, 43.5, currentPrice),
      lotRow("31-Dec-2024", 41.2, 39.8, 182.6, 214.8, 0, 39.8, currentPrice),
      lotRow("30-Jun-2022", 35.0, 33.9, 98.4, 115.8, 20.0, 13.9, currentPrice),
      lotRow("31-Dec-2022", 33.2, 32.1, 112.5, 132.4, 32.1, 0, currentPrice),
      lotRow("28-Jun-2025", 48.0, 46.4, 195.0, 229.4, 0, 46.4, currentPrice),
      lotRow("31-Dec-2025", 44.5, 43.0, 210.8, 248.0, 0, 43.0, currentPrice),
    ];
  }
  const lots: EsppLot[] = [];
  for (let y = 2018; y <= 2025; y++) {
    for (const m of MONTHS) {
      const gross = 30 + ((y * 7 + (m === "Jun" ? 3 : 9)) % 18);
      const net = gross - (gross > 35 ? 1.2 : 0.8);
      const buy = 80 + y * 8 + (m === "Dec" ? 12 : 0);
      const fmv = buy / 0.85;
      const sold = y < 2024 || m === "Jun" ? net * 0.6 : 0;
      const held = net - sold;
      lots.push(
        lotRow(
          `30-${m}-${y}`,
          gross,
          net,
          buy,
          fmv,
          Math.round(sold * 10) / 10,
          Math.round(held * 10) / 10,
          currentPrice,
        ),
      );
    }
  }
  return lots;
}

function aggregateEspp(lots: EsppLot[], currentPrice: number, meta: Partial<EsppData>): EsppData {
  const grossPurchased = lots.reduce((s, l) => s + parseFloat(l.gross), 0);
  const netReceived = lots.reduce((s, l) => s + parseFloat(l.net), 0);
  const taxWithheld = Math.round((grossPurchased - netReceived) * 10) / 10;
  const currentlyHeld = lots.reduce((s, l) => s + l.heldQty, 0);
  const purchaseValue = lots.reduce(
    (s, l) => s + parseFloat(l.buyPrice.slice(1)) * parseFloat(l.gross),
    0,
  );
  const netDiscountValue = lots.reduce((s, l) => {
    const buy = parseFloat(l.buyPrice.slice(1));
    const fmv = parseFloat(l.fmv.slice(1));
    return s + (fmv - buy) * parseFloat(l.net);
  }, 0);
  const realizedPnl = lots.reduce((s, l) => {
    if (l.soldQty <= 0) return s;
    const n = parseFloat(l.realPnl.replace(/[^0-9.-]/g, ""));
    return s + n;
  }, 0);
  const unrealizedPnl = lots.reduce((s, l) => {
    if (l.heldQty <= 0) return s;
    const n = parseFloat(l.unrealPnl.replace(/[^0-9.-]/g, ""));
    return s + n;
  }, 0);
  const totalPnl = realizedPnl + unrealizedPnl;
  const totalReturnPct = `+${((totalPnl / purchaseValue) * 100).toFixed(1)}%`;
  const realizedProceeds = lots.reduce((s, l) => {
    if (l.soldQty <= 0) return s;
    const fmv = parseFloat(l.fmv.slice(1));
    return s + fmv * 0.95 * l.soldQty;
  }, 0);

  const soldBars: SoldBar[] = lots
    .filter((l) => l.soldQty > 0 && l.returnPct != null)
    .map((l) => ({
      label: l.purchaseDate.slice(3, 10).replace("-", " '"),
      returnPct: l.returnPct!,
      pnl: parseFloat(l.realPnl.replace(/[^0-9.-]/g, "")),
      partial: l.heldQty > 0,
    }));

  const unsoldDots: UnsoldDot[] = lots
    .filter((l) => l.heldQty > 0)
    .map((l) => ({
      label: l.purchaseDate.slice(3, 10).replace("-", " '"),
      netBuyPrice: l.netBuyPriceNum,
      unrealizedPnl: parseFloat(l.unrealPnl.replace(/[^0-9.-]/g, "")),
      unrealizedPct: ((currentPrice - l.netBuyPriceNum) / l.netBuyPriceNum) * 100,
      heldQty: l.heldQty,
    }));

  return {
    currentPrice,
    grossPurchased: Math.round(grossPurchased),
    netReceived: Math.round(netReceived),
    taxWithheld,
    purchaseValue: Math.round(purchaseValue),
    currentlyHeld: Math.round(currentlyHeld * 10) / 10,
    netDiscountValue: Math.round(netDiscountValue),
    realizedProceeds: Math.round(realizedProceeds),
    realizedPnl: Math.round(realizedPnl),
    unrealizedPnl: Math.round(unrealizedPnl),
    totalPnl: Math.round(totalPnl),
    totalReturnPct,
    xirr: meta.xirr ?? "18.4%",
    day1Gain: meta.day1Gain ?? Math.round(netDiscountValue),
    opportunityExtra: meta.opportunityExtra ?? Math.round(totalPnl - netDiscountValue),
    holdingBetter: meta.holdingBetter ?? totalPnl > netDiscountValue,
    qualifyingCount: meta.qualifyingCount ?? 3,
    disqualifyingCount: meta.disqualifyingCount ?? 2,
    qualifyingProceeds: meta.qualifyingProceeds ?? 84_200,
    disqualifyingProceeds: meta.disqualifyingProceeds ?? 31_400,
    lots,
    soldBars,
    unsoldDots,
  };
}

function getSymbolData(symbol: string, density: Density): SymbolData {
  if (symbol === "CRM") {
    const lots = [
      lotRow("30-Jun-2023", 22.4, 21.8, 168.3, 198.0, 21.8, 0, 298.64),
      lotRow("31-Dec-2024", 19.8, 19.2, 208.25, 245.0, 0, 19.2, 298.64),
    ];
    return {
      price: "$298.64",
      espp: aggregateEspp(lots, 298.64, {
        xirr: "14.2%",
        opportunityExtra: -7_100,
        holdingBetter: false,
        qualifyingCount: 1,
        disqualifyingCount: 1,
        qualifyingProceeds: 22_100,
        disqualifyingProceeds: 18_400,
      }),
    };
  }
  const lots = buildAdbeLots(density === "dense", 453.21);
  return {
    price: "$453.21",
    espp: aggregateEspp(lots, 453.21, {
      xirr: "18.4%",
      opportunityExtra: 23_940,
      holdingBetter: true,
    }),
  };
}

/** Sold chart Y domain: always includes 0%; no fake negative range when all returns are positive. */
function soldChartYDomain(returnPcts: number[]): { yMin: number; yMax: number; ticks: number[] } {
  const pad = 0.12;
  const dataMin = Math.min(...returnPcts, 0);
  const dataMax = Math.max(...returnPcts, 0);

  let yMin: number;
  let yMax: number;

  if (dataMin >= 0) {
    yMin = 0;
    yMax = Math.max(dataMax * (1 + pad), 8);
  } else if (dataMax <= 0) {
    yMin = dataMin * (1 + pad);
    yMax = 0;
  } else {
    const absMax = Math.max(Math.abs(dataMin), Math.abs(dataMax));
    yMin = -absMax * (1 + pad);
    yMax = absMax * (1 + pad);
  }

  const ticks = new Set<number>([0]);
  if (yMin < 0) ticks.add(Math.round(yMin));
  if (yMax > 0) ticks.add(Math.round(yMax));
  const mid = (yMin + yMax) / 2;
  if (mid !== 0 && Math.abs(mid) > 1) ticks.add(Math.round(mid));

  return { yMin, yMax, ticks: [...ticks].sort((a, b) => a - b) };
}

function chartLayout(n: number) {
  const ml = 48;
  const mr = 16;
  const minSlot = 36;
  const defaultWidth = 600;
  const plotDefault = defaultWidth - ml - mr;
  const needsScroll = n * minSlot > plotDefault;
  const svgWidth = needsScroll ? n * minSlot + ml + mr : defaultWidth;
  const plotWidth = svgWidth - ml - mr;
  const slot = plotWidth / n;
  const maxLabels = Math.floor(plotWidth / 48);
  const labelStep = n <= maxLabels ? 1 : n <= maxLabels * 2 ? 2 : 3;
  return { ml, mr, svgWidth, plotWidth, slot, needsScroll, labelStep, n };
}

function SoldReturnsChart({
  bars,
  currency,
}: {
  bars: SoldBar[];
  currency: Currency;
}) {
  const theme = useHostTheme();
  const n = bars.length;
  if (n === 0) return null;
  const { ml, svgWidth, plotWidth, slot, needsScroll, labelStep } = chartLayout(n);
  const height = 220;
  const mt = 16;
  const mb = 36;
  const plotH = height - mt - mb;
  const returnPcts = bars.map((b) => b.returnPct);
  const { yMin, yMax, ticks } = soldChartYDomain(returnPcts);
  const yScale = (v: number) => mt + plotH - ((v - yMin) / (yMax - yMin)) * plotH;
  const zeroY = yScale(0);
  const plotBottom = height - mb;

  return (
    <Stack gap={6}>
      <div style={{ overflowX: needsScroll ? "auto" : "visible", width: "100%" }}>
        <svg width={svgWidth} height={height} style={{ display: "block", minWidth: needsScroll ? svgWidth : undefined }}>
          <line x1={ml} y1={mt} x2={ml} y2={plotBottom} stroke={theme.stroke.primary} strokeWidth={1} />
          <line x1={ml} y1={plotBottom} x2={ml + plotWidth} y2={plotBottom} stroke={theme.stroke.primary} strokeWidth={1} />
          <line x1={ml} y1={zeroY} x2={ml + plotWidth} y2={zeroY} stroke={theme.stroke.secondary} strokeDasharray="4 3" />
          {ticks.map((tick) => (
            <text key={tick} x={ml - 6} y={yScale(tick) + 4} textAnchor="end" fill={theme.text.tertiary} fontSize={10}>
              {tick === 0 ? "0%" : `${tick > 0 ? "+" : ""}${tick}%`}
            </text>
          ))}
          {bars.map((bar, i) => {
            const cx = ml + slot * i + slot / 2;
            const bw = slot * (n > 24 ? 0.35 : n > 12 ? 0.4 : 0.5);
            const top = yScale(Math.max(bar.returnPct, 0));
            const bottom = yScale(Math.min(bar.returnPct, 0));
            const color =
              bar.returnPct >= 0 ? theme.palette.diffStripAdded : theme.palette.diffStripRemoved;
            const showLabel = i % labelStep === 0 || i === n - 1;
            return (
              <g key={bar.label}>
                <rect
                  x={cx - bw / 2}
                  y={Math.min(top, bottom)}
                  width={bw}
                  height={Math.abs(bottom - top) || 2}
                  fill={color}
                  rx={2}
                >
                  <title>
                    {bar.label}
                    {"\n"}Return: {bar.returnPct >= 0 ? "+" : ""}
                    {bar.returnPct.toFixed(1)}%
                    {"\n"}P&L: {fmtSignedMoney(bar.pnl, currency)}
                    {bar.partial ? "\nPartial sale — see hover for held qty" : ""}
                  </title>
                </rect>
                <text x={cx} y={Math.min(top, bottom) - 4} textAnchor="middle" fill={color} fontSize={9} fontWeight={600}>
                  {bar.returnPct >= 0 ? "+" : ""}
                  {bar.returnPct.toFixed(1)}%
                </text>
                {showLabel && (
                  <text x={cx} y={height - 8} textAnchor="middle" fill={theme.text.secondary} fontSize={10}>
                    {bar.label}
                    {bar.partial ? "*" : ""}
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>
      {needsScroll && (
        <Text size="small" tone="tertiary">
          Scroll chart → · {n} purchases — hover for full date, proceeds, and qty
        </Text>
      )}
      {bars.some((b) => b.partial) && (
        <Text size="small" tone="tertiary">
          * Partial sale — full purchase date and held qty in hover
        </Text>
      )}
    </Stack>
  );
}

function UnsoldScatterChart({
  dots,
  currentPrice,
  currency,
}: {
  dots: UnsoldDot[];
  currentPrice: number;
  currency: Currency;
}) {
  const theme = useHostTheme();
  const n = dots.length;
  if (n === 0) return null;
  const { ml, svgWidth, plotWidth, slot, needsScroll, labelStep } = chartLayout(n);
  const height = 220;
  const mt = 16;
  const mb = 36;
  const plotH = height - mt - mb;
  const prices = dots.map((d) => d.netBuyPrice);
  const yMin = Math.min(...prices, currentPrice) * 0.92;
  const yMax = Math.max(...prices, currentPrice) * 1.05;
  const yScale = (v: number) => mt + plotH - ((v - yMin) / (yMax - yMin)) * plotH;
  const currentScaled = scaleMoney(currentPrice, currency);
  const prefix = currency === "USD" ? "$" : "₹";
  const plotBottom = height - mb;

  return (
    <Stack gap={6}>
      <div style={{ overflowX: needsScroll ? "auto" : "visible", width: "100%" }}>
        <svg width={svgWidth} height={height} style={{ display: "block", minWidth: needsScroll ? svgWidth : undefined }}>
          <line x1={ml} y1={mt} x2={ml} y2={plotBottom} stroke={theme.stroke.primary} strokeWidth={1} />
          <line x1={ml} y1={plotBottom} x2={ml + plotWidth} y2={plotBottom} stroke={theme.stroke.primary} strokeWidth={1} />
          <line
            x1={ml}
            y1={yScale(currentPrice)}
            x2={ml + plotWidth}
            y2={yScale(currentPrice)}
            stroke={theme.accent.primary}
            strokeDasharray="6 4"
            strokeWidth={1.5}
          />
          <text
            x={ml + plotWidth - 4}
            y={yScale(currentPrice) - 6}
            textAnchor="end"
            fill={theme.accent.primary}
            fontSize={10}
            fontWeight={600}
          >
            Current {prefix}
            {currentScaled.toFixed(currency === "USD" ? 2 : 0)}
          </text>
          {[yMin, currentPrice, yMax].map((tick, idx) => (
            <text key={idx} x={ml - 6} y={yScale(tick) + 4} textAnchor="end" fill={theme.text.tertiary} fontSize={10}>
              {prefix}
              {scaleMoney(tick, currency).toFixed(currency === "USD" ? 0 : 0)}
            </text>
          ))}
          {dots.map((dot, i) => {
            const cx = ml + slot * i + slot / 2;
            const cy = yScale(dot.netBuyPrice);
            const profitable = currentPrice > dot.netBuyPrice;
            const color = profitable ? theme.palette.diffStripAdded : theme.palette.diffStripRemoved;
            const r = n > 24 ? 4 : n > 12 ? 5 : 6;
            const showLabel = i % labelStep === 0 || i === n - 1;
            return (
              <g key={dot.label}>
                <circle cx={cx} cy={cy} r={r} fill={color}>
                  <title>
                    {dot.label}
                    {"\n"}Held: {dot.heldQty} shares
                    {"\n"}Net buy: {prefix}
                    {scaleMoney(dot.netBuyPrice, currency).toFixed(2)}
                    {"\n"}Current: {prefix}
                    {currentScaled.toFixed(2)}
                    {"\n"}Unrealized: {fmtSignedMoney(dot.unrealizedPnl, currency)} (
                    {dot.unrealizedPct >= 0 ? "+" : ""}
                    {dot.unrealizedPct.toFixed(1)}%)
                  </title>
                </circle>
                {showLabel && (
                  <text x={cx} y={height - 8} textAnchor="middle" fill={theme.text.secondary} fontSize={10}>
                    {dot.label}
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>
      {needsScroll && (
        <Text size="small" tone="tertiary">
          Scroll chart → · {n} open lots
        </Text>
      )}
    </Stack>
  );
}

function SummarySection({ data, currency }: { data: EsppData; currency: Currency }) {
  const theme = useHostTheme();
  return (
    <Stack gap={14}>
      <Grid columns={3} gap={10}>
        <Stat label="Gross purchased" value={data.grossPurchased.toLocaleString()} />
        <Stat label="Net received" value={data.netReceived.toLocaleString()} tone="info" />
        <Stat label="Currently held" value={data.currentlyHeld.toLocaleString()} />
      </Grid>
      <Grid columns={3} gap={10}>
        <Stat
          label="Purchase value"
          value={fmtMoney(data.purchaseValue, currency)}
          tone="info"
        />
        <Stat
          label="Net discount value"
          value={fmtMoney(data.netDiscountValue, currency)}
          tone="success"
        />
        <Stat
          label="Realized proceeds"
          value={fmtMoney(data.realizedProceeds, currency)}
          tone="info"
        />
      </Grid>
      <Grid columns={3} gap={10}>
        <Stat
          label="Realized P&L"
          value={fmtMoney(data.realizedPnl, currency)}
          tone={data.realizedPnl >= 0 ? "success" : "danger"}
        />
        <Stat
          label="Unrealized P&L"
          value={fmtMoney(data.unrealizedPnl, currency)}
          tone={data.unrealizedPnl >= 0 ? "success" : "danger"}
        />
        <Stat
          label="Total P&L"
          value={fmtMoney(data.totalPnl, currency)}
          tone={data.totalPnl >= 0 ? "success" : "danger"}
        />
      </Grid>
      <Row
        align="center"
        gap={10}
        style={{
          padding: "14px 18px",
          background: theme.fill.tertiary,
          borderRadius: 10,
          border: `1px solid ${theme.stroke.tertiary}`,
        }}
      >
        <Text weight="semibold">
          Portfolio return: <ReturnPct value={data.totalReturnPct} />
        </Text>
        <Text tone="tertiary">·</Text>
        <Text weight="semibold">Approx. XIRR {data.xirr}</Text>
        <Text size="small" tone="tertiary">
          (purchase date outflow — payroll spread not modeled)
        </Text>
      </Row>
      <Text size="small" tone="tertiary">
        Net received ℹ️: {data.taxWithheld} shares withheld for tax (gross − net). P&L uses net buy
        price per received share.
      </Text>
    </Stack>
  );
}

function PurchaseLotsTable({
  lots,
  currency,
  expanded,
  onToggle,
}: {
  lots: EsppLot[];
  currency: Currency;
  expanded: boolean;
  onToggle: () => void;
}) {
  const showScroll = !expanded && lots.length > 5;
  const visible = expanded ? lots : lots.slice(0, 5);

  return (
    <Stack gap={8}>
      <H2>Purchase Lots ({lots.length})</H2>
      <Card>
        <CardBody style={{ padding: 0 }}>
          <div
            style={{
              maxHeight: showScroll ? 220 : undefined,
              overflowY: showScroll ? "auto" : "visible",
            }}
          >
            <Table
              headers={[
                "Purchase date",
                "Gross",
                "Net",
                "Buy price ℹ️",
                "FMV",
                "Disc %",
                "Sold",
                "Held",
                "Real. P&L",
                "Unreal. P&L",
              ]}
              rows={visible.map((lot) => [
                lot.purchaseDate,
                lot.gross,
                lot.net,
                lot.buyPrice,
                lot.fmv,
                lot.discPct,
                lot.sold,
                lot.held,
                lot.realPnl === "—" ? "—" : <ReturnPct value={fmtSignedMoney(parseFloat(lot.realPnl.replace(/[^0-9.-]/g, "")), currency)} />,
                lot.unrealPnl === "—" ? "—" : <ReturnPct value={fmtSignedMoney(parseFloat(lot.unrealPnl.replace(/[^0-9.-]/g, "")), currency)} />,
              ])}
            />
          </div>
        </CardBody>
      </Card>
      {lots.length > 5 && (
        <Row align="center" gap={12}>
          <Text size="small" tone="tertiary">
            {expanded
              ? `Showing all ${lots.length} lots`
              : `Showing 5 of ${lots.length} lots — scroll or expand`}
          </Text>
          <Button variant="ghost" onClick={onToggle}>
            {expanded ? "Collapse table" : `Show all ${lots.length} lots`}
          </Button>
        </Row>
      )}
      <Text size="small" tone="tertiary">
        Buy price ℹ️: discounted price per share (typically ~15% below lock-in). Payroll deducted at
        buy price; P&L math uses effective net buy price (payroll ÷ net shares).
      </Text>
    </Stack>
  );
}

function SopCards({
  data,
  currency,
  currentPrice,
  theme,
}: {
  data: EsppData;
  currency: Currency;
  currentPrice: string;
  theme: CanvasHostTheme;
}) {
  return (
    <Stack gap={12}>
      <H2>Sell-on-Purchase Analysis</H2>
      <Text size="small" tone="tertiary">
        Hypothetical: exit every lot at purchase-day FMV on the next trading day.
      </Text>
      <Grid columns={3} gap={12}>
        {[
          {
            title: "Day-1 gain",
            sub: "Discount at purchase FMV",
            value: fmtMoney(data.day1Gain, currency),
            tone: "success" as const,
          },
          {
            title: "Extra from holding",
            sub: "On top of day-1 gain",
            value: fmtSignedMoney(data.opportunityExtra, currency),
            tone: data.opportunityExtra >= 0 ? ("success" as const) : ("danger" as const),
          },
          {
            title: "Total P&L",
            sub: "Realized + unrealized (actual)",
            value: fmtMoney(data.totalPnl, currency),
            tone: data.totalPnl >= 0 ? ("success" as const) : ("danger" as const),
          },
        ].map((card) => (
          <div
            key={card.title}
            style={{
              background: theme.fill.tertiary,
              borderRadius: 12,
              padding: "16px 14px",
              textAlign: "center",
              border: `1px solid ${theme.stroke.tertiary}`,
            }}
          >
            <Text size="small" tone="secondary">
              {card.title}
            </Text>
            <Text weight="semibold" style={{ fontSize: 20, marginTop: 6 }}>
              <ReturnPct value={card.value} />
            </Text>
            <Text size="small" tone="tertiary" style={{ marginTop: 4 }}>
              {card.sub}
            </Text>
          </div>
        ))}
      </Grid>
      <Callout
        tone={data.holdingBetter ? "success" : "warning"}
        title={
          data.holdingBetter
            ? `Holding was worth it — you are ${fmtMoney(data.opportunityExtra, currency)} ahead versus selling at purchase-day FMV on the next trading day (on top of ${fmtMoney(data.day1Gain, currency)} day-1 discount).`
            : `Day-1 exit would have been better — selling at purchase-day FMV would have left you ${fmtMoney(Math.abs(data.opportunityExtra), currency)} more than your actual outcome (day-1 discount was ${fmtMoney(data.day1Gain, currency)}).`
        }
      />
      <Callout tone="info" title="Not a comparison to today's stock price">
        This section compares your actual realized + unrealized P&L to a purchase-day hypothetical
        exit. It does not tell you whether to sell current holdings at {currentPrice}. For that,
        use the performance summary, return strip, and unsold lots chart above.
      </Callout>
    </Stack>
  );
}

function EsppPage({
  data,
  currency,
  currentPrice,
  qualOpen,
  setQualOpen,
}: {
  data: EsppData;
  currency: Currency;
  currentPrice: string;
  qualOpen: boolean;
  setQualOpen: (v: boolean) => void;
}) {
  const theme = useHostTheme();
  const [lotsExpanded, setLotsExpanded] = useCanvasState("lotsExpanded", false);

  return (
    <Stack gap={28}>
      <SummarySection data={data} currency={currency} />

      <PurchaseLotsTable
        lots={data.lots}
        currency={currency}
        expanded={lotsExpanded}
        onToggle={() => setLotsExpanded(!lotsExpanded)}
      />

      {data.soldBars.length > 0 && (
        <Stack gap={8}>
          <H2>Sold share returns (section name TBD)</H2>
          <Text size="small" tone="tertiary">
            Return on net buy price for shares sold from each purchase (partial or full). Bar height
            = return % — hover for proceeds, qty, and dollar P&L.
          </Text>
          <SoldReturnsChart bars={data.soldBars} currency={currency} />
        </Stack>
      )}

      {data.unsoldDots.length > 0 && (
        <Stack gap={8}>
          <H2>Open lots — cost vs current (section name TBD)</H2>
          <Text size="small" tone="tertiary">
            Each dot = net buy price for an open lot. Dashed line = current market. Green = above
            cost; red = underwater. No connecting line between dots.
          </Text>
          <UnsoldScatterChart
            dots={data.unsoldDots}
            currentPrice={data.currentPrice}
            currency={currency}
          />
        </Stack>
      )}

      <SopCards data={data} currency={currency} currentPrice={currentPrice} theme={theme} />

      <Stack gap={8}>
        <button
          type="button"
          onClick={() => setQualOpen(!qualOpen)}
          style={{
            background: "transparent",
            border: "none",
            color: theme.text.secondary,
            cursor: "pointer",
            fontSize: 13,
            padding: 0,
            textAlign: "left",
          }}
        >
          {qualOpen ? "▾" : "▸"} US tax classification (qualifying vs disqualifying disposition)
          <Text as="span" size="small" tone="tertiary">
            {" "}
            · US tax only
          </Text>
        </button>
        {qualOpen && (
          <Card variant="borderless">
            <CardBody>
              <Grid columns={2} gap={16}>
                <Stat
                  label="Qualifying sales"
                  value={`${data.qualifyingCount} · ${fmtMoney(data.qualifyingProceeds, currency)} proceeds`}
                />
                <Stat
                  label="Disqualifying sales"
                  value={`${data.disqualifyingCount} · ${fmtMoney(data.disqualifyingProceeds, currency)} proceeds`}
                />
              </Grid>
            </CardBody>
          </Card>
        )}
      </Stack>

      <Text size="small" tone="tertiary">
        Returns and P&L on this page use effective cost per received share (total payroll ÷ net
        shares per purchase). Additional tax paid in cash outside the plan is not reflected in these
        calculations.
      </Text>
    </Stack>
  );
}

function PrototypeBar({
  scenario,
  setScenario,
  density,
  setDensity,
}: {
  scenario: Scenario;
  setScenario: (s: Scenario) => void;
  density: Density;
  setDensity: (d: Density) => void;
}) {
  const theme = useHostTheme();
  return (
    <Row
      gap={16}
      align="center"
      style={{
        padding: "10px 14px",
        background: theme.fill.tertiary,
        borderRadius: 6,
        border: `1px solid ${theme.stroke.tertiary}`,
        flexWrap: "wrap",
      }}
    >
      <Text size="small" weight="semibold">
        M24 ESPP History — full page mock (§A–F)
      </Text>
      <Row gap={8} align="center">
        <Text size="small">Empty</Text>
        <Toggle checked={scenario === "loaded"} onChange={(on) => setScenario(on ? "loaded" : "empty")} />
        <Text size="small">Loaded</Text>
      </Row>
      {scenario === "loaded" && (
        <Row gap={8} align="center">
          <Pill active={density === "normal"} onClick={() => setDensity("normal")} size="sm">
            8 lots
          </Pill>
          <Pill active={density === "dense"} onClick={() => setDensity("dense")} size="sm">
            16 lots (§E scroll)
          </Pill>
        </Row>
      )}
      <Spacer />
      <Text size="small" tone="tertiary">
        Reopen canvas if you see the old 9-tile grid
      </Text>
    </Row>
  );
}

export default function M24BhHistoryMockup() {
  const [scenario, setScenario] = useCanvasState<Scenario>("scenario", "loaded");
  const [symbol, setSymbol] = useCanvasState("symbol", "ADBE");
  const [currency, setCurrency] = useCanvasState<Currency>("currency", "INR");
  const [plan, setPlan] = useCanvasState<Plan>("plan", "ESPP");
  const [density, setDensity] = useCanvasState<Density>("density", "normal");
  const [qualOpen, setQualOpen] = useCanvasState("qualOpen", false);

  const sym = getSymbolData(symbol, density);
  const theme = useHostTheme();

  return (
    <Stack gap={16}>
      <PrototypeBar
        scenario={scenario}
        setScenario={setScenario}
        density={density}
        setDensity={setDensity}
      />

      {scenario === "empty" ? (
        <Stack gap={12}>
          <H1>Benefits History</H1>
          <Callout tone="warning" title="No Benefit History uploaded">
            Upload your E*Trade Benefit History XLSX to see ESPP and RSU analyses.
          </Callout>
        </Stack>
      ) : (
        <Stack gap={16}>
          <Row align="center">
            <H1>Benefits History</H1>
            <Spacer />
            <Row gap={6}>
              <Pill active={currency === "INR"} onClick={() => setCurrency("INR")} size="sm">
                ₹ INR
              </Pill>
              <Pill active={currency === "USD"} onClick={() => setCurrency("USD")} size="sm">
                $ USD
              </Pill>
            </Row>
          </Row>

          <Row
            align="center"
            gap={16}
            style={{
              padding: "10px 14px",
              background: theme.bg.elevated,
              border: `1px solid ${theme.stroke.tertiary}`,
              borderRadius: 6,
            }}
          >
            <Select
              value={symbol}
              onChange={setSymbol}
              options={[
                { value: "ADBE", label: "ADBE" },
                { value: "CRM", label: "CRM" },
              ]}
              style={{ width: 100 }}
            />
            <Text weight="semibold" style={{ fontFamily: "monospace" }}>
              {sym.price}
            </Text>
            <Text size="small" tone="tertiary">
              as of 10 Jun 2026
            </Text>
            <Spacer />
            <Text size="small" tone="secondary">
              Updated 08 Jun 2026
            </Text>
            <Button variant="secondary">Upload</Button>
          </Row>

          <Row gap={0} style={{ borderBottom: `1px solid ${theme.stroke.tertiary}` }}>
            {(["RSU", "ESPP"] as const).map((tab) => (
              <button
                key={tab}
                type="button"
                onClick={() => setPlan(tab)}
                style={{
                  background: "transparent",
                  border: "none",
                  borderBottom:
                    plan === tab
                      ? `2px solid ${theme.accent.primary}`
                      : "2px solid transparent",
                  color: plan === tab ? theme.text.primary : theme.text.secondary,
                  cursor: "pointer",
                  fontSize: 13,
                  fontWeight: plan === tab ? 600 : 400,
                  padding: "10px 18px",
                  marginBottom: -1,
                }}
              >
                {tab}
              </button>
            ))}
          </Row>

          {plan === "RSU" ? (
            <Callout tone="info" title="RSU tab">
              See m24-rsu-history.canvas.tsx for the §G income-lens mock.
            </Callout>
          ) : (
            <EsppPage
              data={sym.espp}
              currency={currency}
              currentPrice={sym.price}
              qualOpen={qualOpen}
              setQualOpen={setQualOpen}
            />
          )}
        </Stack>
      )}
    </Stack>
  );
}
