/* ============================================================
   SYN — PRIMITIVE COMPONENTS
   The real app UI vocabulary, reused across gallery + screens.
   Restraint is the rule: neutral by default, rose only in small moments.
   ============================================================ */
(function () {
  const { Icon, Disc } = window;

  /* ---------------- Button ----------------
     primary     = subtle rose-tint (hairline rose border + deep-rose text)
     secondary   = neutral light pill
     tertiary    = plain text
     destructive = neutral button with red glyph                         */
  function Button({ variant = "secondary", size = "md", icon, iconRight, children, disabled, full, state, style, ...rest }) {
    const pad = size === "sm" ? "5px 11px" : size === "lg" ? "9px 18px" : "7px 14px";
    const fs = size === "sm" ? 12 : size === "lg" ? 14 : 13;
    const base = {
      display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 7,
      font: "inherit", fontSize: fs, fontWeight: 550, letterSpacing: "-0.01em",
      padding: pad, borderRadius: 9, cursor: disabled ? "default" : "pointer",
      border: "1px solid transparent", whiteSpace: "nowrap",
      transition: "background .15s, border-color .15s, color .15s, transform .08s",
      width: full ? "100%" : undefined, opacity: disabled ? 0.45 : 1, userSelect: "none",
    };
    const looks = {
      primary: {
        background: state === "press" ? "var(--accent-tint)" : "var(--accent-tint)",
        borderColor: "var(--accent-ring)",
        color: "var(--accent-deep)",
        boxShadow: state === "hover" ? "0 0 0 3px var(--accent-tint-2)" : "none",
      },
      secondary: {
        background: state === "hover" ? "var(--selected)" : "var(--card)",
        borderColor: "var(--hairline-strong)", color: "var(--text1)",
        boxShadow: "var(--shadow-1)",
      },
      tertiary: {
        background: state === "hover" ? "var(--selected)" : "transparent",
        borderColor: "transparent", color: "var(--text1)", boxShadow: "none",
      },
      destructive: {
        background: state === "hover" ? "var(--selected)" : "var(--card)",
        borderColor: "var(--hairline-strong)", color: "var(--destructive)",
        boxShadow: "var(--shadow-1)",
      },
    };
    return (
      <button disabled={disabled} style={{ ...base, ...looks[variant], ...style }} {...rest}>
        {icon && <Icon name={icon} size={fs + 2} sw={1.7} />}
        {children}
        {iconRight && <Icon name={iconRight} size={fs + 1} sw={1.7} />}
      </button>
    );
  }

  /* ---------------- IconButton ----------------
     neutral square; "active" = faint rose tint + rose icon                */
  function IconButton({ icon, active, disabled, size = 30, danger, state, label, sw = 1.7, style, ...rest }) {
    return (
      <button
        aria-label={label}
        disabled={disabled}
        style={{
          width: size, height: size, borderRadius: 8, display: "inline-flex",
          alignItems: "center", justifyContent: "center", cursor: disabled ? "default" : "pointer",
          border: "1px solid", borderColor: active ? "var(--accent-ring)" : "transparent",
          background: active ? "var(--accent-tint)" : state === "hover" ? "var(--selected)" : "transparent",
          color: danger ? "var(--destructive)" : active ? "var(--accent-deep)" : "var(--text2)",
          opacity: disabled ? 0.4 : 1, transition: "background .15s, color .15s, border-color .15s",
          ...style,
        }}
        {...rest}
      >
        <Icon name={icon} size={size * 0.56} sw={sw} />
      </button>
    );
  }

  /* ---------------- ToolButton (canvas) ---------------- */
  function ToolButton({ icon, active, chord, label, state, ...rest }) {
    return (
      <button
        aria-label={label}
        title={label}
        style={{
          width: 34, height: 34, borderRadius: 8, display: "inline-flex",
          alignItems: "center", justifyContent: "center", cursor: "pointer",
          border: "1px solid", borderColor: active ? "var(--accent-ring)" : "transparent",
          background: active ? "var(--accent-tint)" : state === "hover" ? "var(--selected)" : "transparent",
          color: active ? "var(--accent-deep)" : "var(--text1)",
          transition: "background .15s, color .15s, border-color .15s",
        }}
        {...rest}
      >
        <Icon name={icon} size={18} sw={1.7} />
      </button>
    );
  }

  /* ---------------- KeyCap + KeyChord ----------------
     neutral caps; distinguishes Left vs Right Shift via a tiny side tag    */
  function KeyCap({ children, side, wide }) {
    return (
      <span style={{
        display: "inline-flex", alignItems: "center", gap: 3,
        minWidth: wide ? "auto" : 21, height: 21, padding: wide ? "0 8px" : "0 5px",
        borderRadius: 6, background: "var(--keycap-bg)",
        border: "1px solid var(--keycap-edge)",
        boxShadow: "0 1px 0 var(--keycap-shadow), inset 0 1px 0 rgba(255,255,255,0.55)",
        fontFamily: "var(--font-ui)", fontSize: 11.5, fontWeight: 600, lineHeight: 1,
        color: "var(--keycap-text)", letterSpacing: 0,
      }}>
        {side && <span style={{
          fontSize: 8.5, fontWeight: 700, color: "var(--text3)", letterSpacing: "0.02em",
          transform: "translateY(0.5px)",
        }}>{side}</span>}
        {children}
      </span>
    );
  }

  function KeyChord({ keys }) {
    return (
      <span style={{ display: "inline-flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
        {keys.map((k, i) => (
          <React.Fragment key={i}>
            {i > 0 && <span style={{ color: "var(--text3)", fontSize: 11, fontWeight: 500 }}>+</span>}
            <KeyCap side={k.side} wide={k.wide}>{k.k}</KeyCap>
          </React.Fragment>
        ))}
      </span>
    );
  }
  // helpers for common chords
  const SHIFT_L = { k: "⇧", side: "L" };
  const SHIFT_R = { k: "⇧", side: "R" };

  /* ---------------- StatusDot / StatusBadge ---------------- */
  const STATE_COLOR = {
    recording: "var(--rec)", live: "var(--rec)", success: "var(--success)",
    processing: "var(--processing)", info: "var(--processing)",
    warning: "var(--warning)", paused: "var(--warning)", error: "var(--destructive)",
    idle: "var(--text3)",
  };
  function StatusDot({ state = "idle", pulse, size = 8 }) {
    return (
      <span style={{ position: "relative", width: size, height: size, display: "inline-block", flex: "none" }}>
        <span style={{
          position: "absolute", inset: 0, borderRadius: "50%", background: STATE_COLOR[state],
          animation: pulse ? "pulse-rec 1.6s ease-in-out infinite" : "none",
        }} />
      </span>
    );
  }
  function StatusBadge({ state = "idle", children, pulse, glyph }) {
    return (
      <span style={{
        display: "inline-flex", alignItems: "center", gap: 7, padding: "3px 9px 3px 8px",
        borderRadius: 999, background: "var(--surface2)", border: "1px solid var(--hairline)",
        fontSize: 11.5, fontWeight: 550, color: "var(--text2)", letterSpacing: "-0.005em",
      }}>
        {glyph ? <span style={{ color: STATE_COLOR[state], display: "inline-flex" }}><Icon name={glyph} size={13} sw={1.8} /></span>
          : <StatusDot state={state} pulse={pulse} />}
        {children}
      </span>
    );
  }

  /* ---------------- Card ---------------- */
  function Card({ children, pad = 18, float, style, hover, ...rest }) {
    return (
      <div style={{
        background: "var(--card)", border: "1px solid var(--hairline)", borderRadius: 14,
        boxShadow: float ? "var(--shadow-2)" : "var(--shadow-1)", padding: pad,
        transition: "box-shadow .2s, border-color .2s", ...style,
      }} {...rest}>{children}</div>
    );
  }

  /* ---------------- Packet ListCell (hero) ---------------- */
  function ListCell({ title, status = "success", time, dur, selected, tint, glyph = "doc", style, ...rest }) {
    const statusLabel = { success: "Succeeded", processing: "Processing", warning: "Needs attention", error: "Failed" }[status];
    return (
      <div
        style={{
          display: "flex", alignItems: "center", gap: 12, padding: "9px 11px", borderRadius: 9,
          cursor: "pointer",
          background: selected ? "var(--cell-selected)" : "transparent",
          border: "1px solid", borderColor: "transparent",
          transition: "background .15s", ...style,
        }}
        {...rest}
      >
        <span style={{
          width: 30, height: 30, borderRadius: 8, flex: "none", display: "flex",
          alignItems: "center", justifyContent: "center", background: "var(--surface2)",
          border: "1px solid var(--hairline)", color: "var(--text2)",
        }}><Icon name={glyph} size={16} sw={1.6} /></span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{
            display: "block", fontSize: 13, fontWeight: 600, color: "var(--text1)",
            letterSpacing: "-0.01em", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
          }}>{title}</span>
          <span style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 2 }}>
            <StatusDot state={status} pulse={status === "processing"} size={6} />
            <span style={{ fontSize: 11, color: "var(--text2)" }}>{statusLabel}</span>
            <span style={{ fontSize: 11, color: "var(--text3)" }}>· {time}</span>
          </span>
        </span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11.5, color: "var(--text3)", flex: "none" }}>{dur}</span>
      </div>
    );
  }

  /* ---------------- MicLevelMeter (continuous) ---------------- */
  function MicMeter({ bars = 16, w = 3, gap = 2, h = 18, live = true, level }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap, height: h }}>
        {Array.from({ length: bars }).map((_, i) => {
          const seed = (Math.sin(i * 1.7) + 1) / 2;
          const staticScale = level != null ? Math.max(0.18, Math.min(1, level * (0.5 + seed))) : 0.4;
          return (
            <span key={i} style={{
              width: w, height: h, borderRadius: 999, background: "var(--text2)", opacity: 0.55,
              transformOrigin: "center",
              transform: live ? undefined : `scaleY(${staticScale})`,
              animation: live ? `meter-live 0.9s ease-in-out ${(i % 6) * 0.08}s infinite alternate` : "none",
              "--peak": (0.35 + seed * 0.6).toFixed(2),
            }} />
          );
        })}
      </div>
    );
  }

  /* ---------------- Switch / Toggle ---------------- */
  function Switch({ on, tint, disabled, onClick }) {
    return (
      <button
        role="switch" aria-checked={on} disabled={disabled} onClick={onClick}
        style={{
          width: 38, height: 22, borderRadius: 999, border: "1px solid",
          padding: 2, cursor: disabled ? "default" : "pointer", flex: "none",
          background: on ? (tint ? "var(--accent-tint)" : "var(--success)") : "var(--surface3)",
          borderColor: on ? (tint ? "var(--accent-ring)" : "transparent") : "var(--hairline-strong)",
          display: "flex", justifyContent: on ? "flex-end" : "flex-start",
          transition: "background .18s, border-color .18s, justify-content .18s", opacity: disabled ? 0.5 : 1,
        }}
      >
        <span style={{
          width: 16, height: 16, borderRadius: "50%",
          background: on && tint ? "var(--accent)" : "#fff",
          boxShadow: "0 1px 2px rgba(0,0,0,0.25)", transition: "background .18s",
        }} />
      </button>
    );
  }

  /* ---------------- ProgressSteps ---------------- */
  function ProgressSteps({ steps, active = 0 }) {
    return (
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        {steps.map((s, i) => {
          const done = i < active, cur = i === active;
          return (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, padding: "6px 2px" }}>
              <span style={{
                width: 18, height: 18, borderRadius: "50%", flex: "none", display: "flex",
                alignItems: "center", justifyContent: "center",
                background: done ? "var(--accent-tint)" : "transparent",
                border: "1px solid", borderColor: done ? "var(--accent-ring)" : cur ? "var(--accent-ring)" : "var(--hairline-strong)",
                color: "var(--accent-deep)",
              }}>
                {done ? <Icon name="check" size={11} sw={2} />
                  : cur ? <span style={{ width: 8, height: 8, borderRadius: "50%", border: "1.5px solid var(--accent)", borderTopColor: "transparent", animation: "spin .8s linear infinite" }} />
                  : <span style={{ width: 4, height: 4, borderRadius: "50%", background: "var(--text3)" }} />}
              </span>
              <span style={{
                fontSize: 12.5, fontWeight: cur ? 600 : 500,
                color: done || cur ? "var(--text1)" : "var(--text3)",
              }}>{s}</span>
              {cur && <span style={{ fontSize: 11, color: "var(--text3)", marginLeft: "auto", fontFamily: "var(--font-mono)" }}>…</span>}
            </div>
          );
        })}
      </div>
    );
  }

  /* ---------------- SecureKeyField ---------------- */
  function SecureKeyField({ value = "sk-ant-api03-••••••••••••7Qk2", revealed: r0, ok = true }) {
    const [revealed, setReveal] = React.useState(!!r0);
    return (
      <div style={{
        display: "flex", alignItems: "center", gap: 8, padding: "0 4px 0 11px", height: 32,
        background: "var(--card)", border: "1px solid var(--hairline-strong)", borderRadius: 8,
      }}>
        <StatusDot state={ok ? "success" : "warning"} size={7} />
        <input
          readOnly value={revealed ? "sk-ant-api03-7f3c9a1be4d27Qk2" : value}
          style={{
            flex: 1, border: "none", outline: "none", background: "transparent",
            fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--text1)", letterSpacing: "-0.01em",
          }}
        />
        <IconButton icon={revealed ? "eyeOff" : "eye"} size={26} label="Reveal key"
          onClick={() => setReveal((v) => !v)} />
      </div>
    );
  }

  /* ---------------- Select (model / profile picker) ---------------- */
  function Select({ value, hint }) {
    return (
      <div style={{
        display: "flex", alignItems: "center", gap: 8, padding: "0 8px 0 11px", height: 32,
        background: "var(--card)", border: "1px solid var(--hairline-strong)", borderRadius: 8,
        cursor: "pointer", minWidth: 0,
      }}>
        <span style={{ flex: 1, fontSize: 12.5, color: "var(--text1)", fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{value}</span>
        {hint && <span style={{ fontSize: 11, color: "var(--text3)", fontFamily: "var(--font-mono)" }}>{hint}</span>}
        <span style={{ color: "var(--text3)" }}><Icon name="chevronUpDown" size={14} sw={1.7} /></span>
      </div>
    );
  }

  /* ---------------- TrafficLights (window chrome) ---------------- */
  function TrafficLights() {
    return (
      <div style={{ display: "flex", gap: 8 }}>
        {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
          <span key={c} style={{ width: 12, height: 12, borderRadius: "50%", background: c, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.12)" }} />
        ))}
      </div>
    );
  }

  /* ---------------- Divider ---------------- */
  const VDivider = ({ h = 22, m = 4 }) => (
    <span style={{ width: 1, height: h, background: "var(--hairline)", margin: `0 ${m}px`, flex: "none" }} />
  );

  Object.assign(window, {
    Button, IconButton, ToolButton, KeyCap, KeyChord, SHIFT_L, SHIFT_R,
    StatusDot, StatusBadge, STATE_COLOR, Card, ListCell, MicMeter, Switch,
    ProgressSteps, SecureKeyField, Select, TrafficLights, VDivider,
  });
})();
