/**
 * M24 RSU History — visual mock (§G income lens).
 *
 * Git copy: docs/specs/M24-bh-history/m24-rsu-history.canvas.tsx
 * ESPP mock: canvases/m24-bh-history.canvas.tsx
 */
import {
  Button,
  Callout,
  Card,
  CardBody,
  Grid,
  H1,
  H2,
  LineChart,
  Pill,
  Row,
  Select,
  Spacer,
  Stack,
  Table,
  Text,
  useCanvasState,
  useHostTheme,
  type StatTone,
} from "cursor/canvas";

type Currency = "INR" | "USD";
type Plan = "RSU" | "ESPP";
type Scenario = "empty" | "loaded";

type RsuGrant = {
  grantNumber: string;
  grantDate: string;
  grantedQty: number;
  grantPromise: number;
  vestedQty: number;
  recognized: number;
  unvestedQty: number;
  stillToVest: number;
  vsPromisePct: number;
};

type RsuData = {
  currentPrice: number;
  grants: RsuGrant[];
  grantPromise: number;
  incomeRecognized: number;
  stillToVest: number;
  vestedPromiseAtGrant: number;
  vestVsGrantDriftPct: number;
  unvestedGrossShares: number;
  vestedNetShares: number;
  grantsByYear: { year: string; value: number }[];
  incomeByYear: { year: string; value: number }[];
};

const FX = 83;

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

function fmtPct(value: number): string {
  const sign = value >= 0 ? "+" : "";
  return `${sign}${value.toFixed(1)}%`;
}

function scaleForChart(amount: number, currency: Currency): number {
  const scaled = currency === "INR" ? amount * FX : amount;
  return Math.round(scaled / 1000);
}

/** Vest-date income on vested shares vs grant-date FMV for those same shares. */
function computeVestDrift(grants: RsuGrant[]) {
  let vestedPromiseAtGrant = 0;
  let incomeRecognized = 0;

  for (const g of grants) {
    if (g.grantedQty > 0 && g.vestedQty > 0) {
      vestedPromiseAtGrant += (g.grantPromise * g.vestedQty) / g.grantedQty;
      incomeRecognized += g.recognized;
    }
  }

  const vestVsGrantDriftPct =
    vestedPromiseAtGrant > 0 ? (incomeRecognized / vestedPromiseAtGrant - 1) * 100 : 0;

  return { vestedPromiseAtGrant, vestVsGrantDriftPct };
}

function grantYear(grantDate: string): string {
  const parts = grantDate.split("-");
  return parts[parts.length - 1] ?? grantDate;
}

function grantsByYearFromGrants(grants: RsuGrant[]) {
  return grants
    .reduce<{ year: string; value: number }[]>((acc, g) => {
      const year = grantYear(g.grantDate);
      const row = acc.find((r) => r.year === year);
      if (row) row.value += g.grantPromise;
      else acc.push({ year, value: g.grantPromise });
      return acc;
    }, [])
    .sort((a, b) => a.year.localeCompare(b.year));
}

function buildAdbeRsu(currentPrice: number): RsuData {
  const grants: RsuGrant[] = [
    {
      grantNumber: "RU401020",
      grantDate: "15-Feb-2020",
      grantedQty: 1200,
      grantPromise: 372_000,
      vestedQty: 1200,
      recognized: 415_200,
      unvestedQty: 0,
      stillToVest: 0,
      vsPromisePct: 11.6,
    },
    {
      grantNumber: "RU412880",
      grantDate: "15-Feb-2021",
      grantedQty: 1000,
      grantPromise: 480_000,
      vestedQty: 1000,
      recognized: 518_500,
      unvestedQty: 0,
      stillToVest: 0,
      vsPromisePct: 8.0,
    },
    {
      grantNumber: "RU422478",
      grantDate: "15-Feb-2022",
      grantedQty: 850,
      grantPromise: 327_250,
      vestedQty: 680,
      recognized: 289_680,
      unvestedQty: 170,
      stillToVest: 170 * currentPrice,
      vsPromisePct: ((289_680 + 170 * currentPrice) / 327_250 - 1) * 100,
    },
    {
      grantNumber: "RU431102",
      grantDate: "15-Feb-2023",
      grantedQty: 700,
      grantPromise: 367_500,
      vestedQty: 280,
      recognized: 174_160,
      unvestedQty: 420,
      stillToVest: 420 * currentPrice,
      vsPromisePct: ((174_160 + 420 * currentPrice) / 367_500 - 1) * 100,
    },
    {
      grantNumber: "RU441005",
      grantDate: "15-Feb-2024",
      grantedQty: 600,
      grantPromise: 354_000,
      vestedQty: 0,
      recognized: 0,
      unvestedQty: 600,
      stillToVest: 600 * currentPrice,
      vsPromisePct: ((600 * currentPrice) / 354_000 - 1) * 100,
    },
    {
      grantNumber: "RU451118",
      grantDate: "15-Feb-2025",
      grantedQty: 500,
      grantPromise: 310_000,
      vestedQty: 0,
      recognized: 0,
      unvestedQty: 500,
      stillToVest: 500 * currentPrice,
      vsPromisePct: ((500 * currentPrice) / 310_000 - 1) * 100,
    },
  ];

  const grantPromise = grants.reduce((s, g) => s + g.grantPromise, 0);
  const incomeRecognized = grants.reduce((s, g) => s + g.recognized, 0);
  const stillToVest = grants.reduce((s, g) => s + g.stillToVest, 0);
  const unvestedGrossShares = grants.reduce((s, g) => s + g.unvestedQty, 0);
  const { vestedPromiseAtGrant, vestVsGrantDriftPct } = computeVestDrift(grants);
  const vestedNetShares = 2160;

  return {
    currentPrice,
    grants,
    grantPromise,
    incomeRecognized,
    stillToVest,
    vestedPromiseAtGrant,
    vestVsGrantDriftPct,
    unvestedGrossShares,
    vestedNetShares,
    grantsByYear: grantsByYearFromGrants(grants),
    incomeByYear: [
      { year: "2020", value: 98_400 },
      { year: "2021", value: 212_600 },
      { year: "2022", value: 318_200 },
      { year: "2023", value: 286_400 },
      { year: "2024", value: 174_160 },
    ],
  };
}

