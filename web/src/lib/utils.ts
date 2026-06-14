export function fmtTime(secs: number): string {
  if (!isFinite(secs) || secs < 0) return '0:00';
  const s = Math.floor(secs);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function timeAgo(iso: string): string {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'ahora';
  if (diff < 3600) return `hace ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `hace ${Math.floor(diff / 3600)} h`;
  return `hace ${Math.floor(diff / 86400)} d`;
}

export function slugToTitle(url: string): string {
  const slug = url.split('/').pop() ?? url;
  return slug.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

export function letterGradient(title: string): string {
  const hue = Math.abs([...title].reduce((h, c) => h * 31 + c.charCodeAt(0), 0)) % 360;
  return `linear-gradient(135deg, hsl(${hue},70%,40%), hsl(${(hue + 43) % 360},80%,28%))`;
}
