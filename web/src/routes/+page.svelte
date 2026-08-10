<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import CompactAlbumCard from '$lib/components/CompactAlbumCard.svelte';
  import FavoriteButton from '$lib/components/FavoriteButton.svelte';
  import ContextMenu from '$lib/components/ContextMenu.svelte';
  import AddToPlaylistModal from '$lib/components/AddToPlaylistModal.svelte';
  import { player } from '$lib/stores/player';
  import { currentUser } from '$lib/stores/auth';
  import { addToast } from '$lib/stores/toasts';
  import { fmtDuration } from '$lib/utils';
  import { setDragPayload } from '$lib/dnd';

  $: currentAlbumId = $player.queue[$player.queueIndex]?.album.id ?? null;

  let albums: AlbumSummary[] = [];
  let loading = true;
  let error = '';
  let playingId: string | null = null;
  let playCtrl: AbortController | null = null;
  let filterText = '';
  let filterInput: HTMLInputElement | null = null;

  type ViewMode = 'grid' | 'compact' | 'list';
  let viewMode: ViewMode = (localStorage.getItem('vgradio.libraryViewMode') as ViewMode) || 'grid';
  $: localStorage.setItem('vgradio.libraryViewMode', viewMode);

  $: filteredAlbums = filterText.trim()
    ? albums.filter(a => matches(a.title, filterText) || matches(a.platform, filterText))
    : albums;

  function matches(haystack: string, query: string): boolean {
    const words = query.trim().split(/\s+/);
    return words.every(w => haystack.toLowerCase().includes(w.toLowerCase()));
  }

  function onWindowKeydown(e: KeyboardEvent) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') {
      e.preventDefault();
      filterInput?.focus();
    }
  }

  onMount(async () => {
    try { albums = await api.albums(); }
    catch (e) { error = e instanceof Error ? e.message : String(e); }
    finally { loading = false; }
  });

  let ctxMenu: { x: number; y: number; album: AlbumSummary } | null = null;

  function openAlbumContextMenu(e: MouseEvent, album: AlbumSummary) {
    e.preventDefault();
    ctxMenu = { x: e.clientX, y: e.clientY, album };
  }

  let addToPlaylistTrackIds: string[] = [];
  let addToPlaylistOpen = false;

  async function addAlbumToPlaylist(summary: AlbumSummary) {
    try {
      const album = await api.album(summary.id);
      addToPlaylistTrackIds = album.tracks.map(t => t.id);
      addToPlaylistOpen = true;
    } catch (e) {
      addToast('Error: ' + (e instanceof Error ? e.message : String(e)), 'error');
    }
  }

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

<svelte:window on:keydown={onWindowKeydown} />