function buildCrmRsu(currentPrice: number): RsuData {
  const grants: RsuGrant[] = [
    {
      grantNumber: "RU501110",
      grantDate: "01-Mar-2021",
      grantedQty: 800,
      grantPromise: 192_000,
      vestedQty: 800,
      recognized: 218_400,
      unvestedQty: 0,
      stillToVest: 0,
      vsPromisePct: 13.8,
    },
    {
      grantNumber: "RU512220",
      grantDate: "01-Mar-2022",
      grantedQty: 650,
      grantPromise: 175_500,
      vestedQty: 520,
      recognized: 156_000,
      unvestedQty: 130,
      stillToVest: 130 * currentPrice,
      vsPromisePct: ((156_000 + 130 * currentPrice) / 175_500 - 1) * 100,
    },
    {
      grantNumber: "RU523330",
      grantDate: "01-Mar-2023",
      grantedQty: 550,
      grantPromise: 165_000,
      vestedQty: 220,
      recognized: 77_000,
      unvestedQty: 330,
      stillToVest: 330 * currentPrice,
      vsPromisePct: ((77_000 + 330 * currentPrice) / 165_000 - 1) * 100,
    },
  ];

  const grantPromise = grants.reduce((s, g) => s + g.grantPromise, 0);
  const incomeRecognized = grants.reduce((s, g) => s + g.recognized, 0);
  const stillToVest = grants.reduce((s, g) => s + g.stillToVest, 0);
  const unvestedGrossShares = grants.reduce((s, g) => s + g.unvestedQty, 0);
  const { vestedPromiseAtGrant, vestVsGrantDriftPct } = computeVestDrift(grants);

  return {
    currentPrice,
    grants,
    grantPromise,
    incomeRecognized,
    stillToVest,
    vestedPromiseAtGrant,
    vestVsGrantDriftPct,
    unvestedGrossShares,
    vestedNetShares: 1540,
    grantsByYear: grantsByYearFromGrants(grants),
    incomeByYear: [
      { year: "2021", value: 54_600 },
      { year: "2022", value: 163_800 },
      { year: "2023", value: 156_000 },
      { year: "2024", value: 77_000 },
    ],
  };
}

function getSymbolData(symbol: string): { price: number; priceLabel: string; rsu: RsuData } {
  if (symbol === "CRM") {
    const price = 268.4;
    return { price, priceLabel: `$${price.toFixed(2)}`, rsu: buildCrmRsu(price) };
  }
  const price = 420.15;
  return { price, priceLabel: `$${price.toFixed(2)}`, rsu: buildAdbeRsu(price) };
}

function VsPromise({ value }: { value: number }) {
  const theme = useHostTheme();
  return (
    <span
      style={{
        color: value >= 0 ? theme.palette.diffStripAdded : theme.palette.diffStripRemoved,
        fontWeight: 600,
      }}
    >
      {fmtPct(value)}
    </span>
  );
}

function InfoIcon({ hint }: { hint: string }) {
  const theme = useHostTheme();
  return (
    <span
      title={hint}
      aria-label={hint}
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        width: 14,
        height: 14,
        borderRadius: "50%",
        border: `1px solid ${theme.stroke.secondary}`,
        color: theme.text.tertiary,
        fontSize: 10,
        fontWeight: 600,
        lineHeight: 1,
        cursor: "help",
        flexShrink: 0,
      }}
    >
      i
    </span>
  );
}

