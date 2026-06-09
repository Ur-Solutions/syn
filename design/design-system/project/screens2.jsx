/* ============================================================
   SYN — SCREENS, PART 2
   Canvas Mode · Region overlay · Overview window · Settings ·
   App icon · Dark-mode check
   ============================================================ */
(function () {
  const {
    Icon, Disc, Button, IconButton, ToolButton, KeyChord, KeyCap, SHIFT_L, SHIFT_R,
    StatusDot, StatusBadge, MicMeter, Switch, Select, SecureKeyField, ProgressSteps,
    ListCell, MenuRow, ProviderCard, PermissionCard, AnnotationSelection, EmptyState,
    HUDRecording, TrafficLights, VDivider, FieldLabel, FitBox,
    Section, Stage, Mono, Caption, DesktopBackdrop,
  } = window;

  /* ============ CANVAS MODE ============ */
  function CanvasToolbar({ deleteEnabled = true }) {
    return (
      <div style={{
        width: 330, height: 56, display: "flex", alignItems: "center", gap: 3, padding: "0 8px 0 4px",
        background: "var(--material)", backdropFilter: "blur(30px) saturate(1.8)", WebkitBackdropFilter: "blur(30px) saturate(1.8)",
        border: "1px solid var(--material-border)", borderRadius: 14, boxShadow: "var(--shadow-float)",
      }}>
        <span style={{ display: "flex", padding: "0 4px", color: "var(--text3)", cursor: "grab" }}><Icon name="grip" size={18} sw={1.6} /></span>
        <ToolButton icon="pen" active label="Pen" />
        <ToolButton icon="line" label="Line" />
        <ToolButton icon="rectangle" label="Rectangle" />
        <ToolButton icon="ellipse" label="Ellipse" />
        <VDivider h={24} m={3} />
        <IconButton icon="trash" disabled={!deleteEnabled} danger={deleteEnabled} label="Delete selected" size={32} />
        <IconButton icon="eraser" label="Clear" size={32} />
        <IconButton icon="close" label="Exit Canvas" size={32} />
      </div>
    );
  }

  function CanvasScene() {
    return (
      <DesktopBackdrop h={460} tone="code">
        {/* annotations layer */}
        <svg viewBox="0 0 760 460" style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }} aria-hidden="true">
          {/* pen scribble with white halo */}
          <path d="M150 330 q 18 -36 40 -10 t 42 -4 q 20 -28 44 2 t 40 -8"
            className="ink-halo" fill="none" stroke="var(--ink)" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" />
          {/* rose rectangle */}
          <rect x="470" y="120" width="180" height="96" rx="6" className="ink-halo" fill="none" stroke="var(--ink)" strokeWidth="3" />
          {/* a circle annotation */}
          <ellipse cx="250" cy="160" rx="64" ry="40" className="ink-halo" fill="none" stroke="var(--ink)" strokeWidth="3" />
        </svg>
        {/* selection box around the rectangle */}
        <div style={{ position: "absolute", left: "61.8%", top: "25.5%" }}>
          <AnnotationSelection w={190} h={106} />
        </div>
        {/* HUD on top — Canvas on */}
        <div style={{ position: "absolute", top: 20, left: "50%", transform: "translateX(-50%) scale(0.92)", transformOrigin: "top center" }}>
          <HUDRecording canvasOn />
        </div>
        {/* canvas toolbar below the HUD */}
        <div style={{ position: "absolute", top: 104, left: "50%", transform: "translateX(-50%)" }}>
          <CanvasToolbar />
        </div>
        {/* shortcut chips */}
        <div style={{ position: "absolute", bottom: 16, left: 16, display: "flex", gap: 14, alignItems: "center", background: "var(--material)", backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)", border: "1px solid var(--material-border)", borderRadius: 10, padding: "8px 12px", boxShadow: "var(--shadow-2)" }}>
          {[["Pen", [SHIFT_R, { k: "1" }]], ["Line", [SHIFT_R, { k: "2" }]], ["Rect", [SHIFT_R, { k: "3" }]], ["Ellipse", [SHIFT_R, { k: "4" }]], ["Clear", [SHIFT_R, { k: "D" }, { k: "D" }]]].map(([l, c], i) => (
            <span key={i} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, color: "var(--text2)" }}>{l} <KeyChord keys={c} /></span>
          ))}
        </div>
      </DesktopBackdrop>
    );
  }

  /* ============ REGION SELECTION OVERLAY ============ */
  function OverlayControlHUD() {
    return (
      <div style={{
        display: "flex", alignItems: "center", gap: 12, padding: "9px 10px 9px 14px",
        background: "var(--material)", backdropFilter: "blur(30px) saturate(1.8)", WebkitBackdropFilter: "blur(30px) saturate(1.8)",
        border: "1px solid var(--material-border)", borderRadius: 12, boxShadow: "var(--shadow-float)",
      }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 13, fontWeight: 500, color: "var(--text1)", background: "var(--surface2)", border: "1px solid var(--hairline)", borderRadius: 7, padding: "4px 9px", fontVariantNumeric: "tabular-nums" }}>1280 × 720</span>
        <VDivider h={22} />
        <span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11.5, color: "var(--text2)" }}>Cancel <KeyCap wide>esc</KeyCap></span>
        <Button variant="primary" size="sm" icon="check">Confirm <KeyCap wide>return</KeyCap></Button>
      </div>
    );
  }

  function RegionOverlayScene() {
    return (
      <DesktopBackdrop h={420} tone="warm">
        {/* dim scrim */}
        <div style={{ position: "absolute", inset: 0, background: "var(--scrim)" }} />
        {/* selection rect — brighter (un-dimmed) interior + rose stroke */}
        <div style={{ position: "absolute", left: "26%", top: "24%", width: "44%", height: "44%", borderRadius: 4, outline: "1.5px solid var(--accent)", outlineOffset: 0, boxShadow: "0 0 0 1px var(--ink-halo)", overflow: "hidden" }}>
          <div className="syn-wallpaper syn-wall-warm" style={{ position: "absolute", inset: 0 }} />
          {/* corner handles */}
          {[[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y], i) => (
            <span key={i} style={{ position: "absolute", width: 9, height: 9, borderRadius: 2, background: "var(--card)", border: "1.5px solid var(--accent)", left: x ? "100%" : 0, top: y ? "100%" : 0, transform: "translate(-50%,-50%)" }} />
          ))}
          {/* live W×H chip near corner */}
          <span style={{ position: "absolute", left: 8, top: 8, fontFamily: "var(--font-mono)", fontSize: 11, color: "#fff", background: "rgba(28,28,30,0.62)", borderRadius: 6, padding: "2px 7px", fontVariantNumeric: "tabular-nums" }}>1280 × 720</span>
        </div>
        {/* shared overlay control HUD */}
        <div style={{ position: "absolute", left: "50%", bottom: 28, transform: "translateX(-50%)" }}>
          <OverlayControlHUD />
        </div>
      </DesktopBackdrop>
    );
  }

  /* ============ OVERVIEW WINDOW ============ */
  function PacketFile({ name, hero, sub }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "7px 10px", borderRadius: 8, background: hero ? "var(--accent-tint)" : "transparent", border: hero ? "1px solid var(--accent-ring)" : "1px solid transparent" }}>
        <span style={{ color: hero ? "var(--accent-deep)" : "var(--text3)", display: "inline-flex" }}><Icon name={hero ? "sparkle" : "doc"} size={15} sw={1.6} /></span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: hero ? "var(--accent-deep)" : "var(--text1)", fontWeight: hero ? 600 : 400 }}>{name}</span>
        {hero && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: "0.04em", textTransform: "uppercase", color: "var(--accent-deep)", marginLeft: 2 }}>hero</span>}
        <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--text3)" }}>{sub}</span>
      </div>
    );
  }

  function TrimScrubber() {
    return (
      <div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
          <FieldLabel>Trim</FieldLabel>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11.5, color: "var(--text3)" }}>00:06 – 01:24 · 01:18</span>
        </div>
        <div style={{ position: "relative", height: 44, borderRadius: 8, overflow: "hidden", border: "1px solid var(--hairline)", display: "flex" }}>
          {Array.from({ length: 10 }).map((_, i) => (
            <span key={i} className="syn-wall-code" style={{ flex: 1, borderRight: i < 9 ? "1px solid rgba(255,255,255,0.5)" : "none" }} />
          ))}
          {/* dim outside trim */}
          <span style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: "8%", background: "rgba(28,28,30,0.34)" }} />
          <span style={{ position: "absolute", right: 0, top: 0, bottom: 0, width: "12%", background: "rgba(28,28,30,0.34)" }} />
          {/* trim handles */}
          <span style={{ position: "absolute", left: "8%", top: 0, bottom: 0, width: 8, background: "var(--card)", borderRadius: 3, boxShadow: "0 0 0 1px var(--hairline-strong)", transform: "translateX(-50%)", cursor: "ew-resize" }} />
          <span style={{ position: "absolute", left: "88%", top: 0, bottom: 0, width: 8, background: "var(--card)", borderRadius: 3, boxShadow: "0 0 0 1px var(--hairline-strong)", transform: "translateX(-50%)", cursor: "ew-resize" }} />
          {/* playhead */}
          <span style={{ position: "absolute", left: "46%", top: -2, bottom: -2, width: 2, background: "var(--accent)", boxShadow: "0 0 0 1px var(--ink-halo)" }} />
        </div>
      </div>
    );
  }

  function OverviewWindow() {
    const histItems = [
      { t: "Fix the onboarding empty-state", s: "success", time: "2 min ago", d: "01:31", sel: true },
      { t: "Refactor settings sheet layout", s: "processing", time: "just now", d: "00:48" },
      { t: "Dark-mode contrast on toolbar", s: "warning", time: "22 min ago", d: "02:10" },
      { t: "Region picker — multi-display", s: "success", time: "1 hr ago", d: "00:55" },
    ];
    return (
      <div style={{ width: 860, height: 560, borderRadius: 14, overflow: "hidden", border: "1px solid var(--hairline-strong)", boxShadow: "var(--shadow-float)", display: "flex", background: "var(--canvas)" }}>
        {/* sidebar */}
        <div style={{ width: 252, background: "var(--sidebar)", borderRight: "1px solid var(--hairline)", display: "flex", flexDirection: "column" }}>
          <div style={{ height: 44, display: "flex", alignItems: "center", gap: 12, padding: "0 14px", WebkitAppRegion: "drag" }}>
            <TrafficLights />
            <span style={{ display: "inline-flex", color: "var(--accent)", marginLeft: 4 }}><Icon name="aperture" size={15} sw={1.5} /></span>
            <span style={{ fontSize: 13, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.02em" }}>Syn</span>
          </div>
          <div style={{ padding: "6px 8px", overflow: "auto" }} className="thin-scroll">
            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--text3)", padding: "8px 8px 6px" }}>Capture</div>
            <MenuRow icon="region" label="Start with Picker…" chord={[SHIFT_L, SHIFT_R, { k: "R" }]} />
            <MenuRow icon="repeat" label="Repeat Last Capture" />
            <MenuRow icon="gear" label="Settings" />
            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--text3)", padding: "14px 8px 6px" }}>History</div>
            {histItems.map((h, i) => (
              <ListCell key={i} title={h.t} status={h.s} time={h.time} dur={h.d} selected={h.sel} tint={h.sel} />
            ))}
          </div>
        </div>
        {/* detail */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
          {/* live status strip */}
          <div style={{ height: 44, display: "flex", alignItems: "center", gap: 10, padding: "0 18px", borderBottom: "1px solid var(--hairline)", background: "var(--card)" }}>
            <StatusBadge state="success" glyph="check">Packet ready</StatusBadge>
            <span style={{ fontSize: 12, color: "var(--text3)" }}>Auto-copied to clipboard · ready to paste</span>
            <span style={{ marginLeft: "auto" }}><MicMeter bars={9} h={13} w={2.5} live={false} level={0.2} /></span>
          </div>
          {/* packet detail */}
          <div style={{ flex: 1, overflow: "auto", padding: 22 }} className="thin-scroll">
            <div style={{ display: "flex", alignItems: "flex-start", gap: 12, marginBottom: 18 }}>
              <div style={{ flex: 1 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
                  <h3 style={{ margin: 0, fontSize: 19, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.02em" }}>Fix the onboarding empty-state</h3>
                  <StatusBadge state="success" glyph="check">Succeeded</StatusBadge>
                </div>
                <div style={{ fontSize: 12, color: "var(--text2)", marginTop: 5, display: "flex", gap: 10, fontFamily: "var(--font-mono)" }}>
                  <span>2 min ago</span><span>·</span><span>01:31</span><span>·</span><span>v3</span><span>·</span><span>14.2 MB</span>
                </div>
              </div>
            </div>

            {/* actions */}
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
              <Button variant="primary" icon="copy">Copy Packet</Button>
              <Button variant="secondary" icon="folder">Open Folder</Button>
              <Button variant="secondary" icon="archive">Reveal Zip</Button>
              <Button variant="tertiary" icon="bolt">Compact Zip</Button>
              <span style={{ marginLeft: "auto" }}><Button variant="destructive" icon="trash">Delete</Button></span>
            </div>

            {/* trim */}
            <div style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: 16, marginBottom: 16 }}>
              <TrimScrubber />
            </div>

            {/* packet contents */}
            <div style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: "14px 14px 10px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8, padding: "0 2px" }}>
                <FieldLabel>Syn Packet · the product</FieldLabel>
                <span style={{ fontSize: 11, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>manifest.json</span>
              </div>
              <PacketFile name="agent-prompt.md" hero sub="2.1 KB" />
              <PacketFile name="summary.md" sub="1.4 KB" />
              <PacketFile name="transcript.md" sub="6.8 KB" />
              <PacketFile name="semantic-timeline.md" sub="3.2 KB" />
              <PacketFile name="recording.mp4" sub="13.6 MB" />
              <PacketFile name="frames/ (12)" sub="0.9 MB" />
            </div>
          </div>
        </div>
      </div>
    );
  }

  /* ============ SETTINGS WINDOW ============ */
  function SettingsRow({ label, sub, children }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "12px 0", borderTop: "1px solid var(--hairline)" }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 550, color: "var(--text1)" }}>{label}</div>
          {sub && <div style={{ fontSize: 11.5, color: "var(--text2)", marginTop: 2 }}>{sub}</div>}
        </div>
        {children}
      </div>
    );
  }
  function SettingsCard({ title, children }) {
    return (
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color: "var(--text3)", margin: "0 0 8px 2px" }}>{title}</div>
        <div style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: "2px 16px" }}>{children}</div>
      </div>
    );
  }

  function SettingsWindow() {
    const tabs = [["sliders", "General"], ["key", "Hotkeys"], ["folder", "Output"], ["sparkle", "Agent Prompt"], ["brain", "AI Providers"]];
    return (
      <div style={{ width: 520, borderRadius: 14, overflow: "hidden", border: "1px solid var(--hairline-strong)", boxShadow: "var(--shadow-float)", background: "var(--canvas)" }}>
        <div style={{ height: 44, display: "flex", alignItems: "center", gap: 12, padding: "0 14px", borderBottom: "1px solid var(--hairline)", background: "var(--sidebar)" }}>
          <TrafficLights />
          <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text1)", marginLeft: 4 }}>Settings</span>
        </div>
        {/* tab bar */}
        <div style={{ display: "flex", gap: 4, padding: "10px 14px", borderBottom: "1px solid var(--hairline)", background: "var(--card)" }}>
          {tabs.map(([ic, l], i) => (
            <div key={l} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4, padding: "6px 12px", borderRadius: 8, background: i === 4 ? "var(--selected)" : "transparent", color: i === 4 ? "var(--text1)" : "var(--text2)", cursor: "pointer", minWidth: 58 }}>
              <Icon name={ic} size={18} sw={1.6} />
              <span style={{ fontSize: 10.5, fontWeight: 500 }}>{l}</span>
            </div>
          ))}
        </div>
        <div style={{ padding: 18, maxHeight: 440, overflow: "auto" }} className="thin-scroll">
          <SettingsCard title="Hotkeys">
            <SettingsRow label="Open capture picker"><KeyChord keys={[SHIFT_L, SHIFT_R, { k: "R" }]} /></SettingsRow>
            <SettingsRow label="Repeat last capture"><KeyChord keys={[SHIFT_L, SHIFT_R]} /></SettingsRow>
            <SettingsRow label="Toggle Canvas Mode"><KeyChord keys={[SHIFT_R, { k: "C" }]} /></SettingsRow>
          </SettingsCard>
          <SettingsCard title="Agent Prompt">
            <SettingsRow label="Profile" sub="Tone & structure of agent-prompt.md"><div style={{ width: 220 }}><Select value="Builder — concise, evidence-first" /></div></SettingsRow>
            <SettingsRow label="Include semantic timeline"><Switch on /></SettingsRow>
          </SettingsCard>
          <SettingsCard title="Project Context">
            <SettingsRow label="Repository" sub="Linked for relative file paths"><span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--text2)" }}>~/dev/syn-app</span></SettingsRow>
          </SettingsCard>
          <SettingsCard title="AI Providers">
            <SettingsRow label="Anthropic" sub="Summary & agent prompt">
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}><StatusDot state="success" size={7} /><span style={{ fontSize: 12, color: "var(--text2)" }}>Available</span></div>
            </SettingsRow>
            <div style={{ padding: "4px 0 14px" }}>
              <div style={{ display: "flex", gap: 10 }}>
                <div style={{ flex: 1 }}><FieldLabel>Model</FieldLabel><Select value="Claude Sonnet 4.5" hint="latest" /></div>
                <div style={{ flex: 1 }}><FieldLabel>API key</FieldLabel><SecureKeyField /></div>
              </div>
            </div>
          </SettingsCard>
        </div>
      </div>
    );
  }

  /* ============ APP ICON ============ */
  function Squircle({ size = 96, children, bg = "var(--card)", ring }) {
    return (
      <div style={{
        width: size, height: size, borderRadius: size * 0.225,
        background: bg, border: ring || "1px solid var(--hairline)",
        boxShadow: "var(--shadow-2), inset 0 1px 0 rgba(255,255,255,0.7)",
        display: "flex", alignItems: "center", justifyContent: "center", position: "relative", overflow: "hidden",
      }}>{children}</div>
    );
  }

  function AppIconConcepts() {
    return (
      <div style={{ display: "flex", gap: 26, flexWrap: "wrap" }}>
        {/* A — aperture, one rose blade */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
          <Squircle bg="linear-gradient(160deg,#FFFFFF,#F3F1ED)">
            <svg width="58" height="58" viewBox="0 0 58 58" fill="none" stroke="var(--text2)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="29" cy="29" r="20" />
              <path d="M29 9l8.7 15M49 24l-17.3 0M44.3 44.3l-8.7-15M29 49l-8.7-15M9 34l17.3 0M13.7 13.7l8.7 15" />
              <circle cx="29" cy="29" r="5.5" fill="var(--accent)" stroke="none" />
            </svg>
          </Squircle>
          <span style={{ fontSize: 11.5, color: "var(--text2)" }}>Aperture · rose core</span>
        </div>
        {/* B — sight / viewfinder */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
          <Squircle bg="linear-gradient(160deg,#FFFFFF,#F1EFEB)">
            <svg width="58" height="58" viewBox="0 0 58 58" fill="none" stroke="var(--text2)" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 19v-4a3 3 0 0 1 3-3h4M39 12h4a3 3 0 0 1 3 3v4M46 39v4a3 3 0 0 1-3 3h-4M19 46h-4a3 3 0 0 1-3-3v-4" />
              <circle cx="29" cy="29" r="8" stroke="var(--accent)" />
              <circle cx="29" cy="29" r="2.4" fill="var(--accent)" stroke="none" />
            </svg>
          </Squircle>
          <span style={{ fontSize: 11.5, color: "var(--text2)" }}>Sight · rose reticle</span>
        </div>
        {/* C — aperture ring + pen */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
          <Squircle bg="linear-gradient(160deg,#FBEDEF,#FFFFFF)" ring="1px solid var(--accent-ring)">
            <svg width="58" height="58" viewBox="0 0 58 58" fill="none" stroke="var(--accent)" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="29" cy="29" r="18" stroke="var(--text2)" />
              <path d="M22 36l1.5-5 11-11a2.4 2.4 0 0 1 3.4 3.4l-11 11-5 1.5Z" />
            </svg>
          </Squircle>
          <span style={{ fontSize: 11.5, color: "var(--text2)" }}>Ring · narrate + draw</span>
        </div>
      </div>
    );
  }

  function TemplateGlyphStates() {
    const states = [
      { l: "Idle", color: "var(--text1)", dot: null },
      { l: "Recording", color: "var(--accent)", dot: "var(--rec)" },
      { l: "Canvas", color: "var(--text1)", pen: true },
      { l: "Processing", color: "var(--text2)", spin: true },
    ];
    return (
      <div style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>
        {states.map((s) => (
          <div key={s.l} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
            <div style={{ width: 44, height: 30, borderRadius: 7, background: "var(--sidebar)", border: "1px solid var(--hairline)", display: "flex", alignItems: "center", justifyContent: "center", position: "relative" }}>
              <span style={{ position: "relative", display: "inline-flex", color: s.color }}>
                <Icon name="aperture" size={16} sw={1.6} />
                {s.dot && <span style={{ position: "absolute", right: -2, top: -2, width: 5, height: 5, borderRadius: "50%", background: s.dot }} />}
                {s.pen && <span style={{ position: "absolute", right: -4, bottom: -3, color: "var(--text1)" }}><Icon name="pen" size={9} sw={2} /></span>}
                {s.spin && <span style={{ position: "absolute", inset: -3, borderRadius: "50%", border: "1.5px solid var(--hairline-strong)", borderTopColor: "var(--text2)", animation: "spin 1s linear infinite" }} />}
              </span>
            </div>
            <span style={{ fontSize: 10.5, color: "var(--text3)" }}>{s.l}</span>
          </div>
        ))}
      </div>
    );
  }

  /* ============ DARK-MODE CHECK ============ */
  function DarkCheck() {
    return (
      <div className="theme-dark" style={{ background: "var(--canvas)", borderRadius: 16, border: "1px solid var(--hairline)", padding: 26 }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 18, alignItems: "center" }}>
          <div style={{ width: 470, maxWidth: "100%" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "0 12px 0 16px", height: 60, background: "var(--material)", border: "1px solid var(--material-border)", borderRadius: 14, boxShadow: "var(--shadow-float)" }}>
              <StatusDot state="rec" pulse size={9} />
              <span style={{ fontSize: 13.5, fontWeight: 600, color: "var(--text1)" }}>Region</span>
              <span style={{ fontFamily: "var(--font-mono)", fontSize: 14, color: "var(--text1)" }}>01:31</span>
              <MicMeter bars={12} h={16} w={2.5} />
              <VDivider h={24} />
              <Button variant="primary" size="sm" icon="pen">Canvas</Button>
              <span style={{ marginLeft: "auto" }}><Button variant="destructive" size="sm" icon="stop">Stop</Button></span>
            </div>
          </div>
          <div style={{ width: 300, background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: 6 }}>
            <ListCell title="Fix the onboarding empty-state" status="success" time="2 min ago" dur="01:31" selected tint />
            <ListCell title="Dark-mode contrast pass" status="processing" time="now" dur="00:48" />
          </div>
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <Button variant="primary" icon="copy">Copy Packet</Button>
            <Button variant="secondary" icon="folder">Open</Button>
            <StatusBadge state="success" glyph="check">Succeeded</StatusBadge>
          </div>
        </div>
      </div>
    );
  }

  /* ============ section ============ */
  function ScreensTwo() {
    return (
      <>
        <Section id="canvas" eyebrow="Screens" title="Canvas Mode"
          desc="Draw directly on the screen. The HUD stays on top (Canvas toggle faintly tinted); a separate floating Syn Canvas toolbar — draggable, frosted — carries the tools. Rose ink wears a white halo so it survives any background; the active tool is a faint rose tint, never a filled button.">
          <CanvasScene />
          <div style={{ display: "flex", gap: 30, marginTop: 18, alignItems: "center", flexWrap: "wrap" }}>
            <div><Caption style={{ margin: "0 0 8px" }}>Delete-selected — enabled vs disabled:</Caption>
              <div style={{ display: "flex", gap: 16 }}>
                <div style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "center" }}><CanvasToolbar deleteEnabled /><span style={{ fontSize: 10.5, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>shape selected</span></div>
              </div>
            </div>
          </div>
          <Caption>Pen scribble, a rectangle, and an ellipse — one shape selected with a thin dashed rose box. Tool shortcuts show as neutral key-cap chips: Right ⇧ + 1/2/3/4, Right ⇧ + D D to clear.</Caption>
        </Section>

        <Section id="overlay" eyebrow="Screens" title="Region-selection overlay"
          desc="A soft, light frosted wash dims the screen; a thin rose stroke marks the selection. The shared OverlayControlHUD confirms or cancels with Return / Esc chips and a live W × H readout.">
          <RegionOverlayScene />
        </Section>

        <Section id="overview" eyebrow="Screens" title="Overview window"
          desc="A NavigationSplitView: a warm translucent sidebar (Capture actions, then History as packet cells) beside a calm detail pane. One subtly rose-tinted Copy Packet primary; everything else — Open Folder, Reveal Zip, Compact Zip — is neutral, and Delete is a demoted red glyph. agent-prompt.md is the hero artifact of every packet.">
          <Stage variant="canvas" pad={28}>
            <FitBox w={860}><OverviewWindow /></FitBox>
          </Stage>
        </Section>

        <Section id="settings" eyebrow="Screens" title="Settings"
          desc="Neutral card sections with humanized copy: Hotkeys as key-cap chips, Output, the Agent Prompt profile picker, Project Context, and AI Providers with a model selector, secure key field, and a small availability dot.">
          <Stage variant="canvas" pad={28}>
            <FitBox w={520}><SettingsWindow /></FitBox>
          </Stage>
        </Section>

        <Section id="icon" eyebrow="Brand" title="App icon & menu-bar glyph"
          desc="Light squircle concepts on an aperture / sight motif — mostly neutral, rose used only as a restrained accent. The menu-bar glyph is a monochrome template that shows state through shape, taking a subtle rose tint only while recording.">
          <Stage variant="card" pad={30} align="flex-start" style={{ marginBottom: 22 }}>
            <AppIconConcepts />
          </Stage>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
            <Stage variant="card" pad={24} align="flex-start" label="menu-bar template glyph — state variants"><TemplateGlyphStates /></Stage>
            <Stage variant="card" pad={24} align="flex-start" label="empty state — branded but calm"><EmptyState compact /></Stage>
          </div>
        </Section>

        <Section id="dark" eyebrow="Brand" title="Dark-mode adaptive check"
          desc="Light is the showcase, but every token is a dynamic set. The same components adapt cleanly to dark — rose stays a whisper, neutrals carry the surface, and the ink halo flips to keep annotations legible.">
          <DarkCheck />
        </Section>
      </>
    );
  }

  Object.assign(window, { ScreensTwo });
})();
