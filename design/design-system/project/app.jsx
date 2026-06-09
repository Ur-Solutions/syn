/* ============================================================
   SYN — SPEC-SHEET SHELL
   Left nav (scroll-spy) + intro + mounts all sections.
   ============================================================ */
(function () {
  const { Icon, KeyChord, SHIFT_L, SHIFT_R, Foundations, Gallery, ScreensOne, ScreensTwo, Mono } = window;

  const NAV = [
    { group: "Foundations", items: [["color", "Color"], ["type", "Typography"], ["spacing", "Spacing & radii"], ["motion", "Motion"]] },
    { group: "Components", items: [["buttons", "Gallery"]] },
    { group: "Screens", items: [["menubar", "Menu bar"], ["picker", "Capture picker"], ["hud", "Recording HUD"], ["canvas", "Canvas Mode"], ["overlay", "Region overlay"], ["overview", "Overview window"], ["settings", "Settings"]] },
    { group: "Brand", items: [["icon", "App icon"], ["dark", "Dark mode"]] },
  ];
  const ALL_IDS = NAV.flatMap((g) => g.items.map((i) => i[0]));

  function useScrollSpy(scrollerRef) {
    const [active, setActive] = React.useState("top");
    React.useEffect(() => {
      const el = scrollerRef.current;
      if (!el) return;
      const onScroll = () => {
        const top = el.scrollTop + 120;
        let cur = "top";
        for (const id of ALL_IDS) {
          const s = document.getElementById(id);
          if (s && s.offsetTop <= top) cur = id;
        }
        setActive(cur);
      };
      el.addEventListener("scroll", onScroll, { passive: true });
      onScroll();
      return () => el.removeEventListener("scroll", onScroll);
    }, []);
    return active;
  }

  function Sidebar({ active, onGo }) {
    return (
      <nav style={{
        width: 248, flex: "none", height: "100vh", position: "sticky", top: 0,
        borderRight: "1px solid var(--hairline)", background: "var(--sidebar)",
        display: "flex", flexDirection: "column", overflow: "auto",
      }} className="thin-scroll">
        {/* brand */}
        <div onClick={() => onGo("top")} style={{ display: "flex", alignItems: "center", gap: 11, padding: "22px 22px 18px", cursor: "pointer" }}>
          <span style={{ display: "inline-flex", color: "var(--accent)" }}><Icon name="aperture" size={22} sw={1.5} /></span>
          <span style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-0.03em", color: "var(--text1)" }}>Syn</span>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--text3)", border: "1px solid var(--hairline)", borderRadius: 5, padding: "1px 5px", marginLeft: 2 }}>v0.1.0</span>
        </div>
        <div style={{ padding: "0 12px 28px", flex: 1 }}>
          {NAV.map((g) => (
            <div key={g.group} style={{ marginBottom: 16 }}>
              <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text3)", padding: "0 10px 7px" }}>{g.group}</div>
              {g.items.map(([id, label]) => {
                const on = active === id;
                return (
                  <button key={id} onClick={() => onGo(id)} style={{
                    display: "flex", alignItems: "center", gap: 9, width: "100%", textAlign: "left",
                    padding: "6px 10px", borderRadius: 7, border: "none", cursor: "pointer",
                    background: on ? "var(--selected)" : "transparent", marginBottom: 1,
                    font: "inherit", fontSize: 12.5, fontWeight: on ? 600 : 500,
                    color: on ? "var(--text1)" : "var(--text2)", transition: "background .15s",
                  }}>
                    <span style={{ width: 5, height: 5, borderRadius: "50%", background: on ? "var(--accent)" : "transparent", flex: "none" }} />
                    {label}
                  </button>
                );
              })}
            </div>
          ))}
        </div>
        <div style={{ padding: "14px 22px", borderTop: "1px solid var(--hairline)", fontSize: 10.5, color: "var(--text3)", lineHeight: 1.5 }}>
          A living spec for a calm,<br />menu-bar-only macOS app.
        </div>
      </nav>
    );
  }

  function Intro() {
    const principles = [
      { ic: "shield", t: "Neutral by default", d: "Warm greyscale, hairline borders, almost no shadow. Color is a whisper." },
      { ic: "bolt", t: "Evidence-first", d: "Precise, calm, engineered-not-decorative. Low ceremony, keyboard-driven." },
      { ic: "sparkle", t: "The packet is the product", d: "Narrate once, paste once. agent-prompt.md is the hero artifact." },
    ];
    return (
      <section id="top" style={{ paddingTop: 16 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--accent-deep)", marginBottom: 14 }}>Design System · macOS · v0.1.0</div>
        <h1 style={{ margin: 0, fontSize: 46, fontWeight: 700, letterSpacing: "-0.035em", lineHeight: 1.04, color: "var(--text1)", maxWidth: 720 }}>
          Point at it, draw on it,<br />talk through it.
        </h1>
        <p style={{ margin: "20px 0 0", fontSize: 16.5, lineHeight: 1.6, color: "var(--text2)", maxWidth: 600, letterSpacing: "-0.01em" }}>
          Syn is a menu-bar-only utility for builders working alongside AI coding agents. Hit a hotkey, narrate while you demo, draw on the screen, then stop — Syn transcribes, summarizes, and packages a versioned <Mono>Syn Packet</Mono> to your clipboard. The recording is the input; the packet is the product.
        </p>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 22 }}>
          <span style={{ fontSize: 12.5, color: "var(--text3)" }}>Hit</span>
          <KeyChord keys={[SHIFT_L, SHIFT_R, { k: "R" }]} />
          <span style={{ fontSize: 12.5, color: "var(--text3)" }}>to begin.</span>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginTop: 38 }}>
          {principles.map((p) => (
            <div key={p.t} style={{ background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 14, padding: 18, boxShadow: "var(--shadow-1)" }}>
              <span style={{ display: "inline-flex", color: "var(--text2)", marginBottom: 12 }}><Icon name={p.ic} size={20} sw={1.6} /></span>
              <div style={{ fontSize: 14, fontWeight: 650, color: "var(--text1)", letterSpacing: "-0.01em" }}>{p.t}</div>
              <div style={{ fontSize: 12.5, color: "var(--text2)", marginTop: 6, lineHeight: 1.5 }}>{p.d}</div>
            </div>
          ))}
        </div>
      </section>
    );
  }

  function App() {
    const scrollerRef = React.useRef(null);
    const active = useScrollSpy(scrollerRef);
    const go = (id) => {
      const s = document.getElementById(id);
      const el = scrollerRef.current;
      if (s && el) el.scrollTo({ top: id === "top" ? 0 : s.offsetTop - 28, behavior: "smooth" });
    };
    return (
      <div className="theme-light app-root" style={{ display: "flex", alignItems: "flex-start" }}>
        <Sidebar active={active} onGo={go} />
        <main ref={scrollerRef} className="thin-scroll" style={{ flex: 1, height: "100vh", overflow: "auto" }}>
          <div style={{ maxWidth: 920, margin: "0 auto", padding: "46px 56px 120px", minWidth: 0 }}>
            <Intro />
            <Foundations />
            <Gallery />
            <ScreensOne />
            <ScreensTwo />
            <footer style={{ marginTop: 64, paddingTop: 24, borderTop: "1px solid var(--hairline)", fontSize: 12, color: "var(--text3)", display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 10 }}>
              <span>Syn — design system spec · v0.1.0</span>
              <span style={{ fontFamily: "var(--font-mono)" }}>Light is the showcase · every token is a dynamic set</span>
            </footer>
          </div>
        </main>
      </div>
    );
  }

  ReactDOM.createRoot(document.getElementById("root")).render(<App />);
})();
