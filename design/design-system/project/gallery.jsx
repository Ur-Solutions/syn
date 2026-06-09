/* ============================================================
   SYN — COMPONENT GALLERY
   Every component, every state. Also defines composite cells
   (CaptureModeCard, MenuRow, ProviderCard, PermissionCard,
   AnnotationSelection, CompletionMoment, EmptyState) reused by screens.
   ============================================================ */
(function () {
  const {
    Icon, Disc, Button, IconButton, ToolButton, KeyCap, KeyChord, SHIFT_L, SHIFT_R,
    StatusDot, StatusBadge, Card, ListCell, MicMeter, Switch, ProgressSteps,
    SecureKeyField, Select, VDivider, Section, Stage, Mono, Caption,
  } = window;

  /* ---------- composite cells (exported for screens) ---------- */
  function CaptureModeCard({ icon, title, sub, state = "default", w }) {
    const selected = state === "selected", last = state === "last", hover = state === "hover";
    return (
      <div style={{
        display: "flex", gap: 12, padding: 14, borderRadius: 12, width: w, cursor: "pointer",
        background: hover ? "var(--selected)" : "var(--card)",
        border: "1px solid", borderColor: selected ? "var(--accent-ring)" : "var(--hairline)",
        boxShadow: selected ? "0 0 0 3px var(--accent-tint-2)" : "var(--shadow-1)",
        transition: "border-color .15s, box-shadow .15s, background .15s", alignItems: "flex-start",
      }}>
        <span style={{
          width: 34, height: 34, borderRadius: 9, flex: "none", display: "flex", alignItems: "center",
          justifyContent: "center", background: "var(--surface2)", border: "1px solid var(--hairline)",
          color: "var(--text1)",
        }}><Icon name={icon} size={18} sw={1.6} /></span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
            <span style={{ fontSize: 13.5, fontWeight: 600, color: "var(--text1)", letterSpacing: "-0.01em" }}>{title}</span>
            {last && <span style={{
              fontSize: 9.5, fontWeight: 700, letterSpacing: "0.04em", textTransform: "uppercase",
              color: "var(--accent-deep)", background: "var(--accent-tint)", border: "1px solid var(--accent-ring)",
              borderRadius: 999, padding: "1px 6px",
            }}>Last</span>}
          </div>
          <div style={{ fontSize: 11.5, color: "var(--text2)", marginTop: 3, lineHeight: 1.4 }}>{sub}</div>
        </div>
      </div>
    );
  }

  function MenuRow({ icon, label, hint, chord, chevron, danger, selected, tint, glyphColor, state }) {
    return (
      <div style={{
        display: "flex", alignItems: "center", gap: 11, padding: "7px 10px", borderRadius: 7,
        cursor: "pointer",
        background: selected ? (tint ? "var(--accent-tint)" : "var(--selected)") : state === "hover" ? "var(--selected)" : "transparent",
        color: danger ? "var(--destructive)" : "var(--text1)",
      }}>
        <span style={{ color: danger ? "var(--destructive)" : glyphColor || "var(--text2)", display: "inline-flex", flex: "none" }}>
          <Icon name={icon} size={16} sw={1.6} />
        </span>
        <span style={{ flex: 1, fontSize: 13, fontWeight: 500, letterSpacing: "-0.01em" }}>{label}</span>
        {chord && <KeyChord keys={chord} />}
        {hint && <span style={{ fontSize: 11.5, color: "var(--text3)" }}>{hint}</span>}
        {chevron && <span style={{ color: "var(--text3)" }}><Icon name="chevronRight" size={13} sw={1.7} /></span>}
      </div>
    );
  }

  function ProviderCard({ name, sub, model, hint, ok = true, icon = "sparkle" }) {
    return (
      <Card pad={16}>
        <div style={{ display: "flex", alignItems: "center", gap: 11, marginBottom: 14 }}>
          <span style={{
            width: 32, height: 32, borderRadius: 8, flex: "none", display: "flex", alignItems: "center",
            justifyContent: "center", background: "var(--surface2)", border: "1px solid var(--hairline)", color: "var(--text1)",
          }}><Icon name={icon} size={17} sw={1.6} /></span>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13.5, fontWeight: 600, color: "var(--text1)" }}>{name}</div>
            <div style={{ fontSize: 11.5, color: "var(--text2)", marginTop: 1 }}>{sub}</div>
          </div>
          <StatusBadge state={ok ? "success" : "warning"}>{ok ? "Available" : "No key"}</StatusBadge>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
          <div>
            <Label>Model</Label>
            <Select value={model} hint={hint} />
          </div>
          <div>
            <Label>API key</Label>
            <SecureKeyField ok={ok} />
          </div>
        </div>
      </Card>
    );
  }

  function PermissionCard({ icon, title, desc, granted }) {
    return (
      <Card pad={16}>
        <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
          <span style={{
            width: 34, height: 34, borderRadius: 9, flex: "none", display: "flex", alignItems: "center",
            justifyContent: "center", background: "var(--surface2)", border: "1px solid var(--hairline)", color: "var(--text1)",
          }}><Icon name={icon} size={18} sw={1.6} /></span>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13.5, fontWeight: 600, color: "var(--text1)" }}>{title}</div>
            <div style={{ fontSize: 11.5, color: "var(--text2)", marginTop: 3, lineHeight: 1.45 }}>{desc}</div>
          </div>
          {granted
            ? <StatusBadge state="success" glyph="check">Granted</StatusBadge>
            : <Button size="sm" variant="primary">Allow…</Button>}
        </div>
      </Card>
    );
  }

  function Label({ children }) {
    return <div style={{ fontSize: 10.5, fontWeight: 600, color: "var(--text3)", textTransform: "uppercase", letterSpacing: "0.07em", marginBottom: 6 }}>{children}</div>;
  }

  function AnnotationSelection({ w = 132, h = 80 }) {
    return (
      <div style={{ position: "relative", width: w, height: h }}>
        <div style={{
          position: "absolute", inset: 0, borderRadius: 8,
          border: "1.5px dashed var(--accent)", boxShadow: "0 0 0 1px var(--ink-halo)",
        }} />
        {[[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y], i) => (
          <span key={i} style={{
            position: "absolute", width: 7, height: 7, borderRadius: 2, background: "var(--card)",
            border: "1.5px solid var(--accent)",
            left: x ? "100%" : 0, top: y ? "100%" : 0, transform: "translate(-50%,-50%)",
          }} />
        ))}
      </div>
    );
  }

  function CompletionMoment({ replayable }) {
    const [k, setK] = React.useState(0);
    return (
      <div onClick={() => replayable && setK((v) => v + 1)} style={{ display: "inline-flex", alignItems: "center", gap: 12, cursor: replayable ? "pointer" : "default" }}>
        <span key={k} style={{ position: "relative", display: "inline-flex" }}>
          <span style={{ position: "absolute", inset: -7, borderRadius: "50%", border: "2px solid var(--accent-ring)", animation: "completion-ring 0.7s ease-out", opacity: 0 }} />
          <span style={{
            width: 30, height: 30, borderRadius: "50%", background: "var(--accent-tint)", border: "1px solid var(--accent-ring)",
            color: "var(--accent-deep)", display: "flex", alignItems: "center", justifyContent: "center",
            animation: "completion-pop 0.6s var(--spring)",
          }}><Icon name="check" size={16} sw={2.2} /></span>
        </span>
        <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text1)" }}>Packet ready</span>
      </div>
    );
  }

  function EmptyState({ compact }) {
    return (
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", padding: compact ? 18 : 34, gap: 14 }}>
        <span style={{
          width: 56, height: 56, borderRadius: 16, display: "flex", alignItems: "center", justifyContent: "center",
          background: "var(--card)", border: "1px solid var(--hairline)", boxShadow: "var(--shadow-1)", color: "var(--accent)",
        }}><Icon name="aperture" size={28} sw={1.4} /></span>
        <div>
          <div style={{ fontSize: 15, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.015em" }}>No packets yet</div>
          <div style={{ fontSize: 12.5, color: "var(--text2)", marginTop: 5, maxWidth: 280, lineHeight: 1.5 }}>
            Point at it, draw on it, talk through it. Your first Syn Packet lands here, ready to paste.
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 7, marginTop: 2 }}>
          <span style={{ fontSize: 11.5, color: "var(--text3)" }}>Start with</span>
          <KeyChord keys={[SHIFT_L, SHIFT_R, { k: "R" }]} />
        </div>
      </div>
    );
  }

  /* ---------- gallery scaffolding ---------- */
  const Block = ({ title, sub, children, cols }) => (
    <div style={{ marginBottom: 34 }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 16 }}>
        <h3 style={{ margin: 0, fontSize: 15, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.015em" }}>{title}</h3>
        {sub && <span style={{ fontSize: 12, color: "var(--text3)" }}>{sub}</span>}
      </div>
      {children}
    </div>
  );

  const Cell = ({ label, children, bg = "var(--card)", minH = 92, pad = 18 }) => (
    <div>
      <div style={{ fontSize: 10.5, fontWeight: 600, color: "var(--text3)", marginBottom: 9, fontFamily: "var(--font-mono)" }}>{label}</div>
      <div style={{
        background: bg === "canvas" ? "var(--canvas)" : bg, border: "1px solid var(--hairline)", borderRadius: 12,
        padding: pad, minHeight: minH, display: "flex", alignItems: "center", justifyContent: "center", gap: 12, flexWrap: "wrap",
      }}>{children}</div>
    </div>
  );

  const Grid = ({ cols = 4, children, gap = 14 }) => (
    <div style={{ display: "grid", gridTemplateColumns: `repeat(${cols}, 1fr)`, gap }}>{children}</div>
  );

  /* ---------- the gallery ---------- */
  function Gallery() {
    return (
      <Section id="buttons" eyebrow="Components" title="Buttons & controls"
        desc="One subtly rose-tinted primary per view; everything else neutral. Destructive is a neutral button with a red glyph — never a red fill.">

        <Block title="ButtonStyle" sub="primary · secondary · tertiary · destructive">
          <Grid cols={4}>
            <Cell label="rest"><Button variant="primary" icon="copy">Copy Packet</Button></Cell>
            <Cell label="hover"><Button variant="primary" icon="copy" state="hover">Copy Packet</Button></Cell>
            <Cell label="pressed"><Button variant="primary" icon="copy" state="press">Copy Packet</Button></Cell>
            <Cell label="disabled"><Button variant="primary" icon="copy" disabled>Copy Packet</Button></Cell>
            <Cell label="secondary"><Button variant="secondary" icon="folder">Open Folder</Button></Cell>
            <Cell label="hover"><Button variant="secondary" icon="folder" state="hover">Open Folder</Button></Cell>
            <Cell label="tertiary"><Button variant="tertiary">Reveal Zip</Button></Cell>
            <Cell label="destructive"><Button variant="destructive" icon="trash">Delete</Button></Cell>
          </Grid>
        </Block>

        <Block title="IconButton" sub="neutral; active = faint rose tint + rose icon">
          <Grid cols={4}>
            <Cell label="default"><IconButton icon="pause" label="Pause" /></Cell>
            <Cell label="hover"><IconButton icon="pause" state="hover" label="Pause" /></Cell>
            <Cell label="active"><IconButton icon="pen" active label="Canvas" /></Cell>
            <Cell label="disabled"><IconButton icon="trash" disabled label="Delete" /></Cell>
          </Grid>
        </Block>

        <Block title="ToolButton" sub="canvas tools — active = faint rose tint + rose icon">
          <Cell label="Pen · Line · Rectangle · Ellipse" minH={78}>
            <div style={{ display: "flex", gap: 4, padding: 4, background: "var(--surface2)", borderRadius: 10, border: "1px solid var(--hairline)" }}>
              <ToolButton icon="pen" active label="Pen" />
              <ToolButton icon="line" label="Line" />
              <ToolButton icon="rectangle" label="Rectangle" />
              <ToolButton icon="ellipse" label="Ellipse" />
            </div>
          </Cell>
        </Block>

        <Block title="KeyCapChip" sub="neutral caps; distinguishes Left ⇧ vs Right ⇧">
          <div style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, overflow: "hidden" }}>
            {[
              { l: "Open capture picker", c: [SHIFT_L, SHIFT_R, { k: "R" }] },
              { l: "Repeat last capture", c: [SHIFT_L, SHIFT_R] },
              { l: "Toggle Canvas Mode", c: [SHIFT_R, { k: "C" }] },
              { l: "Pen / Line / Rect / Ellipse", c: [SHIFT_R, { k: "1 / 2 / 3 / 4", wide: true }] },
              { l: "Clear annotations", c: [SHIFT_R, { k: "D", }, { k: "D" }] },
              { l: "Confirm region · Cancel", c: [{ k: "return", wide: true }, { k: "esc", wide: true }] },
            ].map((r, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, padding: "11px 16px", borderTop: i ? "1px solid var(--hairline)" : "none" }}>
                <span style={{ fontSize: 13, color: "var(--text1)", fontWeight: 500 }}>{r.l}</span>
                <KeyChord keys={r.c} />
              </div>
            ))}
          </div>
        </Block>

        <Block title="StatusDot & StatusBadge" sub="dot + SF Symbol + gray label — never color alone">
          <Grid cols={2}>
            <Cell label="live states" minH={92}>
              <div style={{ display: "flex", gap: 10, flexWrap: "wrap", justifyContent: "center" }}>
                <StatusBadge state="recording" pulse>Recording</StatusBadge>
                <StatusBadge state="paused" glyph="pause">Paused</StatusBadge>
                <StatusBadge state="processing" pulse>Processing</StatusBadge>
              </div>
            </Cell>
            <Cell label="PacketStatus" minH={92}>
              <div style={{ display: "flex", gap: 10, flexWrap: "wrap", justifyContent: "center" }}>
                <StatusBadge state="success" glyph="check">Succeeded</StatusBadge>
                <StatusBadge state="warning" glyph="info">Partial</StatusBadge>
                <StatusBadge state="error" glyph="info">Failed</StatusBadge>
              </div>
            </Cell>
          </Grid>
        </Block>

        <Block title="CaptureModeCard" sub="default · hover · selected (faint thin ring) · last mode">
          <Grid cols={4}>
            <CaptureModeCard icon="monitor" title="Screen" sub="Capture one display." state="default" />
            <CaptureModeCard icon="window" title="Active Window" sub="Follow the frontmost window." state="hover" />
            <CaptureModeCard icon="region" title="Region" sub="Draw a fixed rectangle." state="selected" />
            <CaptureModeCard icon="smartRegion" title="Smart Region" sub="Follow the cursor in a region." state="last" />
          </Grid>
        </Block>

        <Block title="Packet ListCell" sub="the hero cell — glyph · title · status dot · relative time · duration">
          <div style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: 6 }}>
            <ListCell title="Fix the onboarding empty-state" status="success" time="2 min ago" dur="01:31" selected tint />
            <ListCell title="Refactor settings sheet layout" status="processing" time="just now" dur="00:48" />
            <ListCell title="Dark-mode contrast on toolbar" status="warning" time="22 min ago" dur="02:10" />
            <ListCell title="Region picker — multi-display" status="error" time="1 hr ago" dur="00:12" />
          </div>
          <Caption>Selected reads as a quiet neutral pill. Partial / Failed both say “needs attention” — status is never carried by color alone.</Caption>
        </Block>

        <Block title="Inputs & rows">
          <Grid cols={2}>
            <Cell label="Switch — off / on neutral / on tint (Canvas)" minH={92}>
              <SwitchRow />
            </Cell>
            <Cell label="SecureKeyField — concealed / revealed" minH={92} pad={16}>
              <div style={{ display: "flex", flexDirection: "column", gap: 10, width: "100%" }}>
                <SecureKeyField />
                <SecureKeyField revealed />
              </div>
            </Cell>
            <Cell label="MenuRow" minH={92} pad={10}>
              <div style={{ width: "100%" }}>
                <MenuRow icon="region" label="Start with Picker…" chord={[SHIFT_L, SHIFT_R, { k: "R" }]} />
                <MenuRow icon="repeat" label="Repeat Last Capture" chord={[SHIFT_L, SHIFT_R]} />
                <MenuRow icon="gear" label="Settings" chevron />
              </div>
            </Cell>
            <Cell label="Select — model / profile" minH={92} pad={16}>
              <div style={{ display: "flex", flexDirection: "column", gap: 10, width: "100%" }}>
                <Select value="Claude Sonnet 4.5" hint="latest" />
                <Select value="Builder — concise agent prompt" />
              </div>
            </Cell>
          </Grid>
        </Block>

        <Block title="Cards">
          <Grid cols={2}>
            <ProviderCard name="Anthropic" sub="Summary & agent prompt" model="Claude Sonnet 4.5" hint="latest" ok icon="sparkle" />
            <PermissionCard icon="monitor" title="Screen Recording" desc="Needed to capture displays, windows and regions." granted />
          </Grid>
        </Block>

        <Block title="Indicators">
          <Grid cols={3}>
            <Cell label="MicLevelMeter (continuous)" minH={110}>
              <MicMeter bars={18} h={22} />
            </Cell>
            <Cell label="ProgressIndicator" minH={110} pad={16}>
              <div style={{ width: "100%" }}>
                <ProgressSteps steps={["Transcribing", "Summarizing", "Zipping"]} active={1} />
              </div>
            </Cell>
            <Cell label="CompletionMoment" minH={110}>
              <CompletionMoment replayable />
            </Cell>
            <Cell label="AnnotationSelectionIndicator" bg="canvas" minH={140}>
              <AnnotationSelection />
            </Cell>
            <Cell label="EmptyState" minH={140} pad={0}>
              <EmptyState compact />
            </Cell>
            <Cell label="ProgressIndicator — done" minH={140} pad={16}>
              <div style={{ width: "100%" }}>
                <ProgressSteps steps={["Transcribing", "Summarizing", "Zipping"]} active={3} />
              </div>
            </Cell>
          </Grid>
        </Block>

      </Section>
    );
  }

  function SwitchRow() {
    const [a, setA] = React.useState(false);
    const [b, setB] = React.useState(true);
    const [c, setC] = React.useState(true);
    return (
      <div style={{ display: "flex", gap: 22, alignItems: "center" }}>
        <Switch on={a} onClick={() => setA(v => !v)} />
        <Switch on={b} onClick={() => setB(v => !v)} />
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Switch on={c} tint onClick={() => setC(v => !v)} />
          <span style={{ fontSize: 11.5, color: "var(--text3)" }}>Canvas</span>
        </div>
      </div>
    );
  }

  Object.assign(window, {
    Gallery, CaptureModeCard, MenuRow, ProviderCard, PermissionCard,
    AnnotationSelection, CompletionMoment, EmptyState, FieldLabel: Label,
  });
})();
