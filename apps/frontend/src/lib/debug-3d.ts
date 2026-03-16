export const DEBUG_3D_STORAGE_KEY = "box-debug-3d";

export function is3DDebugEnabled() {
  if (typeof window === "undefined") return false;
  return window.localStorage.getItem(DEBUG_3D_STORAGE_KEY) === "1";
}

export function log3DDebug(label: string, payload?: unknown) {
  if (!is3DDebugEnabled()) return;
  if (payload === undefined) {
    console.debug(`[3D] ${label}`);
    return;
  }
  console.debug(`[3D] ${label}`, payload);
}
