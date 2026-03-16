declare module 'bun:test' {
  export function describe(label: string, fn: () => void): void
  export function test(label: string, fn: () => void | Promise<void>): void
  export function expect<T>(value: T): {
    toBe(expected: unknown): void
    toBeCloseTo(expected: number, precision?: number): void
    toEqual(expected: unknown): void
    toContain(expected: unknown): void
    toHaveLength(expected: number): void
    toBeNull(): void
    not: {
      toBe(expected: unknown): void
      toBeNull(): void
    }
  }
}
