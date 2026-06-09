/* ============================================================
   SYN — SCREENS, PART 1
   Menu-bar dropdown · Capture picker sheet · Floating recording HUD
   ============================================================ */
(function () {
  const {
    Icon, Disc, Button, IconButton, KeyChord, KeyCap, SHIFT_L, SHIFT_R,
    StatusDot, StatusBadge, MicMeter, Switch, ProgressSteps, CompletionMoment,
    CaptureModeCard, MenuRow, Section, Stage, Mono, Caption, DesktopBackdrop, VDivider, FieldLabel, FitBox,
  } = window;

  /* ---------------- menu-bar template glyph ---------------- */
  function MenuGlyph({ recording }) {
    return (
      <span style={{ position: "relative", display: "inline-flex", color: recording ? "var(--accent)" : "var(--text1)" }}>
        <Icon name="aperture" size={16} sw={1.5} />
        {recording && <span style={{
          position: "absolute", right: -2, top: -2, width: 5, height: 5, borderRadius: "50%",
          background: "var(--rec)", animation: "pulse-rec 1.6s ease-in-out infinite",
        }} />}
      </span>
    );
  }

  /* ---------------- menu-bar + dropdown ---------------- */
  function MenuPanel({ children, w = 268 }) {
    return (
      <div style={{
        width: w, background: "var(--card)", borderRadius: 12, border: "1px solid var(--hairline)",
        boxShadow: "var(--shadow-float)", padding: 6, animation: "float-in .25s var(--ease-out)",
      }}>{children}</div>
    );
  }

  function MenuHeader({ icon, glyph, color, title, mono, meter, pulse }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "8px 10px 9px", margin: "0 0 4px" }}>
        {glyph
          ? <span style={{ color, display: "inline-flex" }}><Icon name={glyph} size={14} sw={1.8} /></span>
          : <StatusDot state={color} pulse={pulse} size={8} />}
        <span style={{ fontSize: 12.5, fontWeight: 600, color: "var(--text1)" }}>{title}</span>
        {mono && <span style={{ fontFamily: "var(--font-mono)", fontSize: 12.5, color: "var(--text2)", marginLeft: 1 }}>{mono}</span>}
        {meter && <span style={{ marginLeft: "auto" }}><MicMeter bars={9} h={13} w={2.5} /></span>}
      </div>
    );
  }

  const MenuSep = () => <div style={{ height: 1, background: "var(--hairline)", margin: "5px 8px" }} />;

  function IdleMenu() {
    return (
      <MenuPanel>
        <MenuHeader color="success" title="Packet ready" />
        <MenuRow icon="region" label="Start with Picker…" chord={[SHIFT_L, SHIFT_R, { k: "R" }]} />
        <MenuRow icon="repeat" label="Repeat Last Capture" chord={[SHIFT_L, SHIFT_R]} />
        <MenuSep />
        <MenuRow icon="archive" label="Recent Packets" chevron />
        <MenuRow icon="window" label="Open Syn…" />
        <MenuRow icon="gear" label="Settings…" hint="⌘," />
        <MenuSep />
        <MenuRow icon="power" label="Quit Syn" hint="⌘Q" />
      </MenuPanel>
    );
  }

  function RecordingMenu() {
    return (
      <MenuPanel>
        <MenuHeader color="rec" pulse title="Recording" mono="01:31" meter />
        <MenuRow icon="stop" label="Stop & Build Packet" chord={[SHIFT_L, SHIFT_R]} glyphColor="var(--destructive)" />
        <MenuRow icon="pen" label="Toggle Canvas Mode" chord={[SHIFT_R, { k: "C" }]} />
        <MenuRow icon="pause" label="Pause" />
        <MenuSep />
        <MenuRow icon="trash" label="Discard Recording" danger />
      </MenuPanel>
    );
  }

  function MenuBarScreen() {
    return (
      <DesktopBackdrop h={420} tone="warm" style={{ alignItems: "flex-start" }}>
        {/* top menu bar */}
        <div style={{
          position: "absolute", top: 0, left: 0, right: 0, height: 26,
          background: "rgba(250,249,247,0.7)", backdropFilter: "blur(20px) saturate(1.6)",
          WebkitBackdropFilter: "blur(20px) saturate(1.6)", borderBottom: "1px solid rgba(0,0,0,0.06)",
          display: "flex", alignItems: "center", justifyContent: "flex-end", gap: 16, padding: "0 12px",
          fontSize: 12, color: "var(--text1)",
        }}>
          <span style={{ display: "inline-flex", color: "var(--text2)" }}><Icon name="waveform" size={14} sw={1.6} /></span>
          <span style={{ background: "var(--selected)", borderRadius: 5, padding: "3px 5px", display: "inline-flex" }}><MenuGlyph recording /></span>
          <span style={{ fontVariantNumeric: "tabular-nums" }}>Fri 10:24</span>
        </div>
        {/* two dropdowns */}
        <div style={{ position: "absolute", top: 36, right: 14, display: "flex", gap: 22, alignItems: "flex-start" }}>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
            <RecordingMenu />
            <span style={{ fontSize: 10.5, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>recording</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
            <IdleMenu />
            <span style={{ fontSize: 10.5, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>idle · packet ready</span>
          </div>
        </div>
      </DesktopBackdrop>
    );
  }

  /* ---------------- capture picker sheet ---------------- */
  function PickerSection({ label, children }) {
    return (
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text3)", margin: "0 0 10px 2px" }}>{label}</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>{children}</div>
      </div>
    );
  }

  function CapturePicker() {
    return (
      <div style={{
        width: 720, background: "var(--canvas)", borderRadius: 16, border: "1px solid var(--hairline)",
        boxShadow: "var(--shadow-float)", overflow: "hidden",
      }}>
        {/* header */}
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 18px 14px" }}>
          <span style={{ color: "var(--accent)", display: "inline-flex" }}><Icon name="aperture" size={20} sw={1.5} /></span>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.015em" }}>Start Recording</div>
            <div style={{ fontSize: 12, color: "var(--text2)", marginTop: 1 }}>Choose what Syn captures, then narrate.</div>
          </div>
          <IconButton icon="close" label="Close" />
        </div>
        <div style={{ padding: "4px 18px 16px" }}>
          <PickerSection label="Displays">
            <CaptureModeCard icon="monitor" title="Screen" sub="Capture one display." />
            <CaptureModeCard icon="monitors" title="All Screens" sub="Capture every display." />
          </PickerSection>
          <PickerSection label="Windows">
            <CaptureModeCard icon="window" title="Active Window" sub="Follow the frontmost window." />
            <CaptureModeCard icon="windowPick" title="Select Window" sub="Capture one chosen window." />
          </PickerSection>
          <PickerSection label="Targeted">
            <CaptureModeCard icon="region" title="Region" sub="Draw a fixed rectangle." state="last" />
            <CaptureModeCard icon="smartRegion" title="Smart Region" sub="Follow the cursor in a region." />
            <CaptureModeCard icon="chrome" title="Chrome Tab" sub="Capture one Chrome tab." />
          </PickerSection>
        </div>
        {/* mic status footer */}
        <div style={{
          display: "flex", alignItems: "center", gap: 10, padding: "11px 18px", borderTop: "1px solid var(--hairline)",
          background: "var(--card)",
        }}>
          <span style={{ color: "var(--text2)", display: "inline-flex" }}><Icon name="mic" size={15} sw={1.6} /></span>
          <span style={{ fontSize: 12, color: "var(--text2)" }}>MacBook Pro Microphone</span>
          <StatusDot state="success" size={6} />
          <span style={{ marginLeft: 4 }}><MicMeter bars={12} h={14} w={2.5} /></span>
          <span style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 7, fontSize: 11.5, color: "var(--text3)" }}>
            Reopen with <KeyChord keys={[SHIFT_L, SHIFT_R, { k: "R" }]} />
          </span>
        </div>
      </div>
    );
  }

  /* ---------------- floating recording HUD ---------------- */
  function HUDShell({ children, w = 540 }) {
    return (
      <div style={{
        width: w, minHeight: 64, display: "flex", alignItems: "center", gap: 10, padding: "0 12px 0 16px",
        background: "var(--material)", backdropFilter: "blur(30px) saturate(1.8)", WebkitBackdropFilter: "blur(30px) saturate(1.8)",
        border: "1px solid var(--material-border)", borderRadius: 16, boxShadow: "var(--shadow-float)", height: 64,
      }}>{children}</div>
    );
  }

  function DiscardButton() {
    const [armed, setArmed] = React.useState(false);
    const [count, setCount] = React.useState(3);
    React.useEffect(() => {
      if (!armed) { setCount(3); return; }
      if (count === 0) { setArmed(false); return; }
      const t = setTimeout(() => setCount((c) => c - 1), 800);
      return () => clearTimeout(t);
    }, [armed, count]);
    return (
      <button onClick={() => setArmed((a) => !a)} style={{
        display: "inline-flex", alignItems: "center", gap: 6, height: 32, padding: "0 11px", borderRadius: 8,
        border: "1px solid", borderColor: armed ? "var(--accent-ring)" : "transparent",
        background: armed ? "var(--accent-tint)" : "transparent", color: armed ? "var(--destructive)" : "var(--text2)",
        cursor: "pointer", font: "inherit", fontSize: 12.5, fontWeight: 550, transition: "background .15s, color .15s",
      }}>
        <Icon name="trash" size={14} sw={1.7} />
        {armed ? <span style={{ fontFamily: "var(--font-mono)" }}>Tap again · {count}</span> : "Discard"}
      </button>
    );
  }

  function HUDRecording({ canvasOn }) {
    return (
      <HUDShell>
        <span style={{ display: "inline-flex", alignItems: "center", gap: 9 }}>
          <StatusDot state="rec" pulse size={9} />
          <span style={{ fontSize: 13.5, fontWeight: 600, color: "var(--text1)" }}>Region</span>
        </span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 15, fontWeight: 500, color: "var(--text1)", letterSpacing: "-0.01em", fontVariantNumeric: "tabular-nums" }}>01:31</span>
        <MicMeter bars={12} h={18} w={2.5} />
        <div style={{ display: "flex", alignItems: "center", gap: 6, marginLeft: "auto" }}>
          <VDivider h={26} />
          <button style={{
            display: "inline-flex", alignItems: "center", gap: 7, height: 32, padding: "0 11px", borderRadius: 8,
            border: "1px solid", borderColor: canvasOn ? "var(--accent-ring)" : "transparent",
            background: canvasOn ? "var(--accent-tint)" : "transparent", color: canvasOn ? "var(--accent-deep)" : "var(--text1)",
            cursor: "pointer", font: "inherit", fontSize: 12.5, fontWeight: 550,
          }}>
            <Icon name="pen" size={15} sw={1.7} /> Canvas
          </button>
          <IconButton icon="pause" label="Pause" />
          <DiscardButton />
          <button style={{
            display: "inline-flex", alignItems: "center", gap: 7, height: 32, padding: "0 13px", borderRadius: 8,
            border: "1px solid var(--hairline-strong)", background: "var(--card)", color: "var(--destructive)",
            cursor: "pointer", font: "inherit", fontSize: 12.5, fontWeight: 600, boxShadow: "var(--shadow-1)",
          }}>
            <Icon name="stop" size={13} sw={1.8} /> Stop
          </button>
        </div>
      </HUDShell>
    );
  }

  function HUDProcessing() {
    return (
      <HUDShell>
        <span style={{ width: 22, height: 22, borderRadius: "50%", border: "2.5px solid var(--accent-tint)", borderTopColor: "var(--accent)", animation: "spin .9s linear infinite", flex: "none" }} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: "var(--text1)" }}>Building packet…</div>
          <div style={{ fontSize: 11.5, color: "var(--text2)", marginTop: 1 }}>Summarizing transcript · step 2 of 3</div>
        </div>
        <div style={{ width: 120 }}>
          <div style={{ height: 4, borderRadius: 999, background: "var(--surface3)", overflow: "hidden" }}>
            <div style={{ width: "62%", height: "100%", borderRadius: 999, background: "var(--accent)" }} />
          </div>
        </div>
      </HUDShell>
    );
  }

  function HUDCompletion() {
    return (
      <HUDShell>
        <CompletionMoment />
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: 11.5, color: "var(--text2)", marginRight: 4 }}>Copied to clipboard</span>
        <Button variant="primary" size="sm" icon="copy">Copy again</Button>
      </HUDShell>
    );
  }

  /* ---------------- section ---------------- */
  function ScreensOne() {
    return (
      <>
        <Section id="menubar" eyebrow="Screens" title="Menu-bar dropdown"
          desc="Syn lives only in the menu bar (LSUIElement — no Dock icon). The template glyph is monochrome and tints rose only while recording. A status header opens every menu; rows carry leading SF Symbols and trailing chord hints.">
          <MenuBarScreen />
          <Caption>Header swaps with state: “Recording 01:31”, “Canvas on”, “Processing packet…”, “Packet ready”. The recording menu demotes Discard to a red glyph; Quit Syn sits behind ⌘Q.</Caption>
        </Section>

        <Section id="picker" eyebrow="Screens" title="Capture picker"
          desc="A sheet, never a detail-pane takeover. Seven neutral mode cards in three sections; the last-used mode wears a thin faint-rose ring. An unobtrusive mic row sits at the foot.">
          <Stage variant="canvas" pad={34}>
            <FitBox w={720}><CapturePicker /></FitBox>
          </Stage>
        </Section>

        <Section id="hud" eyebrow="Screens" title="Recording HUD"
          desc="A small, light, frosted panel — non-activating, draggable, multi-display aware. Live dot, mode title, a monospaced timer, the continuous mic meter, a neutral Canvas toggle (faint rose when active), Pause, a two-step Discard with a visible countdown, and Stop as a neutral button with a red glyph. No drawing tools live here.">
          <DesktopBackdrop h={150} tone="code"><HUDRecording /></DesktopBackdrop>
          <Caption>Recording — Canvas off.</Caption>
          <div style={{ height: 18 }} />
          <DesktopBackdrop h={150} tone="code"><HUDRecording canvasOn /></DesktopBackdrop>
          <Caption>Canvas on — the toggle picks up a faint rose tint; drawing tools live in a separate toolbar, never the HUD.</Caption>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18, marginTop: 18 }}>
            <div><DesktopBackdrop h={130} tone="code"><HUDProcessing /></DesktopBackdrop><Caption>Processing.</Caption></div>
            <div><DesktopBackdrop h={130} tone="code"><HUDCompletion /></DesktopBackdrop><Caption>Completion — one calm beat, then “Packet ready”.</Caption></div>
          </div>
        </Section>
      </>
    );
  }

  Object.assign(window, { ScreensOne, MenuGlyph, HUDRecording, CapturePicker });
})();
