/* ============================================================
   SYN — TOKEN DATA + SHARED SPEC-SHEET HELPERS
   Exported to window for the foundations/gallery/screens scripts.
   ============================================================ */
(function () {
  // ---------- TOKEN DATA ----------
  const COLORS = {
    neutral: {
      title: "Warm neutrals — the whole interface",
      note: "Light is the showcase. Everything is warm-neutral greyscale by default.",
      swatches: [
        { name: "Window / Content", v: "--canvas", hex: "#F5F4F1", use: "App & content background" },
        { name: "Sidebar", v: "--sidebar", hex: "#F1F0EC", use: "Translucent warm vibrancy" },
        { name: "Card / Elevated", v: "--card", hex: "#FFFFFF", use: "Data surfaces, sheets" },
        { name: "Hover / Selected", v: "--selected", hex: "#ECEBE7", use: "Neutral selection fill" },
        { name: "Hairline", v: "--hairline", hex: "#E7E5E0", use: "Separators & borders" },
        { name: "Text Primary", v: "--text1", hex: "#1C1C1E", use: "Titles, body", dark: true },
        { name: "Text Secondary", v: "--text2", hex: "#6E6E73", use: "Subtitles, labels", dark: true },
        { name: "Text Tertiary", v: "--text3", hex: "#9B9BA0", use: "Hints, metadata" },
      ],
    },
    accent: {
      title: "Rose-coral — a whisper",
      note: "Appears only at small surface area: the live dot, the active tool, one tinted action per view.",
      swatches: [
        { name: "Accent", v: "--accent", hex: "#EC6579", use: "Live dot · active tool · badge", dark: true },
        { name: "Hover", v: "--accent-hover", hex: "#E24B62", use: "Pointer-over", dark: true },
        { name: "Pressed", v: "--accent-pressed", hex: "#D63850", use: "Active press", dark: true },
        { name: "Faint Tint", v: "--accent-tint", hex: "#FDEBEE", use: "Selection / primary fill" },
        { name: "Ring", v: "--accent-ring", hex: "#F099A6", use: "Focus / 'last mode'" },
        { name: "Deep Rose", v: "--accent-deep", hex: "#D63850", use: "Text on tint", dark: true },
      ],
    },
    semantic: {
      title: "State tokens — small dots & glyphs only",
      note: "Never large fills. Status is dot + SF Symbol + gray label — never color alone.",
      swatches: [
        { name: "Recording / Live", v: "--rec", hex: "#EC6579", use: "= accent", dark: true },
        { name: "Success", v: "--success", hex: "#34C759", use: "Succeeded", dark: true },
        { name: "Processing / Info", v: "--processing", hex: "#2E8BFF", use: "In progress", dark: true },
        { name: "Warning / Paused", v: "--warning", hex: "#F5A623", use: "Needs attention", dark: true },
        { name: "Destructive / Error", v: "--destructive", hex: "#E5342B", use: "Rare · reserved", dark: true },
      ],
    },
  };

  const TYPE = [
    { name: "Large Title", px: 26, w: 700, ls: "-0.02em", role: "Window titles, wordmark", sample: "Syn Packet" },
    { name: "Title 2", px: 20, w: 600, ls: "-0.02em", role: "Sheet & section headers", sample: "Start Recording" },
    { name: "Title 3", px: 17, w: 600, ls: "-0.01em", role: "Card titles, list cells", sample: "Region capture" },
    { name: "Headline", px: 14, w: 600, ls: "-0.01em", role: "Emphasis, row labels", sample: "Repeat Last Capture" },
    { name: "Body", px: 13, w: 400, ls: "-0.005em", role: "Default reading text", sample: "Follow the frontmost window." },
    { name: "Subhead", px: 12, w: 400, ls: "0", role: "Secondary descriptions", sample: "Capture one chosen window." },
    { name: "Footnote", px: 11, w: 500, ls: "0.01em", role: "Metadata, chip labels", sample: "2 min ago · 01:31" },
    { name: "Caption", px: 10.5, w: 600, ls: "0.06em", role: "Eyebrows (uppercase)", sample: "DISPLAYS", caps: true },
  ];

  const MONO = [
    { label: "Timer", sample: "01:31", note: "Recording / trim readout" },
    { label: "Duration", sample: "00:48", note: "Packet length" },
    { label: "Dimensions", sample: "1280 × 720", note: "Region W × H chip" },
  ];

  const SPACE = [
    { t: "4", v: "4px", k: "--s1" }, { t: "8", v: "8px", k: "--s2" },
    { t: "12", v: "12px", k: "--s3" }, { t: "16", v: "16px", k: "--s4" },
    { t: "20", v: "20px", k: "--s5" }, { t: "24", v: "24px", k: "--s6" },
    { t: "32", v: "32px", k: "--s8" }, { t: "40", v: "40px", k: "--s10" },
  ];

  const RADII = [
    { name: "sm", v: 6, use: "Chips, dots, small controls" },
    { name: "md", v: 10, use: "Buttons, cards, cells" },
    { name: "lg", v: 14, use: "Sheets, HUD, panels" },
    { name: "pill", v: 999, use: "Selection pills, toggles" },
  ];

  window.SynData = { COLORS, TYPE, MONO, SPACE, RADII };

  // ---------- SHARED LAYOUT / DISPLAY HELPERS ----------
  const Eyebrow = ({ children, accent }) => (
    <div style={{
      fontSize: 10.5, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase",
      color: accent ? "var(--accent-deep)" : "var(--text3)", marginBottom: 10,
    }}>{children}</div>
  );

  const Section = ({ id, eyebrow, title, desc, children, max }) => (
    <section id={id} style={{ scrollMarginTop: 24, padding: "56px 0", borderTop: "1px solid var(--hairline)" }}>
      <div style={{ maxWidth: 720, marginBottom: 36 }}>
        {eyebrow && <Eyebrow accent>{eyebrow}</Eyebrow>}
        <h2 style={{
          margin: 0, fontSize: 30, fontWeight: 700, letterSpacing: "-0.025em",
          color: "var(--text1)", lineHeight: 1.08,
        }}>{title}</h2>
        {desc && <p style={{
          margin: "14px 0 0", fontSize: 15, lineHeight: 1.6, color: "var(--text2)",
          letterSpacing: "-0.01em", maxWidth: max || 620,
        }}>{desc}</p>}
      </div>
      {children}
    </section>
  );

  // A titled display surface. variant: "card" | "canvas" | "desktop" | "plain"
  const Stage = ({ label, children, variant = "card", pad = 28, minH, align = "stretch", style }) => {
    const bg = {
      card: "var(--card)",
      canvas: "var(--canvas)",
      plain: "transparent",
      desktop: "transparent",
    }[variant];
    return (
      <div style={{ ...style }}>
        {label && (
          <div style={{
            fontSize: 11, fontWeight: 600, color: "var(--text3)", marginBottom: 10,
            letterSpacing: "0.02em", fontFamily: "var(--font-mono)",
          }}>{label}</div>
        )}
        <div
          className={variant === "desktop" ? "syn-desktop" : ""}
          style={{
            background: variant === "desktop" ? undefined : bg,
            border: variant === "plain" ? "none" : "1px solid var(--hairline)",
            borderRadius: 16, padding: pad, minHeight: minH,
            display: "flex", flexDirection: "column", justifyContent: "center", alignItems: align,
            position: "relative", overflow: "hidden",
          }}
        >
          {children}
        </div>
      </div>
    );
  };

  const Mono = ({ children, color }) => (
    <span style={{ fontFamily: "var(--font-mono)", fontSize: "0.92em", color: color || "inherit", letterSpacing: "-0.01em" }}>{children}</span>
  );

  // grid of labeled spec cells
  const SpecGrid = ({ cols = 3, children, gap = 1 }) => (
    <div style={{
      display: "grid", gridTemplateColumns: `repeat(${cols}, 1fr)`, gap,
      background: "var(--hairline)", border: "1px solid var(--hairline)",
      borderRadius: 14, overflow: "hidden",
    }}>{children}</div>
  );

  // caption under a stage
  const Caption = ({ children, style }) => (
    <p style={{
      margin: "12px 2px 0", fontSize: 12.5, lineHeight: 1.55, color: "var(--text2)",
      letterSpacing: "-0.005em", ...style,
    }}>{children}</p>
  );

  // small label inside galleries
  const StateLabel = ({ children }) => (
    <div style={{
      fontSize: 11, fontWeight: 600, color: "var(--text3)", marginBottom: 12,
      fontFamily: "var(--font-mono)", letterSpacing: "0.01em",
    }}>{children}</div>
  );

  // a representational desktop "screen content" backdrop for floating panels
  const DesktopBackdrop = ({ children, h = 360, tone = "photo", style, padBottom }) => (
    <div style={{
      position: "relative", height: h, borderRadius: 16, overflow: "hidden",
      border: "1px solid var(--hairline)",
      display: "flex", alignItems: "center", justifyContent: "center",
      paddingBottom: padBottom, ...style,
    }}>
      <div className={`syn-wallpaper syn-wall-${tone}`} style={{ position: "absolute", inset: 0 }} />
      <div style={{ position: "relative", width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center" }}>
        {children}
      </div>
    </div>
  );

  // Responsive auto-fit: scales a fixed-width child down to fit its container
  // (never upscales). Reserves the scaled height so layout stays clean.
  const FitBox = ({ w, children, max = 1 }) => {
    const outer = React.useRef(null), inner = React.useRef(null);
    const [s, setS] = React.useState({ scale: max, h: 0 });
    React.useLayoutEffect(() => {
      const o = outer.current, i = inner.current;
      if (!o || !i) return;
      const measure = () => {
        const scale = Math.min(max, o.clientWidth / w);
        setS({ scale, h: i.offsetHeight * scale });
      };
      measure();
      const ro = new ResizeObserver(measure);
      ro.observe(o);
      return () => ro.disconnect();
    }, [w, max]);
    return (
      <div ref={outer} style={{ width: "100%" }}>
        <div style={{ height: s.h, display: "flex", justifyContent: "center", alignItems: "flex-start" }}>
          <div ref={inner} style={{ width: w, height: "max-content", transform: `scale(${s.scale})`, transformOrigin: "top center" }}>
            {children}
          </div>
        </div>
      </div>
    );
  };

  Object.assign(window, { Eyebrow, Section, Stage, Mono, SpecGrid, Caption, StateLabel, DesktopBackdrop, FitBox });
})();
