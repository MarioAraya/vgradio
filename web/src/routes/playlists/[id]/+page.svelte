<script lang="ts">
  import { page } from '$app/stores';
  import { api } from '$lib/api';
  import { currentUser, authLoading } from '$lib/stores/auth';
  import { player } from '$lib/stores/player';
  import { addToast } from '$lib/stores/toasts';
  import { deletePlaylist, removeTrackFromPlaylist } from '$lib/stores/playlists';
  import { fmtTime } from '$lib/utils';
  import { goto } from '$app/navigation';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import PlaylistEditModal from '$lib/components/PlaylistEditModal.svelte';
  import type { PlaylistDetail, PlaylistTrack } from '$lib/types';

  let pl: PlaylistDetail | null = null;
  let loadErr = '';
  let fetching = false;
  let editOpen = false;

  $: id = $page.params.id;
  $: if (id) loadPlaylist(id);

  async function loadPlaylist(plId: string) {
    fetching = true;
    loadErr = '';
    try { pl = await api.playlist(plId); }
    catch (e: any) { loadErr = e.message ?? 'Error'; }
    finally { fetching = false; }
  }

  $: isOwner = !!$currentUser && !!pl && $currentUser.id === pl.ownerId;

  function trackToPlayer(t: PlaylistTrack, idx: number) {
    return { id: t.id, index: idx, name: t.name, durationSec: t.durationSec,
      sizeBytes: 0, streamUrl: t.streamUrl,
      downloadUrl: t.streamUrl.replace('/stream', '/download'), downloaded: false };
  }

  function playAll() {
    if (!pl?.tracks.length) return;
    const queue = pl.tracks.map(trackToPlayer);
    const summary = {
      id: pl.id, title: pl.name, platform: '', year: 0, albumType: '',
      trackCount: pl.trackCount, totalDurationSec: pl.totalDurationSec, coverUrls: pl.coverUrls
    };
    player.play(queue[0], summary, queue);
  }

  function playFrom(t: PlaylistTrack) {
    if (!pl) return;
    const queue = pl.tracks.map(trackToPlayer);
    const summary = {
      id: pl.id, title: pl.name, platform: '', year: 0, albumType: '',
      trackCount: pl.trackCount, totalDurationSec: pl.totalDurationSec, coverUrls: pl.coverUrls
    };
    const track = queue.find(q => q.id === t.id);
    if (track) player.play(track, summary, queue);
  }

  async function removeTr(t: PlaylistTrack) {
    if (!pl) return;
    try {
      await removeTrackFromPlaylist(pl.id, t.id);
      pl = { ...pl, tracks: pl.tracks.filter(tr => tr.id !== t.id), trackCount: pl.trackCount - 1 };
      addToast('Track removed');
    } catch { addToast('Error', 'error'); }
  }

  async function onDelete() {
    if (!pl || !confirm(`Delete "${pl.name}"?`)) return;
    try {
      await deletePlaylist(pl.id);
      goto('/');
    } catch { addToast('Error deleting playlist', 'error'); }
  }

  function fmtDuration(sec: number) {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }
</script>

