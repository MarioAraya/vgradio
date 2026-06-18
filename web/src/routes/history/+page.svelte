<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import { player } from '$lib/stores/player';
  import type { HistoryEntry, Track, AlbumSummary } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { timeAgo, fmtTime } from '$lib/utils';

  let entries: HistoryEntry[] = [];
  let loading = true;

  onMount(async () => {
    try { entries = await api.history(100); }
    catch {}
    loading = false;
  });

  function play(e: HistoryEntry) {
    const track: Track = { id: e.trackId, name: e.trackName, index: 0, durationSec: 0,
      sizeBytes: 0, streamUrl: `/tracks/${e.trackId}/stream`, downloadUrl: `/tracks/${e.trackId}/download`, downloaded: false };
    const album: AlbumSummary = { id: e.albumId, title: e.albumTitle, platform: e.platform,
      year: e.year, albumType: '', trackCount: 0, totalDurationSec: 0, coverUrls: e.coverUrl ? [e.coverUrl] : [] };
    player.play(track, album, [track]);
  }
</script>

<div class="page">
  <h1>Recently Played</h1>

  {#if loading}
    <div class="center"><span class="muted">Loading…</span></div>
  {:else if entries.length === 0}
    <div class="center">
      <div class="icon">🕐</div>
      <p class="muted">No history yet</p>
      <p class="hint">Tracks you play will appear here</p>
    </div>
  {:else}
    <div class="list">
      {#each entries as e}
        <div class="entry">
          <button class="cover-btn" on:click={() => play(e)}>
            <CoverImage url={e.coverUrl} title={e.albumTitle} size={44} radius={6} />
          </button>
          <div class="info">
            <button class="track-name" on:click={() => play(e)}>{e.trackName}</button>
            <button class="album-name" on:click={() => goto(`/albums/${e.albumId}`)}>{e.albumTitle}</button>
          </div>
          <div class="meta">
            <span class="platform">{e.platform}{e.platform && e.year ? ' · ' : ''}{e.year || ''}</span>
            <span class="ago">{timeAgo(e.playedAt)}</span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 20px; }
  .center { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; min-height: 300px; }
  .muted { color: var(--text-muted); }
  .icon { font-size: 36px; opacity: 0.4; }
  .hint { font-size: 12px; color: var(--text-muted); }
  .list { display: flex; flex-direction: column; }
  .entry {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px;
    border-radius: var(--r-md);
    transition: background 0.1s;
  }
  .entry:hover { background: rgba(255,255,255,0.04); }
  .cover-btn { flex-shrink: 0; border-radius: 6px; overflow: hidden; }
  .info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .track-name { text-align: left; font-size: 13px; color: var(--text); font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .track-name:hover { color: var(--accent); }
  .album-name { text-align: left; font-size: 12px; color: var(--text-sec); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .album-name:hover { color: var(--accent); }
  .meta { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; flex-shrink: 0; }
  .platform { font-size: 11px; color: var(--text-muted); }
  .ago { font-size: 11px; color: var(--text-muted); }
</style>
