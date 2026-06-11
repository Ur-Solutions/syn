import { describe, expect, it } from "vitest"
import { sanitizeProps } from "../src/privacy"
import { DEFAULT_REDACT_KEYS } from "../src/config"

describe("sanitizeProps", () => {
  it("returns nothing in off mode", () => {
    const result = sanitizeProps({ a: 1 }, "off", DEFAULT_REDACT_KEYS)
    expect(result.props).toBeUndefined()
    expect(result.redacted).toBe(false)
  })

  it("keeps safe primitives, drops the rest", () => {
    const result = sanitizeProps(
      {
        flag: true,
        count: 3,
        label: "ok",
        missing: null,
        big: Number.POSITIVE_INFINITY,
        fn: () => {},
        obj: { deep: 1 },
        list: [1, 2],
        children: "skip",
      },
      "safe-primitives",
      DEFAULT_REDACT_KEYS,
    )
    expect(result.props).toEqual({ flag: true, count: 3, label: "ok", missing: null })
  })

  it("redacts by case-insensitive key substring", () => {
    const result = sanitizeProps(
      { userEmail: "a@b.c", AccessToken: "x", planId: "team" },
      "safe-primitives",
      DEFAULT_REDACT_KEYS,
    )
    expect(result.redacted).toBe(true)
    expect(result.props).toEqual({
      userEmail: "[redacted]",
      AccessToken: "[redacted]",
      planId: "team",
    })
  })

  it("truncates long strings", () => {
    const result = sanitizeProps({ text: "x".repeat(100) }, "safe-primitives", [])
    expect((result.props!.text as string).length).toBe(65)
  })
})