<div class="page">
  {#if fetching && !pl}
    <div class="center"><span class="muted">Cargando…</span></div>

  {:else if loadErr}
    <div class="center"><span class="err">{loadErr}</span></div>

  {:else if pl}
    <div class="hero">
      <div class="hero-cover">
        {#if pl.coverUrls.length}
          <div class="mosaic" class:single={pl.coverUrls.length === 1}>
            {#each pl.coverUrls as url}
              <CoverImage {url} title={pl.name} size={80} radius={0} />
            {/each}
          </div>
        {:else}
          <div class="cover-placeholder">♫</div>
        {/if}
      </div>

      <div class="hero-info">
        <span class="meta-top">{pl.isPublic ? 'Playlist · Public' : 'Playlist · Private'} · {pl.createdAt.slice(0, 4)}</span>
        <h1>{pl.name}</h1>
        {#if pl.description}<p class="desc">{pl.description}</p>{/if}
        <span class="owner">@{pl.ownerName}</span>
        <span class="meta">{pl.trackCount} tracks{pl.totalDurationSec ? ` · ${fmtDuration(pl.totalDurationSec)}` : ''}</span>
        <div class="actions">
          <button class="play-btn" on:click={playAll} disabled={!pl.tracks.length}>▶</button>
          {#if isOwner}
            <button class="icon-btn" title="Edit" on:click={() => (editOpen = true)}>✏</button>
            <button class="icon-btn danger" title="Delete" on:click={onDelete}>✕</button>
          {/if}
        </div>
      </div>
    </div>

    {#if pl.tracks.length === 0}
      <div class="center">
        <p class="muted">No tracks yet. Add from an album page.</p>
      </div>
    {:else}
      <div class="track-list">
        {#each pl.tracks as t, i (t.id)}
          <div class="track-row">
            <span class="pos">{i + 1}</span>
            <CoverImage url={t.coverUrl ?? ''} title={t.albumTitle} size={32} radius={4} />
            <div class="track-info">
              <button class="track-name" on:click={() => playFrom(t)}>{t.name}</button>
              <span class="track-album">
                <a href="/albums/{t.albumId}">{t.albumTitle}</a>
                {#if t.platform} · {t.platform}{/if}
              </span>
            </div>
            <span class="track-dur">{fmtTime(t.durationSec)}</span>
            {#if isOwner}
              <button class="remove-btn" title="Remove" on:click={() => removeTr(t)}>✕</button>
            {/if}
          </div>
        {/each}
      </div>
    {/if}

    {#if pl}
      <PlaylistEditModal bind:open={editOpen} playlist={pl}
        on:done={e => { pl = pl ? { ...pl, name: e.detail.name, description: e.detail.description, isPublic: e.detail.isPublic } : pl; }} />
    {/if}
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); max-width: 860px; }
  .center { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; min-height: 300px; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); }

  .hero { display: flex; gap: 24px; align-items: flex-end; margin-bottom: 32px; padding-bottom: 24px; border-bottom: 1px solid var(--separator); }
  .hero-cover { flex-shrink: 0; }
  .mosaic { display: grid; grid-template-columns: 1fr 1fr; width: 160px; height: 160px; border-radius: var(--r-lg); overflow: hidden; }
  .mosaic.single { grid-template-columns: 1fr; }
  .cover-placeholder { width: 160px; height: 160px; border-radius: var(--r-lg); background: var(--surface-hi); display: flex; align-items: center; justify-content: center; font-size: 48px; color: var(--text-sec); }
  .hero-info { display: flex; flex-direction: column; gap: 5px; }
  .meta-top { font-size: 11px; color: var(--text-sec); text-transform: uppercase; letter-spacing: 0.06em; }
  h1 { font-size: 28px; font-weight: 800; }
  .desc { font-size: 12px; color: var(--text-sec); max-width: 420px; }
  .owner { font-size: 12px; color: var(--text-sec); }
  .meta { font-size: 12px; color: var(--text-sec); }
  .actions { display: flex; align-items: center; gap: 10px; margin-top: 10px; }
  .play-btn { width: 48px; height: 48px; border-radius: 50%; background: var(--accent); color: #000; font-size: 18px; font-weight: 700; display: flex; align-items: center; justify-content: center; }
  .play-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .play-btn:not(:disabled):hover { opacity: 0.88; }
  .icon-btn { width: 36px; height: 36px; border-radius: 50%; background: var(--surface-hi); font-size: 14px; display: flex; align-items: center; justify-content: center; }
  .icon-btn:hover { background: var(--muted); }
  .icon-btn.danger:hover { color: var(--red); }

  .track-list { display: flex; flex-direction: column; gap: 1px; }
  .track-row { display: flex; align-items: center; gap: 10px; padding: 7px 8px; border-radius: var(--r-sm); }
  .track-row:hover { background: var(--surface-hi); }
  .pos { width: 22px; text-align: right; font-size: 12px; color: var(--text-sec); flex-shrink: 0; }
  .track-info { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .track-name { text-align: left; font-size: 13px; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .track-name:hover { color: var(--accent); }
  .track-album { font-size: 11px; color: var(--text-sec); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .track-album a:hover { color: var(--accent); }
  .track-dur { font-size: 11px; color: var(--text-sec); min-width: 36px; text-align: right; flex-shrink: 0; }
  .remove-btn { font-size: 12px; color: var(--text-sec); padding: 4px; border-radius: var(--r-sm); opacity: 0; }
  .track-row:hover .remove-btn { opacity: 1; }
  .remove-btn:hover { color: var(--red); }
</style>
