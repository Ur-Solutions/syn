/* ============================================================
   SYN — FOUNDATIONS SECTION
   Color · Typography · Spacing & Radii · Motion
   ============================================================ */
(function () {
  const { Section, Stage, Mono, SpecGrid, Caption, Eyebrow, Icon, Disc } = window;
  const { COLORS, TYPE, MONO, SPACE, RADII } = window.SynData;

  function Swatch({ s }) {
    return (
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{
          height: 56, borderRadius: 10, background: `var(${s.v})`,
          border: "1px solid var(--hairline)",
          boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.03)",
        }} />
        <div style={{ marginTop: 9 }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: "var(--text1)", letterSpacing: "-0.01em" }}>{s.name}</div>
          <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 3 }}>
            <Mono color="var(--text2)">{s.hex}</Mono>
          </div>
          <div style={{ fontSize: 11, color: "var(--text3)", marginTop: 4, lineHeight: 1.35 }}>{s.use}</div>
        </div>
      </div>
    );
  }

  function ColorGroup({ g }) {
    return (
      <div style={{ marginBottom: 30 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 4, flexWrap: "wrap" }}>
          <h3 style={{ margin: 0, fontSize: 16, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.015em" }}>{g.title}</h3>
        </div>
        <p style={{ margin: "0 0 18px", fontSize: 13, color: "var(--text2)", maxWidth: 560, lineHeight: 1.55 }}>{g.note}</p>
        <div style={{
          display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(132px, 1fr))", gap: 18,
        }}>
          {g.swatches.map((s) => <Swatch key={s.name} s={s} />)}
        </div>
      </div>
    );
  }

  // surface-area illustration: "color is a whisper"
  function WhisperBar() {
    return (
      <Stage label="surface area — neutral by default, rose only in small moments" variant="card" pad={0} style={{ marginBottom: 34 }}>
        <div style={{ width: "100%", padding: 24 }}>
          <div style={{
            display: "flex", alignItems: "center", height: 64, borderRadius: 12, overflow: "hidden",
            border: "1px solid var(--hairline)", background: "var(--canvas)", padding: "0 18px", gap: 14,
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
              <span style={{ width: 9, height: 9, borderRadius: "50%", background: "var(--accent)" }} />
              <span style={{ width: 120, height: 9, borderRadius: 999, background: "var(--surface3)" }} />
              <span style={{ width: 64, height: 9, borderRadius: 999, background: "var(--surface3)" }} />
            </div>
            <span style={{ width: 88, height: 26, borderRadius: 7, background: "var(--accent-tint)", border: "1px solid var(--accent-ring)" }} />
            <span style={{ width: 70, height: 26, borderRadius: 7, background: "var(--card)", border: "1px solid var(--hairline-strong)" }} />
          </div>
          <div style={{ display: "flex", gap: 18, marginTop: 14, fontSize: 11.5, color: "var(--text3)" }}>
            <span style={{ display: "flex", alignItems: "center", gap: 6 }}><span style={{ width: 9, height: 9, borderRadius: "50%", background: "var(--accent)" }} /> ≈ 2% of pixels are rose</span>
            <span style={{ display: "flex", alignItems: "center", gap: 6 }}><span style={{ width: 9, height: 9, borderRadius: 2, background: "var(--surface3)" }} /> everything else is warm-neutral</span>
          </div>
        </div>
      </Stage>
    );
  }

  function ColorSection() {
    return (
      <Section id="color" eyebrow="Foundations" title="Color is a whisper"
        desc="The interface is warm-neutral greyscale. A single rose-coral accent exists, but it only ever appears at small surface area — a live dot, an active tool, one tinted action per view. If in doubt, make it neutral.">
        <WhisperBar />
        <ColorGroup g={COLORS.neutral} />
        <ColorGroup g={COLORS.accent} />
        <ColorGroup g={COLORS.semantic} />
        <Caption style={{ maxWidth: 640 }}>
          Every token is a dynamic light/dark color set — no hard-coded hex in real logic. The annotation-ink token is rose
          with a white contrast halo so strokes stay legible on any screen content. See the dark-mode check at the end.
        </Caption>
      </Section>
    );
  }

  function TypeSection() {
    return (
      <Section id="type" eyebrow="Foundations" title="Typography"
        desc="SF Pro across the display + text range, mapped to macOS text styles for Dynamic Type. SF Mono carries timers, durations and dimension readouts. One restrained wordmark.">
        {/* wordmark */}
        <Stage label="wordmark" variant="card" align="flex-start" style={{ marginBottom: 22 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <span style={{ display: "inline-flex", color: "var(--accent)" }}><Icon name="aperture" size={30} sw={1.5} /></span>
            <span style={{ fontSize: 30, fontWeight: 700, letterSpacing: "-0.03em", color: "var(--text1)" }}>Syn</span>
            <span style={{
              fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--text3)", border: "1px solid var(--hairline)",
              borderRadius: 6, padding: "2px 7px", marginLeft: 2,
            }}>v0.1.0</span>
          </div>
        </Stage>

        {/* scale */}
        <div style={{ border: "1px solid var(--hairline)", borderRadius: 14, overflow: "hidden", background: "var(--card)" }}>
          {TYPE.map((t, i) => (
            <div key={t.name} style={{
              display: "grid", gridTemplateColumns: "180px 1fr", gap: 20, alignItems: "baseline",
              padding: "16px 20px", borderTop: i ? "1px solid var(--hairline)" : "none",
            }}>
              <div>
                <div style={{ fontSize: 13, fontWeight: 600, color: "var(--text1)" }}>{t.name}</div>
                <div style={{ fontSize: 11, color: "var(--text3)", marginTop: 3 }}>
                  <Mono>{t.px}px · {t.w}</Mono>
                </div>
                <div style={{ fontSize: 11, color: "var(--text3)", marginTop: 3, lineHeight: 1.4 }}>{t.role}</div>
              </div>
              <div style={{
                fontSize: t.px, fontWeight: t.w, letterSpacing: t.ls, color: "var(--text1)",
                textTransform: t.caps ? "uppercase" : "none", lineHeight: 1.2,
                whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
              }}>{t.sample}</div>
            </div>
          ))}
        </div>

        {/* mono uses */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginTop: 18 }}>
          {MONO.map((m) => (
            <div key={m.label} style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 12, padding: "16px 18px" }}>
              <div style={{ fontSize: 11, fontWeight: 600, color: "var(--text3)", textTransform: "uppercase", letterSpacing: "0.08em" }}>{m.label}</div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 22, fontWeight: 500, color: "var(--text1)", margin: "8px 0 6px", letterSpacing: "-0.01em" }}>{m.sample}</div>
              <div style={{ fontSize: 11.5, color: "var(--text2)" }}>{m.note}</div>
            </div>
          ))}
        </div>
      </Section>
    );
  }

  function SpacingSection() {
    return (
      <Section id="spacing" eyebrow="Foundations" title="Spacing, radii & elevation"
        desc="A 4 / 8pt grid with generous whitespace. Elevation is mostly hairline borders — soft, low-opacity shadows appear only where a surface truly floats.">
        <div style={{ display: "grid", gridTemplateColumns: "1.2fr 1fr", gap: 22, alignItems: "start" }}>
          {/* spacing */}
          <Stage label="spacing scale" variant="card" align="flex-start">
            <div style={{ display: "flex", flexDirection: "column", gap: 12, width: "100%" }}>
              {SPACE.map((s) => (
                <div key={s.t} style={{ display: "flex", alignItems: "center", gap: 14 }}>
                  <span style={{ width: 34, fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--text2)", textAlign: "right" }}>{s.t}</span>
                  <span style={{ height: 14, width: s.v, borderRadius: 4, background: "var(--accent-tint)", border: "1px solid var(--accent-ring)" }} />
                  <span style={{ fontSize: 11, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>{s.k}</span>
                </div>
              ))}
            </div>
          </Stage>

          <div style={{ display: "flex", flexDirection: "column", gap: 22 }}>
            {/* radii */}
            <Stage label="corner radii" variant="card" align="flex-start">
              <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
                {RADII.map((r) => (
                  <div key={r.name} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
                    <div style={{
                      width: 58, height: 58, background: "var(--surface2)", border: "1px solid var(--hairline-strong)",
                      borderRadius: r.v, borderBottom: "none", borderRight: "none",
                      WebkitMaskImage: "linear-gradient(135deg, #000 40%, transparent 60%)",
                    }} />
                    <div style={{ fontSize: 11.5, fontWeight: 600, color: "var(--text1)" }}>{r.name}</div>
                    <div style={{ fontFamily: "var(--font-mono)", fontSize: 10.5, color: "var(--text3)" }}>{r.name === "pill" ? "999" : r.v}</div>
                  </div>
                ))}
              </div>
            </Stage>

            {/* elevation */}
            <Stage label="elevation — hairline first, shadow only when floating" variant="canvas" align="flex-start">
              <div style={{ display: "flex", gap: 16 }}>
                {[
                  { l: "Hairline", s: "none", b: "1px solid var(--hairline)" },
                  { l: "Card", s: "var(--shadow-1)", b: "1px solid var(--hairline)" },
                  { l: "Float / HUD", s: "var(--shadow-float)", b: "1px solid var(--material-border)" },
                ].map((e) => (
                  <div key={e.l} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 9 }}>
                    <div style={{ width: 74, height: 50, borderRadius: 12, background: "var(--card)", boxShadow: e.s, border: e.b }} />
                    <div style={{ fontSize: 11, color: "var(--text2)", fontWeight: 500 }}>{e.l}</div>
                  </div>
                ))}
              </div>
            </Stage>
          </div>
        </div>
      </Section>
    );
  }

  function MotionSection() {
    const [popKey, setPop] = React.useState(0);
    return (
      <Section id="motion" eyebrow="Foundations" title="Motion"
        desc="Gentle springs, subtle hover and press, an indeterminate processing motion, and exactly one calm completion beat. Reduce Motion & Reduce Transparency are honored throughout.">
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 16 }}>
          <Stage label="indeterminate — processing" variant="card" minH={150}>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
              <span style={{ width: 26, height: 26, borderRadius: "50%", border: "2.5px solid var(--accent-tint)", borderTopColor: "var(--accent)", animation: "spin 0.9s linear infinite" }} />
              <span style={{ fontSize: 12, color: "var(--text2)" }}>summarizing…</span>
            </div>
          </Stage>

          <Stage label="one calm completion beat" variant="card" minH={150}>
            <div onClick={() => setPop((k) => k + 1)} style={{ cursor: "pointer", display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
              <span key={popKey} style={{ position: "relative", display: "inline-flex" }}>
                <span style={{
                  position: "absolute", inset: -8, borderRadius: "50%", border: "2px solid var(--accent-ring)",
                  animation: "completion-ring 0.7s ease-out", opacity: 0,
                }} />
                <span style={{
                  width: 38, height: 38, borderRadius: "50%", background: "var(--accent-tint)",
                  border: "1px solid var(--accent-ring)", color: "var(--accent-deep)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                  animation: "completion-pop 0.6s var(--spring)",
                }}><Icon name="check" size={20} sw={2.2} /></span>
              </span>
              <span style={{ fontSize: 12, color: "var(--text2)" }}>Packet ready · <span style={{ color: "var(--text3)" }}>tap to replay</span></span>
            </div>
          </Stage>

          <Stage label="reduce motion / transparency" variant="card" minH={150} align="flex-start">
            <div style={{ display: "flex", flexDirection: "column", gap: 12, fontSize: 12.5, color: "var(--text2)", lineHeight: 1.5 }}>
              <div style={{ display: "flex", gap: 9 }}><span style={{ color: "var(--success)", marginTop: 1 }}><Icon name="check" size={14} sw={2} /></span> Animations collapse to instant state changes.</div>
              <div style={{ display: "flex", gap: 9 }}><span style={{ color: "var(--success)", marginTop: 1 }}><Icon name="check" size={14} sw={2} /></span> Vibrancy falls back to solid surfaces.</div>
              <div style={{ display: "flex", gap: 9 }}><span style={{ color: "var(--success)", marginTop: 1 }}><Icon name="check" size={14} sw={2} /></span> No looping decorative motion on content.</div>
            </div>
          </Stage>
        </div>
      </Section>
    );
  }

  function Foundations() {
    return (
      <>
        <ColorSection />
        <TypeSection />
        <SpacingSection />
        <MotionSection />
      </>
    );
  }

  window.Foundations = Foundations;
})();
