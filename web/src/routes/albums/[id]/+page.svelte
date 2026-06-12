<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { api } from '$lib/api';
  import type { Album, AlbumSummary } from '$lib/types';
  import { player } from '$lib/stores/player';
  import { favorites } from '$lib/stores/favorites';
  import { hidden } from '$lib/stores/hidden';
  import { coverPrefs } from '$lib/stores/coverPrefs';
  import CoverCarousel from '$lib/components/CoverCarousel.svelte';
  import CoverLightbox from '$lib/components/CoverLightbox.svelte';
  import { fmtTime } from '$lib/utils';

  let lightboxOpen = false;
  let lightboxIndex = 0;

  let album: Album | null = null;
  let loading = true;
  let error = '';
  let coverIdx = 0;

  $: id = $page.params.id;

  onMount(async () => {
    try {
      album = await api.album(id);
      coverIdx = coverPrefs.get(id);
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally { loading = false; }
  });

  function toSummary(a: Album): AlbumSummary {
    return { id: a.id, title: a.title, platform: a.platform, year: a.year,
      albumType: a.albumType, trackCount: a.tracks.length, coverUrls: a.covers.map(c => c.url) };
  }

  function playTrack(idx: number) {
    if (!album) return;
    const sum = toSummary(album);
    player.play(album.tracks[idx], sum, album.tracks, album.covers);
  }

  function playAll(shuffle = false) {
    if (!album) return;
    const sum = toSummary(album);
    if (shuffle) {
      const shuffled = [...album.tracks].sort(() => Math.random() - 0.5);
      player.play(shuffled[0], sum, shuffled, album.covers);
    } else {
      player.play(album.tracks[0], sum, album.tracks, album.covers);
    }
  }

  function setCover(i: number) {
    coverIdx = i;
    coverPrefs.set(id, i);
    player.setCoverIndex(id, i);
  }

  $: isAlbumFav = album ? $favorites.some(f => f.albumId === album!.id) : false;

  function toggleAlbumFav() {
    if (!album) return;
    const sum = toSummary(album);
    if (isAlbumFav) favorites.removeAll(album.id);
    else favorites.addAll(album.tracks, sum);
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
      <CoverCarousel
        covers={album.covers}
        index={coverIdx}
        size={220}
        on:change={(e) => setCover(e.detail)}
        on:open={(e) => { lightboxIndex = e.detail; lightboxOpen = true; }}
      />
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
        </div>
      </div>
    </div>

    <div class="tracklist">
      <div class="track-header">
        <span class="col-num">#</span>
        <span class="col-name">Title</span>
        <span class="col-dur">Duration</span>
        <span class="col-acts"></span>
      </div>
      {#each album.tracks as track, i}
        {@const isPlaying = $player.queue[$player.queueIndex]?.id === track.id && $player.isPlaying}
        {@const isCurrent = $player.queue[$player.queueIndex]?.id === track.id}
        {@const isFav = $favorites.some(f => f.id === track.id)}
        {@const isHid = $hidden.has(track.id)}
        <div
          class="track-row"
          class:current={isCurrent}
          class:hidden-track={isHid}
          on:dblclick={() => playTrack(i)}
          role="row"
        >
          <span class="col-num">
            {#if isPlaying}<span class="wave">♪</span>{:else}{i + 1}{/if}
          </span>
          <button class="col-name track-name" on:click={() => playTrack(i)}>{track.name}</button>
          <span class="col-dur">{fmtTime(track.durationSec)}</span>
          <div class="col-acts acts">
            <button class="act" title="Play next" on:click={() => player.playNext(track)}>▶+</button>
            <button class="act" class:act-active={isFav} title="Favorite"
              on:click={() => favorites.toggle(track, toSummary(album!))}>
              {isFav ? '★' : '☆'}
            </button>
            <button class="act" class:act-active={isHid} title="Hide"
              on:click={() => hidden.toggle(track.id)}>
              {isHid ? '👁' : '👎'}
            </button>
            {#if track.downloaded}
              <a class="act" href={api.downloadURL(track)} download>⬇</a>
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

  .tracklist { margin-bottom: 24px; }
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
  .track-row.current { background: var(--accent-bg); }
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
  .act {
    font-size: 13px;
    width: 28px; height: 28px;
    display: flex; align-items: center; justify-content: center;
    color: var(--text-muted);
    border-radius: var(--r-sm);
  }
  .act:hover { color: var(--text); background: rgba(255,255,255,0.06); }
  .act-active { color: var(--accent) !important; }

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
