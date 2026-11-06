import deepmerge from 'deepmerge'
import { describe, expect, it } from 'vitest'

// Regression tests for the yarn patch on deepmerge 4.3.1
// (.yarn/patches/deepmerge-npm-4.3.1-*.patch, GHSA-gcqx-w48m-w2h4).
describe('patched deepmerge', () => {
  const polluted = () => JSON.parse('{"__proto__": {"polluted": true}, "a": 1}')

  it('does not let a __proto__ key from the target change the result prototype', () => {
    const result: any = deepmerge(polluted(), { b: 2 })
    expect(Object.getPrototypeOf(result)).toBe(Object.prototype)
    expect(result.polluted).toBeUndefined()
    expect(result.a).toBe(1)
    expect(result.b).toBe(2)
  })

  it('does not let a __proto__ key from the source change the result prototype', () => {
    const result: any = deepmerge({ b: 2 }, polluted())
    expect(Object.getPrototypeOf(result)).toBe(Object.prototype)
    expect(result.polluted).toBeUndefined()
    expect(result.a).toBe(1)
  })

  it('does not pollute Object.prototype', () => {
    deepmerge(polluted(), polluted())
    expect(({} as any).polluted).toBeUndefined()
  })

  it('still merges ordinary nested objects and arrays', () => {
    expect(deepmerge({ a: { b: 1 }, l: [1] }, { a: { c: 2 }, l: [2] })).toEqual({
      a: { b: 1, c: 2 },
      l: [1, 2],
    })
  })
})
