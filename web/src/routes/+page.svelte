<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { player } from '$lib/stores/player';

  $: currentAlbumId = $player.currentAlbum?.id ?? null;

  let albums: AlbumSummary[] = [];
  let loading = true;
  let error = '';
  let playingId: string | null = null;
  let playCtrl: AbortController | null = null;

  onMount(async () => {
    try { albums = await api.albums(); }
    catch (e) { error = e instanceof Error ? e.message : String(e); }
    finally { loading = false; }
  });

  async function playAlbum(e: MouseEvent, summary: AlbumSummary) {
    e.stopPropagation();
    playCtrl?.abort();
    playCtrl = new AbortController();
    playingId = summary.id;
    try {
      const album = await api.album(summary.id, playCtrl.signal);
      if (!album.tracks.length) return;
      player.play(album.tracks[0], summary, album.tracks, album.covers);
    } catch (err) {
      if ((err as Error).name === 'AbortError') return;
    } finally {
      playingId = null;
      playCtrl = null;
    }
  }
</script>

<div class="page">
  <div class="header">
    <h1>Library</h1>
    <span class="count">{albums.length} albums</span>
  </div>

  {#if loading}
    <div class="center"><span class="muted">Loading…</span></div>
  {:else if error}
    <div class="center"><span class="err">{error}</span></div>
  {:else if albums.length === 0}
    <div class="center">
      <div class="empty-icon">♫</div>
      <p class="muted">No albums yet</p>
      <p class="hint">Add albums with + Add URL (Cmd+4)</p>
    </div>
  {:else}
    <div class="grid">
      {#each albums as album}
        <div class="card" class:playing={album.id === currentAlbumId} on:click={() => goto(`/albums/${album.id}`)} role="button" tabindex="0" on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${album.id}`)}>
          <div class="cover-wrap">
            <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={120} radius={8} />
            <div class="play-overlay">
              <button
                class="play-btn"
                class:loading={playingId === album.id}
                on:click={(e) => playAlbum(e, album)}
                title="Play all"
              >
                {#if playingId === album.id}
                  <span class="spin">⟳</span>
                {:else}
                  ▶
                {/if}
              </button>
            </div>
          </div>
          <div class="card-info">
            <span class="card-title">{album.title}</span>
            <span class="card-sub">{album.platform || album.albumType}{album.year ? ` · ${album.year}` : ''}</span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  .header {
    display: flex;
    align-items: baseline;
    gap: 10px;
    margin-bottom: var(--sp-lg);
  }
  h1 { font-size: 22px; font-weight: 700; }
  .count { font-size: 12px; color: var(--text-muted); }
  .center {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 300px;
    color: var(--text-muted);
  }
  .empty-icon { font-size: 40px; opacity: 0.4; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); font-size: 13px; }
  .hint { font-size: 12px; color: var(--text-muted); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: var(--sp-md);
  }
  .card {
    display: flex;
    flex-direction: column;
    gap: 8px;
    text-align: left;
    border-radius: var(--r-md);
    padding: 8px;
    transition: background 0.15s;
    cursor: pointer;
  }
  .card:hover { background: rgba(255,255,255,0.04); }
  .card.playing { background: rgba(203, 168, 39, 0.10); }
  .card.playing .card-title { color: var(--accent); }
  .cover-wrap {
    border-radius: var(--r-md);
    overflow: hidden;
    position: relative;
  }
  .play-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: flex-end;
    justify-content: flex-end;
    padding: 8px;
    background: linear-gradient(to top, rgba(0,0,0,0.55) 0%, transparent 50%);
    opacity: 0;
    transition: opacity 0.15s;
  }
  .cover-wrap:hover .play-overlay { opacity: 1; }
  .play-btn {
    width: 36px; height: 36px;
    border-radius: 50%;
    background: rgba(255,255,255,0.92);
    color: #131320;
    font-size: 14px;
    display: flex; align-items: center; justify-content: center;
    box-shadow: 0 2px 8px rgba(0,0,0,0.4);
    transition: transform 0.1s, background 0.1s;
    padding-left: 2px; /* optical center for ▶ */
  }
  .play-btn:hover { transform: scale(1.08); background: white; }
  .play-btn.loading { cursor: default; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .spin { display: inline-block; animation: spin 0.8s linear infinite; }
  .card-info { display: flex; flex-direction: column; gap: 2px; }
  .card-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .card-sub { font-size: 11px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