function HintStat({
  label,
  hint,
  value,
  tone,
}: {
  label: string;
  hint: string;
  value: string;
  tone?: StatTone;
}) {
  const theme = useHostTheme();
  const valueColor =
    tone === "success"
      ? theme.palette.diffStripAdded
      : tone === "danger"
        ? theme.palette.diffStripRemoved
        : tone === "info"
          ? theme.accent.primary
          : tone === "warning"
            ? theme.text.link
            : theme.text.primary;

  return (
    <Stack gap={4}>
      <Text weight="semibold" style={{ fontSize: 20, lineHeight: "26px", color: valueColor }}>
        {value}
      </Text>
      <Row gap={4} align="center">
        <Text size="small" tone="tertiary">
          {label}
        </Text>
        <InfoIcon hint={hint} />
      </Row>
    </Stack>
  );
}

function RsuSummary({ data, currency }: { data: RsuData; currency: Currency }) {
  const priceLabel = `$${data.currentPrice.toFixed(2)}`;

  return (
    <Stack gap={10}>
      <Grid columns={4} gap={10}>
        <HintStat
          label="Grants"
          hint="Number of RSU grant records for this symbol in your Benefit History."
          value={String(data.grants.length)}
        />
        <HintStat
          label="Grant promise"
          hint="Total compensation value when granted — sum of granted qty × grant-date FMV across all grants."
          value={fmtMoney(data.grantPromise, currency)}
        />
        <HintStat
          label="Income recognized"
          hint="RSU compensation already earned at vest — sum of vest qty × vest-date FMV on all vested tranches. This is ordinary income at vest."
          value={fmtMoney(data.incomeRecognized, currency)}
          tone="success"
        />
        <HintStat
          label="Still to vest (est.)"
          hint={`Unvested gross shares × today's price (${priceLabel}). An estimate of future vest income if remaining shares vested at the current price — not income you have received.`}
          value={fmtMoney(data.stillToVest, currency)}
          tone="info"
        />
      </Grid>
      <Grid columns={3} gap={10}>
        <HintStat
          label="Vested (net shares)"
          hint="Sellable shares delivered after tax withholding on vested RSU tranches."
          value={data.vestedNetShares.toLocaleString()}
        />
        <HintStat
          label="Unvested (gross shares)"
          hint="Shares still on the vesting schedule — not yet delivered or taxed."
          value={data.unvestedGrossShares.toLocaleString()}
        />
        <HintStat
          label="Vest vs grant drift"
          hint="How much higher or lower vest-date income was vs grant-date FMV for shares that have already vested. Positive means the stock was worth more at vest than at grant."
          value={fmtPct(data.vestVsGrantDriftPct)}
          tone={data.vestVsGrantDriftPct >= 0 ? "success" : "danger"}
        />
      </Grid>
    </Stack>
  );
}

function grantTableRows(grants: RsuGrant[], currency: Currency) {
  return grants.map((g) => [
    g.grantNumber,
    g.grantDate,
    g.grantedQty.toLocaleString(),
    fmtMoney(g.grantPromise, currency),
    fmtMoney(g.recognized, currency),
    g.unvestedQty > 0 ? fmtMoney(g.stillToVest, currency) : "—",
    <VsPromise value={g.vsPromisePct} />,
  ]);
}

function GrantTable({ grants, currency }: { grants: RsuGrant[]; currency: Currency }) {
  const [expanded, setExpanded] = useCanvasState("grantsExpanded", false);
  const sorted = [...grants].sort((a, b) => b.grantDate.localeCompare(a.grantDate));
  const showScroll = !expanded && sorted.length > 5;
  const visible = expanded ? sorted : sorted.slice(0, 5);

  return (
    <Stack gap={8}>
      <H2>Grant breakdown ({grants.length})</H2>
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
                "Grant #",
                "Grant date",
                "Granted",
                "Grant promise",
                "Recognized",
                "Still to vest",
                "vs promise",
              ]}
              rows={grantTableRows(visible, currency)}
            />
          </div>
        </CardBody>
      </Card>
      {sorted.length > 5 && (
        <Row align="center" gap={12}>
          <Text size="small" tone="tertiary">
            {expanded
              ? `Showing all ${sorted.length} grants`
              : `Showing 5 of ${sorted.length} grants — scroll or expand`}
          </Text>
          <Button variant="ghost" onClick={() => setExpanded(!expanded)}>
            {expanded ? "Collapse table" : `Show all ${sorted.length} grants`}
          </Button>
        </Row>
      )}
      <Text size="small" tone="tertiary">
        Sorted by grant date (newest first). vs promise = (recognized + still-to-vest estimate) ÷
        grant promise − 1.
      </Text>
    </Stack>
  );
}