<div class="page">
  <div class="header">
    <h1>Library</h1>
    <span class="count">{albums.length} albums</span>
    <div class="spacer"></div>
    <div class="filter-wrap">
      <span class="filter-icon">🔍</span>
      <input
        bind:this={filterInput}
        class="filter-input"
        type="text"
        placeholder="Filter albums… (⌘F)"
        bind:value={filterText}
        on:keydown={(e) => { if (e.key === 'Escape') { filterText = ''; filterInput?.blur(); } }}
      />
    </div>
    <div class="view-toggle">
      <button class:active={viewMode === 'grid'} on:click={() => viewMode = 'grid'} title="Grid view">▦</button>
      <button class:active={viewMode === 'compact'} on:click={() => viewMode = 'compact'} title="Compact view">▪▪</button>
      <button class:active={viewMode === 'list'} on:click={() => viewMode = 'list'} title="List view">☰</button>
    </div>
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
  {:else if filteredAlbums.length === 0}
    <div class="center"><span class="muted">No results for "{filterText}"</span></div>
  {:else if viewMode === 'list'}
    <div class="rows">
      {#each filteredAlbums as album}
        <div class="row" class:playing={album.id === currentAlbumId} on:click={() => goto(`/albums/${album.id}`)} on:contextmenu={(e) => openAlbumContextMenu(e, album)} draggable="true" on:dragstart={(e) => setDragPayload(e, { albumId: album.id })} role="button" tabindex="0" on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${album.id}`)}>
          <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={44} radius={6} />
          <div class="row-info">
            <span class="row-title">{album.title}</span>
            <span class="row-sub">{album.platform || album.albumType}{album.year ? ` · ${album.year}` : ''}</span>
          </div>
          <span class="row-dur">{album.totalDurationSec ? fmtDuration(album.totalDurationSec) : ''}</span>
          <span class="row-tracks">{album.trackCount} tracks</span>
        </div>
      {/each}
    </div>
  {:else if viewMode === 'compact'}
    <div class="compact-grid">
      {#each filteredAlbums as album}
        <CompactAlbumCard {album} on:click={() => goto(`/albums/${album.id}`)} on:contextmenu={(e) => openAlbumContextMenu(e, album)} on:dragstart={(e) => setDragPayload(e, { albumId: album.id })} on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${album.id}`)} />
      {/each}
    </div>
  {:else}
    <div class="grid">
      {#each filteredAlbums as album}
        <div class="card" class:playing={album.id === currentAlbumId} on:click={() => goto(`/albums/${album.id}`)} on:contextmenu={(e) => openAlbumContextMenu(e, album)} draggable="true" on:dragstart={(e) => setDragPayload(e, { albumId: album.id })} role="button" tabindex="0" on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${album.id}`)}>
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
            <div class="card-title-row">
              <span class="card-title">{album.title}</span>
              <FavoriteButton albumId={album.id} favorited={album.isFavorite ?? false}
                on:change={(e) => { album.isFavorite = e.detail; albums = albums; }} />
            </div>
            <span class="card-sub">{album.platform || album.albumType}{album.year ? ` · ${album.year}` : ''}{album.totalDurationSec ? ` · ${fmtDuration(album.totalDurationSec)}` : ''}</span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<AddToPlaylistModal bind:open={addToPlaylistOpen} trackIds={addToPlaylistTrackIds} />

{#if ctxMenu}
  {@const album = ctxMenu.album}
  <ContextMenu x={ctxMenu.x} y={ctxMenu.y} onClose={() => ctxMenu = null}>
    <button on:click={() => { goto(`/albums/${album.id}`); ctxMenu = null; }}>↗ Open Album</button>
    {#if $currentUser}
      <button on:click={() => { addAlbumToPlaylist(album); ctxMenu = null; }}>+ Add Album to Playlist…</button>
    {/if}
  </ContextMenu>
{/if}

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
  .spacer { flex: 1; }
  .filter-wrap {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 10px;
    background: var(--hover-md);
    border-radius: var(--r-sm);
    width: 220px;
  }
  .filter-icon { font-size: 12px; opacity: 0.6; }
  .filter-input {
    background: transparent;
    border: none;
    outline: none;
    color: var(--text);
    font-size: 13px;
    width: 100%;
  }
  .filter-input::placeholder { color: var(--text-muted); }
  .view-toggle {
    display: flex;
    gap: 2px;
    padding: 2px;
    background: var(--hover-md);
    border-radius: var(--r-sm);
  }
  .view-toggle button {
    width: 28px; height: 24px;
    font-size: 12px;
    color: var(--text-muted);
    border-radius: 5px;
    display: flex; align-items: center; justify-content: center;
  }
  .view-toggle button.active { color: var(--accent); background: var(--accent-soft); }
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
  .card:hover { background: var(--hover); }
  .card.playing { background: var(--accent-soft); }
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
  .card-title-row {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .card-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
    min-width: 0;
  }
  .card-sub { font-size: 11px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

  .compact-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 2px;
  }

  .rows { display: flex; flex-direction: column; }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 4px 8px;
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: background 0.1s;
  }
  .row:hover { background: var(--hover); }
  .row.playing .row-title { color: var(--accent); }
  .row-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .row-title { font-size: 13px; font-weight: 600; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row-sub { font-size: 11px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row-dur { font-size: 12px; color: var(--text-sec); width: 60px; text-align: right; flex-shrink: 0; }
  .row-tracks { font-size: 11px; color: var(--text-muted); width: 80px; text-align: right; flex-shrink: 0; }
</style>
