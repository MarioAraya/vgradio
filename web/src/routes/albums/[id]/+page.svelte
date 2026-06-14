<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { api } from '$lib/api';
  import type { Album, AlbumSummary } from '$lib/types';
  import { player } from '$lib/stores/player';
  import { hidden } from '$lib/stores/hidden';
  import { currentUser } from '$lib/stores/auth';
  import { requireAuth } from '$lib/stores/authModal';
  import { coverPrefs } from '$lib/stores/coverPrefs';
  import CoverCarousel from '$lib/components/CoverCarousel.svelte';
  import CoverLightbox from '$lib/components/CoverLightbox.svelte';
  import { fmtTime } from '$lib/utils';
  import { addToast } from '$lib/stores/toasts';

  let lightboxOpen = false;
  let lightboxIndex = 0;

  let album: Album | null = null;
  let loading = true;
  let error = '';
  let coverIdx = 0;
  let fetching = new Set<string>();  // track IDs being fetched (download to disk)
  let scraping = new Set<string>();  // track IDs being scraped (resolve mp3 URL)

  $: id = $page.params.id!;

  onMount(async () => {
    try {
      album = await api.album(id);
      coverIdx = coverPrefs.get(id);
      const activeId = $player.queue[$player.queueIndex]?.id;
      if (activeId) {
        // wait one tick for DOM to render the track rows
        setTimeout(() => {
          document.getElementById(`track-${activeId}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }, 50);
      }
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally { loading = false; }
  });

  function toSummary(a: Album): AlbumSummary {
    return { id: a.id, title: a.title, platform: a.platform, year: a.year,
      albumType: a.albumType, trackCount: a.tracks.length, coverUrls: a.covers.map(c => c.url) };
  }

  function visibleTracks() {
    return album!.tracks.filter(t => !$hidden.has(t.id));
  }

  function playTrack(track: import('$lib/types').Track) {
    if (!album) return;
    const sum = toSummary(album);
    const queue = visibleTracks();
    player.play(track, sum, queue.length ? queue : [track], album.covers);
  }

  function playAll(shuffle = false) {
    if (!album) return;
    const sum = toSummary(album);
    const visible = visibleTracks();
    if (!visible.length) return;
    if (shuffle) {
      const shuffled = [...visible].sort(() => Math.random() - 0.5);
      player.play(shuffled[0], sum, shuffled, album.covers);
    } else {
      player.play(visible[0], sum, visible, album.covers);
    }
  }

  function setCover(i: number) {
    coverIdx = i;
    coverPrefs.set(id, i);
    player.setCoverIndex(id, i);
  }

  async function fetchTrack(trackId: string) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 120_000);
    fetching = new Set(fetching).add(trackId);
    try {
      await api.fetchTrack(trackId, ctrl.signal);
      if (album) {
        album = { ...album, tracks: album.tracks.map(t => t.id === trackId ? { ...t, downloaded: true } : t) };
      }
      addToast('Descargado', 'info');
    } catch (e) {
      const msg = (e as Error).name === 'AbortError' ? 'Timeout al descargar (>120s)' : 'Error: ' + (e instanceof Error ? e.message : String(e));
      addToast(msg, 'error');
    } finally {
      clearTimeout(timer);
      const next = new Set(fetching);
      next.delete(trackId);
      fetching = next;
    }
  }

  async function scrapeTrack(trackId: string) {
    scraping = new Set(scraping).add(trackId);
    try {
      await api.resolveTrackUrl(trackId, false);
      if (album) {
        album = { ...album, tracks: album.tracks.map(t => t.id === trackId ? { ...t, scraped: true } : t) };
      }
    } catch (e) {
      addToast('Error al scrapear URL: ' + (e instanceof Error ? e.message : String(e)), 'error');
    } finally {
      const next = new Set(scraping);
      next.delete(trackId);
      scraping = next;
    }
  }

  let trackFilter = '';
  let compact = false;

  $: isThisAlbumCurrent = $player.currentAlbum?.id === album?.id;
  $: isThisAlbumPlaying = isThisAlbumCurrent && $player.isPlaying;

  let albumScraping = false;
  async function scrapeAllTracks() {
    if (!album || albumScraping) return;
    albumScraping = true;
    try {
      const r = await api.scrapeAlbumTracks(album.id);
      // Mark all tracks as scraped in local state
      if (album) {
        album = { ...album, tracks: album.tracks.map(t => ({ ...t, scraped: t.scraped || true })) };
      }
      addToast(`URLs resueltas: ${r.resolved} ok · ${r.failed} fallidas · ${r.skipped} ya tenían`, 'info', 5000);
    } catch (e) {
      addToast('Error al scrapear: ' + (e instanceof Error ? e.message : String(e)), 'error');
    } finally {
      albumScraping = false;
    }
  }

  $: isAlbumFav = album?.isFavorite ?? false;

  async function doToggleAlbumFav() {
    if (!album) return;
    try {
      const res = await api.toggleFavorite(album.id);
      album = { ...album, isFavorite: res.favorited };
    } catch (e) {
      addToast('Error al guardar favorito', 'error');
    }
  }

  function toggleAlbumFav() {
    requireAuth(doToggleAlbumFav);
  }

  async function doToggleTrackFav(track: import('$lib/types').Track) {
    try {
      const res = await api.toggleTrackFavorite(track.id);
      if (album) {
        album = { ...album, tracks: album.tracks.map(t =>
          t.id === track.id ? { ...t, isFavorite: res.favorited } : t
        )};
      }
    } catch (e) {
      addToast('Error al guardar favorito', 'error');
    }
  }

  function toggleTrackFav(track: import('$lib/types').Track) {
    requireAuth(() => doToggleTrackFav(track));
  }
</script>

<div class="page">
  <button class="back" on:click={() => goto('/')}>← Library</button>

  {#if loading}
    <div class="center"><span class="muted">Loading…</span></div>
  {:else if error}
    <div class="center"><span class="err">{error}</span></div>
  {:else if album}
    <div class="top">
      <div class="cover-wrap">
        <CoverCarousel
          covers={album.covers}
          index={coverIdx}
          size={220}
          on:change={(e) => setCover(e.detail)}
          on:open={(e) => { lightboxIndex = e.detail; lightboxOpen = true; }}
        />
        <button
          class="play-fab"
          class:playing={isThisAlbumPlaying}
          on:click={() => isThisAlbumCurrent ? player.togglePlay() : playAll(false)}
          title={isThisAlbumPlaying ? 'Pause' : 'Play'}
        >
          {#if isThisAlbumPlaying}⏸{:else}▶{/if}
        </button>
      </div>
      <div class="meta">
        <h1 class="title">{album.title}</h1>
        {#if album.altTitle}<p class="alt">{album.altTitle}</p>{/if}
        <div class="tags">
          {#if album.platform}<span class="tag">{album.platform}</span>{/if}
          {#if album.year}<span class="tag">{album.year}</span>{/if}
          {#if album.albumType}<span class="tag">{album.albumType}</span>{/if}
        </div>
        {#if album.developer}<p class="detail">Developer: {album.developer}</p>{/if}
        {#if album.publisher}<p class="detail">Publisher: {album.publisher}</p>{/if}
        {#if album.catalogNumber}<p class="detail">Catalog: {album.catalogNumber}</p>{/if}
        <div class="actions">
          <button class="btn-primary" on:click={() => playAll(false)}>▶ Play All</button>
          <button class="btn-sec" on:click={() => playAll(true)}>⇀ Shuffle</button>
          <button class="btn-sec" class:fav={isAlbumFav} on:click={toggleAlbumFav}>
            {isAlbumFav ? '★ Unfavorite' : '☆ Favorite'}
          </button>
          <a class="btn-sec" href={`${api.baseURL()}/albums/${id}/covers.zip`} download>
            ⬇ Covers
          </a>
          <button class="btn-sec" class:scraping={albumScraping} on:click={scrapeAllTracks} disabled={albumScraping} title="Resuelve URLs de MP3 de todas las canciones desde khinsider">
            {albumScraping ? '⟳ Scraping…' : '⚡ Scrape URLs'}
          </button>
          {#if album.sourceUrl}
            <a class="source-link" href={album.sourceUrl} target="_blank" rel="noopener noreferrer" title="Visit source">↗</a>
          {/if}
        </div>
      </div>
    </div>

    <div class="tracklist" class:compact>
      <div class="track-header">
        <span class="col-num">#</span>
        <span class="col-name">
          <div class="filter-wrap" class:has-value={!!trackFilter}>
            <span class="filter-icon">🔍</span>
            <input class="track-filter" type="text" placeholder="Filter tracks…" bind:value={trackFilter} />
          </div>
        </span>
        <span class="col-dur">Duration</span>
        <span class="col-acts">
          <button class="compact-btn" class:active={compact} on:click={() => compact = !compact} title={compact ? 'Vista normal' : 'Vista compacta'}>
            {compact ? '▤' : '☰'}
          </button>
        </span>
      </div>
      {#each album.tracks.filter(t => !trackFilter || t.name.toLowerCase().includes(trackFilter.toLowerCase())) as track, i}
        {@const isPlaying = $player.queue[$player.queueIndex]?.id === track.id && $player.isPlaying}
        {@const isCurrent = $player.queue[$player.queueIndex]?.id === track.id}
        {@const isFav = track.isFavorite ?? false}
        {@const isHid = $hidden.has(track.id)}
        {@const trackNum = album.tracks.indexOf(track) + 1}
        <div
          id="track-{track.id}"
          class="track-row"
          class:current={isCurrent}
          class:hidden-track={isHid}
          on:dblclick={() => playTrack(track)}
          role="row"
        >
          <span class="col-num">
            {#if isPlaying}
              <span class="wave">♪</span>
            {:else}
              <span class="num-wrap">
                {trackNum}
                {#if track.downloaded}
                  <span class="state-dot dot-local" title="Descargado localmente"></span>
                {:else if track.scraped}
                  <span class="state-dot dot-scraped" title="URL resuelta"></span>
                {/if}
              </span>
            {/if}
          </span>
          <button class="col-name track-name" on:click={() => playTrack(track)}>{track.name}</button>
          <span class="col-dur">{fmtTime(track.durationSec)}</span>
          <div class="col-acts acts">
            <button class="act" title="Play next" on:click={() => player.playNext(track)}>▶+</button>
            <button class="act" class:act-active={isFav} title="Favorite"
              on:click={() => toggleTrackFav(track)}>
              {isFav ? '★' : '☆'}
            </button>
            <button class="act hide-btn" class:hide-active={isHid} title={isHid ? 'Unhide' : 'Hide'}
              on:click={() => hidden.toggle(track.id)}>
              👎
            </button>
            {#if track.downloaded}
              <a class="act act-dl-local" href={api.downloadURL(track)} download target="_blank" rel="noopener noreferrer" title="Guardar MP3 (local)">⬇</a>
            {:else if fetching.has(track.id)}
              <span class="act act-spin" title="Descargando…">⟳</span>
            {:else if scraping.has(track.id)}
              <span class="act act-spin" title="Scrapeando URL…">⟳</span>
            {:else if track.scraped}
              <button class="act act-scraped" title="Descargar localmente" on:click={() => fetchTrack(track.id)}>⬇</button>
            {:else}
              <button class="act act-unscrape" title="Resolver URL de khinsider" on:click={() => scrapeTrack(track.id)}>🔗</button>
            {/if}
          </div>
        </div>
      {/each}
    </div>

    {#if album.description}
      <div class="description">{album.description}</div>
    {/if}

    {#if album.comments.length > 0}
      <div class="comments">
        <h3>Comments</h3>
        {#each album.comments as c}
          <div class="comment">
            <span class="c-author">{c.author}</span>
            <span class="c-date">{c.postedAt.slice(0,10)}</span>
            <p class="c-body">{c.body}</p>
          </div>
        {/each}
      </div>
    {/if}

    <CoverLightbox
      covers={album.covers}
      bind:index={lightboxIndex}
      open={lightboxOpen}
      on:close={() => lightboxOpen = false}
      on:change={(e) => { lightboxIndex = e.detail; setCover(e.detail); }}
    />
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  .back { font-size: 13px; color: var(--text-sec); margin-bottom: 20px; }
  .back:hover { color: var(--accent); }
  .center { display: flex; align-items: center; justify-content: center; min-height: 300px; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); }
  .top { display: flex; gap: 28px; margin-bottom: 28px; align-items: flex-start; }
  .cover-wrap { position: relative; flex-shrink: 0; }
  .play-fab {
    position: absolute;
    bottom: 10px; right: 10px;
    width: 44px; height: 44px;
    border-radius: 50%;
    background: var(--accent);
    color: #131320;
    font-size: 16px;
    display: flex; align-items: center; justify-content: center;
    box-shadow: 0 4px 12px rgba(0,0,0,0.5);
    opacity: 0;
    transform: translateY(4px);
    transition: opacity 0.15s, transform 0.15s;
  }
  .cover-wrap:hover .play-fab,
  .play-fab.playing { opacity: 1; transform: translateY(0); }
  .meta { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
  .title { font-size: 22px; font-weight: 700; line-height: 1.2; }
  .alt { font-size: 13px; color: var(--text-sec); }
  .tags { display: flex; gap: 6px; flex-wrap: wrap; }
  .tag {
    font-size: 11px;
    padding: 2px 8px;
    background: var(--surface-hi);
    border-radius: 20px;
    color: var(--text-sec);
  }
  .detail { font-size: 12px; color: var(--text-muted); }
  .actions { display: flex; gap: 8px; margin-top: 8px; flex-wrap: wrap; }
  .btn-primary {
    padding: 7px 16px;
    background: var(--accent);
    color: #131320;
    border-radius: var(--r-sm);
    font-size: 13px;
    font-weight: 600;
  }
  .btn-sec {
    padding: 7px 14px;
    background: var(--surface-hi);
    color: var(--text-sec);
    border-radius: var(--r-sm);
    font-size: 13px;
  }
  .btn-sec:hover { color: var(--text); }
  .btn-sec.fav { color: var(--accent); }
  .btn-sec.scraping { opacity: 0.6; cursor: default; }
  .source-link {
    display: flex; align-items: center; justify-content: center;
    width: 30px; height: 30px;
    font-size: 14px;
    color: transparent;
    border-radius: var(--r-sm);
    transition: color 0.15s, background 0.15s;
  }
  .source-link:hover { color: var(--text-sec); background: var(--surface-hi); }

  .filter-wrap { display: flex; align-items: center; width: 100%; }
  .filter-icon {
    font-size: 11px;
    opacity: 0.45;
    transition: opacity 0.15s, width 0.15s;
    width: auto;
    flex-shrink: 0;
  }
  .track-filter {
    font-size: 11px;
    background: transparent;
    color: var(--text);
    width: 0;
    opacity: 0;
    padding: 0;
    border-bottom: 1px solid transparent;
    transition: width 0.2s, opacity 0.15s, border-color 0.15s;
    overflow: hidden;
  }
  .filter-wrap:hover .filter-icon,
  .filter-wrap.has-value .filter-icon { opacity: 0; width: 0; pointer-events: none; }
  .filter-wrap:hover .track-filter,
  .filter-wrap.has-value .track-filter { width: 100%; opacity: 1; }
  .track-filter::placeholder { color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .track-filter:focus { outline: none; border-bottom-color: var(--accent); }
  .compact-btn {
    font-size: 14px;
    color: var(--text-muted);
    padding: 2px 4px;
    border-radius: var(--r-sm);
  }
  .compact-btn:hover, .compact-btn.active { color: var(--accent); }
  .tracklist { margin-bottom: 24px; }
  .tracklist.compact .track-row { height: 28px; padding-top: 2px; padding-bottom: 2px; }
  .tracklist.compact .track-name { font-size: 12px; }
  .tracklist.compact .col-num { font-size: 11px; }
  .tracklist.compact .col-dur { font-size: 11px; }
  .track-header {
    display: grid;
    grid-template-columns: 32px 1fr 64px 120px;
    padding: 4px 8px;
    border-bottom: 1px solid var(--separator);
    font-size: 11px;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-bottom: 4px;
  }
  .track-row {
    display: grid;
    grid-template-columns: 32px 1fr 64px 120px;
    align-items: center;
    padding: 4px 8px;
    border-radius: var(--r-sm);
    height: 40px;
    transition: background 0.1s;
  }
  .track-row:hover { background: rgba(255,255,255,0.04); }
  .track-row.current { background: rgba(203, 168, 39, 0.12); }
  .track-row.current .track-name { color: var(--accent); font-weight: 700; }
  .track-row.current .col-num { color: var(--accent); }
  .track-row.hidden-track { opacity: 0.35; }
  .col-num { font-size: 12px; color: var(--text-muted); text-align: right; padding-right: 8px; }
  .wave { color: var(--accent); }
  .track-name {
    text-align: left;
    font-size: 13px;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    padding-right: 8px;
  }
  .track-name:hover { color: var(--accent); }
  .col-dur { font-size: 12px; color: var(--text-muted); font-variant-numeric: tabular-nums; }
  .acts { display: flex; gap: 2px; opacity: 0; transition: opacity 0.1s; }
  .track-row:hover .acts { opacity: 1; }
  .track-row.current .acts { opacity: 1; }
  .track-row.hidden-track .acts { opacity: 1; }
  .act {
    font-size: 13px;
    width: 28px; height: 28px;
    display: flex; align-items: center; justify-content: center;
    color: var(--text-muted);
    border-radius: var(--r-sm);
  }
  .act:hover { color: var(--text); background: rgba(255,255,255,0.06); }
  .act-active { color: var(--accent) !important; }

  .hide-btn { filter: grayscale(1); opacity: 0.35; }
  .hide-btn:hover { filter: none; opacity: 1; }
  .hide-btn.hide-active { filter: none; opacity: 1; }

  /* State dots on track number */
  .num-wrap { position: relative; display: inline-flex; align-items: center; justify-content: flex-end; }
  .state-dot {
    position: absolute;
    right: -6px; top: 50%; transform: translateY(-50%);
    width: 5px; height: 5px;
    border-radius: 50%;
  }
  .dot-local   { background: #4ade80; } /* green — on disk */
  .dot-scraped { background: var(--accent); } /* yellow — url known */

  /* Download/scrape action buttons */
  .act-dl-local  { color: #4ade80; }
  .act-dl-local:hover { color: #86efac; background: rgba(74,222,128,0.08); }
  .act-scraped   { color: var(--accent); opacity: 0.7; }
  .act-scraped:hover { opacity: 1; background: rgba(203,168,39,0.08); }
  .act-unscrape  { opacity: 0.2; font-size: 11px; }
  .act-unscrape:hover { opacity: 1; color: var(--text); }
  @keyframes spin { to { transform: rotate(360deg); } }
  .act-spin { animation: spin 0.9s linear infinite; opacity: 0.5; cursor: default; }

  .description {
    font-size: 13px;
    color: var(--text-sec);
    line-height: 1.6;
    max-width: 640px;
    margin-bottom: 24px;
    white-space: pre-wrap;
  }
  .comments h3 { font-size: 14px; font-weight: 600; margin-bottom: 12px; }
  .comment {
    border-top: 1px solid var(--separator);
    padding: 10px 0;
  }
  .c-author { font-size: 12px; font-weight: 600; color: var(--accent); }
  .c-date { font-size: 11px; color: var(--text-muted); margin-left: 8px; }
  .c-body { font-size: 13px; color: var(--text-sec); line-height: 1.5; margin-top: 4px; }
</style>
