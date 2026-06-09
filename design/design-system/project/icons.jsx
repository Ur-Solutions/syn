/* ============================================================
   SYN — ICON SET
   SF-Symbol-flavored line icons. 24px grid, stroke = currentColor,
   round caps/joins. Kept geometric & minimal on purpose.
   Usage: <Icon name="mic" size={16} sw={1.6} />
   ============================================================ */
(function () {
  const P = {}; // name -> inner SVG markup (function of props if needed)

  // ---- simple stroke icons ----
  P.mic = (
    <>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5.5 11a6.5 6.5 0 0 0 13 0" />
      <path d="M12 17.5V21" />
      <path d="M8.5 21h7" />
    </>
  );
  P.pen = (
    <>
      <path d="M4 20l1.2-4.2L15.5 5.5a2.1 2.1 0 0 1 3 3L8.2 18.8 4 20Z" />
      <path d="M14 7l3 3" />
    </>
  );
  P.line = <path d="M5 19L19 5" />;
  P.rectangle = <rect x="4" y="6.5" width="16" height="11" rx="1.4" />;
  P.ellipse = <ellipse cx="12" cy="12" rx="8.5" ry="6.5" />;
  P.cursor = (
    <>
      <path d="M6 4l12 7-5 1.4-2.2 5.1L6 4Z" />
    </>
  );
  P.trash = (
    <>
      <path d="M5 7h14" />
      <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
      <path d="M6.5 7l.8 11a1.6 1.6 0 0 0 1.6 1.5h6.2a1.6 1.6 0 0 0 1.6-1.5L18.5 7" />
      <path d="M10 11v5M14 11v5" />
    </>
  );
  P.eraser = (
    <>
      <path d="M8.5 19h9" />
      <path d="M4.7 14.3l5-5a1.8 1.8 0 0 1 2.6 0l3.4 3.4a1.8 1.8 0 0 1 0 2.6L13.5 17.5a2 2 0 0 1-2.8 0L4.7 11.6" />
      <path d="M8.5 9.5l5 5" />
    </>
  );
  P.close = <path d="M6 6l12 12M18 6L6 18" />;
  P.pause = (
    <>
      <rect x="7" y="5" width="3.4" height="14" rx="1.2" />
      <rect x="13.6" y="5" width="3.4" height="14" rx="1.2" />
    </>
  );
  P.play = <path d="M7 5.5l11 6.5-11 6.5V5.5Z" />;
  P.stop = <rect x="6.5" y="6.5" width="11" height="11" rx="2.2" />;
  P.check = <path d="M5 12.5l4.2 4.2L19 7" />;
  P.chevronRight = <path d="M9.5 5.5L16 12l-6.5 6.5" />;
  P.chevronDown = <path d="M5.5 9.5L12 16l6.5-6.5" />;
  P.chevronUpDown = <path d="M8 10l4-4 4 4M8 14l4 4 4-4" />;
  P.plus = <path d="M12 5v14M5 12h14" />;
  P.sliders = (
    <>
      <path d="M4 7h10M18 7h2" />
      <circle cx="16" cy="7" r="2.1" />
      <path d="M4 17h2M10 17h10" />
      <circle cx="8" cy="17" r="2.1" />
    </>
  );
  P.gear = (
    <>
      <circle cx="12" cy="12" r="3.1" />
      <path d="M12 2.6v2.4M12 19v2.4M21.4 12H19M5 12H2.6M18.6 5.4l-1.7 1.7M7.1 16.9l-1.7 1.7M18.6 18.6l-1.7-1.7M7.1 7.1L5.4 5.4" />
    </>
  );
  P.folder = (
    <>
      <path d="M3.5 7.5a1.5 1.5 0 0 1 1.5-1.5h3.3a1.5 1.5 0 0 1 1.1.5l1 1.1H19a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 17V7.5Z" />
    </>
  );
  P.archive = (
    <>
      <rect x="4" y="5" width="16" height="4" rx="1.2" />
      <path d="M5.2 9v8.5A1.5 1.5 0 0 0 6.7 19h10.6a1.5 1.5 0 0 0 1.5-1.5V9" />
      <path d="M10 12.5h4" />
    </>
  );
  P.copy = (
    <>
      <rect x="8" y="8" width="11" height="11" rx="2.2" />
      <path d="M5 16V6.2A2.2 2.2 0 0 1 7.2 4H15" />
    </>
  );
  P.doc = (
    <>
      <path d="M6.5 3.5h7L18 8v11.5a1 1 0 0 1-1 1H6.5a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1Z" />
      <path d="M13 3.6V8h4.4" />
      <path d="M8.5 12h7M8.5 15.5h7" />
    </>
  );
  P.clock = (
    <>
      <circle cx="12" cy="12" r="8.2" />
      <path d="M12 7.5V12l3 2" />
    </>
  );
  P.monitor = (
    <>
      <rect x="3" y="4.5" width="18" height="12" rx="2" />
      <path d="M9 20h6M12 16.5V20" />
    </>
  );
  P.monitors = (
    <>
      <rect x="2.5" y="5" width="12.5" height="9" rx="1.8" />
      <path d="M16.5 8.2h3a1.5 1.5 0 0 1 1.5 1.5v6.3a1.5 1.5 0 0 1-1.5 1.5H10a1.5 1.5 0 0 1-1.5-1.5V14" />
    </>
  );
  P.window = (
    <>
      <rect x="3.5" y="5" width="17" height="14" rx="2.2" />
      <path d="M3.5 9h17" />
      <circle cx="6.4" cy="7" r="0.5" />
      <circle cx="8.4" cy="7" r="0.5" />
    </>
  );
  P.windowPick = (
    <>
      <rect x="3.5" y="5" width="17" height="14" rx="2.2" />
      <path d="M3.5 9h17" />
      <path d="M9.5 13.5l5 0M12 11v5" />
    </>
  );
  P.region = (
    <>
      <path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" />
    </>
  );
  P.smartRegion = (
    <>
      <path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" />
      <circle cx="12" cy="12" r="2.1" />
    </>
  );
  P.chrome = (
    <>
      <rect x="3.5" y="5" width="17" height="14" rx="2.2" />
      <path d="M3.5 9h17" />
      <path d="M7 5v4M12 5v4" />
    </>
  );
  P.grip = (
    <>
      <circle cx="9" cy="7" r="0.5" /><circle cx="9" cy="12" r="0.5" /><circle cx="9" cy="17" r="0.5" />
      <circle cx="15" cy="7" r="0.5" /><circle cx="15" cy="12" r="0.5" /><circle cx="15" cy="17" r="0.5" />
    </>
  );
  P.eye = (
    <>
      <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" />
      <circle cx="12" cy="12" r="2.6" />
    </>
  );
  P.eyeOff = (
    <>
      <path d="M4 5l16 14" />
      <path d="M9.5 5.9A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-2.7 3.3" />
      <path d="M6.2 7.7A16.6 16.6 0 0 0 2.5 12S6 18.5 12 18.5a9.2 9.2 0 0 0 3-.5" />
      <path d="M9.9 10.2a2.6 2.6 0 0 0 3.6 3.7" />
    </>
  );
  P.aperture = (
    <>
      <circle cx="12" cy="12" r="8.4" />
      <path d="M12 3.6l3.6 6.2M20 9.6l-7.2 0M18.4 17.4l-3.6-6.2M12 20.4l-3.6-6.2M4 14.4l7.2 0M5.6 6.6l3.6 6.2" />
    </>
  );
  P.scissors = (
    <>
      <circle cx="6.5" cy="6.5" r="2.2" />
      <circle cx="6.5" cy="17.5" r="2.2" />
      <path d="M8.4 7.9L20 17M8.4 16.1L20 7M13 12l-4.6 3.6" />
    </>
  );
  P.returnKey = <path d="M20 6v4.5a2 2 0 0 1-2 2H5M8.5 9L5 12.5 8.5 16" />;
  P.bolt = <path d="M13 2.5L5 13.5h6l-1 8 8-11h-6l1-8Z" />;
  P.sparkle = (
    <>
      <path d="M12 4l1.6 4.4L18 10l-4.4 1.6L12 16l-1.6-4.4L6 10l4.4-1.6L12 4Z" />
      <path d="M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7.7-1.8Z" />
    </>
  );
  P.shield = (
    <>
      <path d="M12 3l7 2.4v5.2c0 4.6-3 8-7 10-4-2-7-5.4-7-10V5.4L12 3Z" />
      <path d="M9 12l2 2 4-4.4" />
    </>
  );
  P.repeat = <path d="M5 8.5A4.5 4.5 0 0 1 9.5 4H18M18 4l-3-3M18 4l-3 3M19 15.5A4.5 4.5 0 0 1 14.5 20H6M6 20l3 3M6 20l3-3" />;
  P.power = (
    <>
      <path d="M12 3v8" />
      <path d="M7 6.5a7 7 0 1 0 10 0" />
    </>
  );
  P.dragMove = <path d="M12 3v18M3 12h18M9 6l3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3" />;
  P.waveform = (
    <>
      <path d="M4 12v0M7 9v6M10 6v12M13 8.5v7M16 10.5v3M19 11.5v1" />
    </>
  );
  P.info = (
    <>
      <circle cx="12" cy="12" r="8.4" />
      <path d="M12 11v5.5" />
      <circle cx="12" cy="7.8" r="0.6" />
    </>
  );
  P.key = (
    <>
      <circle cx="8" cy="8" r="3.6" />
      <path d="M10.6 10.6L20 20M16 16l2.4-2.4M18.5 18.5l2-2" />
    </>
  );
  P.brain = (
    <>
      <path d="M9 5.5A3 3 0 0 0 6 8.5a2.7 2.7 0 0 0-1.5 4.5A2.7 2.7 0 0 0 6 17a3 3 0 0 0 3 2.5V5.5Z" />
      <path d="M15 5.5A3 3 0 0 1 18 8.5a2.7 2.7 0 0 1 1.5 4.5A2.7 2.7 0 0 1 18 17a3 3 0 0 1-3 2.5V5.5Z" />
      <path d="M12 5v14" />
    </>
  );

  function Icon({ name, size = 18, sw = 1.6, fill = false, style, className, ...rest }) {
    const inner = P[name];
    if (!inner) return null;
    const filledNames = { record: true };
    return (
      <svg
        width={size}
        height={size}
        viewBox="0 0 24 24"
        fill={fill || filledNames[name] ? "currentColor" : "none"}
        stroke={fill || filledNames[name] ? "none" : "currentColor"}
        strokeWidth={sw}
        strokeLinecap="round"
        strokeLinejoin="round"
        className={className}
        style={{ display: "block", flex: "none", ...style }}
        aria-hidden="true"
        {...rest}
      >
        {inner}
      </svg>
    );
  }

  // a tiny solid record disc (no stroke)
  function Disc({ size = 8, color = "var(--rec)", style }) {
    return (
      <span
        style={{
          width: size, height: size, borderRadius: "50%",
          background: color, display: "inline-block", flex: "none", ...style,
        }}
      />
    );
  }

  window.Icon = Icon;
  window.Disc = Disc;
  window.ICON_NAMES = Object.keys(P);
})();