function VestIncomeByYearChart({ data, currency }: { data: RsuData; currency: Currency }) {
  const prefix = currency === "USD" ? "$" : "₹";

  return (
    <Stack gap={8}>
      <H2>RSU income by year</H2>
      <Text size="small" tone="secondary">
        Total compensation that vested each calendar year — all grants combined. Read it like annual
        salary growth: did your RSU income go up or down year to year?
      </Text>
      <LineChart
        height={220}
        categories={data.incomeByYear.map((r) => r.year)}
        series={[
          {
            name: "Vest income (vest FMV)",
            data: data.incomeByYear.map((r) => scaleForChart(r.value, currency)),
            tone: "success",
          },
        ]}
        fill
        valuePrefix={prefix}
        valueSuffix="k"
        showValues
      />
      <Text size="small" tone="tertiary">
        Y-axis: total vest-date income in {currency} (thousands) · Source: Σ(vest qty × vest FMV) per
        calendar year
      </Text>
    </Stack>
  );
}

function GrantValueByYearChart({ data, currency }: { data: RsuData; currency: Currency }) {
  const prefix = currency === "USD" ? "$" : "₹";

  return (
    <Stack gap={8}>
      <H2>New grant value by year</H2>
      <Text size="small" tone="secondary">
        Value of new RSU grants issued each year at grant-date FMV. Shows when fresh equity comp was
        awarded — separate from when it actually vests.
      </Text>
      <LineChart
        height={220}
        categories={data.grantsByYear.map((r) => r.year)}
        series={[
          {
            name: "New grant promise (grant FMV)",
            data: data.grantsByYear.map((r) => scaleForChart(r.value, currency)),
            tone: "info",
          },
        ]}
        fill
        valuePrefix={prefix}
        valueSuffix="k"
        showValues
      />
      <Text size="small" tone="tertiary">
        Y-axis: new grant value in {currency} (thousands) · Source: Σ(granted qty × grant FMV) for
        grants issued that year
      </Text>
      <Callout tone="info" title="Grant FMV vs vest income">
        A large grant in one year appears here immediately but only flows into RSU income by year
        as tranches vest in later years.
      </Callout>
    </Stack>
  );
}

function RsuPage({ data, currency }: { data: RsuData; currency: Currency }) {
  return (
    <Stack gap={24}>
      <RsuSummary data={data} currency={currency} />
      <VestIncomeByYearChart data={data} currency={currency} />
      <GrantTable grants={data.grants} currency={currency} />
      <GrantValueByYearChart data={data} currency={currency} />

      <Callout tone="warning" title="Disclaimer">
        Still-to-vest estimates use today&apos;s stock price — not income you have received.
        Income recognized uses vest-date FMV from your Benefit History upload.
      </Callout>
    </Stack>
  );
}

function PrototypeBar({
  scenario,
  setScenario,
}: {
  scenario: Scenario;
  setScenario: (s: Scenario) => void;
}) {
  const theme = useHostTheme();
  return (
    <Row
      align="center"
      gap={8}
      style={{
        padding: "8px 12px",
        background: theme.fill.quaternary,
        borderRadius: 6,
        border: `1px solid ${theme.stroke.tertiary}`,
      }}
    >
      <Text size="small" weight="semibold" tone="secondary">
        Prototype
      </Text>
      <Pill active={scenario === "loaded"} onClick={() => setScenario("loaded")} size="sm">
        Loaded
      </Pill>
      <Pill active={scenario === "empty"} onClick={() => setScenario("empty")} size="sm">
        Empty
      </Pill>
      <Spacer />
      <Text size="small" tone="tertiary">
        §G RSU income lens · Jun 2026
      </Text>
    </Row>
  );
}

export default function M24RsuHistoryMockup() {
  const [scenario, setScenario] = useCanvasState<Scenario>("scenario", "loaded");
  const [symbol, setSymbol] = useCanvasState("symbol", "ADBE");
  const [currency, setCurrency] = useCanvasState<Currency>("currency", "INR");
  const [plan, setPlan] = useCanvasState<Plan>("plan", "RSU");

  const sym = getSymbolData(symbol);
  const theme = useHostTheme();

  return (
    <Stack gap={16}>
      <PrototypeBar scenario={scenario} setScenario={setScenario} />

      {scenario === "empty" ? (
        <Stack gap={12}>
          <H1>Benefits History</H1>
          <Callout tone="warning" title="No Benefit History uploaded">
            Upload your E*Trade Benefit History XLSX to see RSU and ESPP analyses.
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
              {sym.priceLabel}
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
            <RsuPage data={sym.rsu} currency={currency} />
          ) : (
            <Callout tone="info" title="ESPP tab">
              See m24-bh-history.canvas.tsx for the locked ESPP mock (§A–F).
            </Callout>
          )}
        </Stack>
      )}
    </Stack>
  );
}
