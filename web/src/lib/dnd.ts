// Drag payload for "drag album/track onto a playlist" in the sidebar.
// Carries either explicit track IDs (single track drag) or an albumId
// (whole-album drag, resolved to track IDs by the drop target).
export type DragPayload = { trackIds: string[] } | { albumId: string };

const MIME = 'application/x-vgradio-items';

export function setDragPayload(e: DragEvent, payload: DragPayload) {
  if (!e.dataTransfer) return;
  e.dataTransfer.setData(MIME, JSON.stringify(payload));
  e.dataTransfer.effectAllowed = 'copy';
}

export function hasDragPayload(e: DragEvent): boolean {
  return !!e.dataTransfer?.types.includes(MIME);
}

export function getDragPayload(e: DragEvent): DragPayload | null {
  const raw = e.dataTransfer?.getData(MIME);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}
