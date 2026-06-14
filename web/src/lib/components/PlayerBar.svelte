<script lang="ts">
  import { player, playerNext, playerPrev } from '$lib/stores/player';
  import { fmtTime } from '$lib/utils';
  import CoverImage from './CoverImage.svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import { requireAuth } from '$lib/stores/authModal';
  import { favoritedTrackIDs, setTrackFavorited } from '$lib/stores/trackFavorites';

  let volumeHovered = false;
  let scrubDragging = false;
  let scrubEl: HTMLElement;
  let fsScrubEl: HTMLElement;
  let scrubHoverX: number | null = null;
  let scrubHoverTime: string | null = null;
  let fullscreen = false;

  $: track = $player.queue[$player.queueIndex] ?? null;
  $: album = $player.currentAlbum;
  $: covers = $player.currentCovers;
  $: coverUrl = covers[$player.currentCoverIndex]?.url ?? '';
  $: isFav = track ? $favoritedTrackIDs.has(track.id) : false;

  async function doToggleTrackFav() {
    if (!track) return;
    const id = track.id;
    try {
      const res = await api.toggleTrackFavorite(id);
      setTrackFavorited(id, res.favorited);
    } catch (e) {
      console.error('[PlayerBar] toggleTrackFavorite failed:', e);
    }
  }

  function toggleTrackFav() {
    requireAuth(doToggleTrackFav);
  }
  $: fraction = $player.duration > 0 ? $player.currentTime / $player.duration : 0;
  $: volFrac = $player.isMuted ? 0 : $player.volume;
  $: repeatTitle = $player.repeatMode === 'off'
    ? 'Activar repetición'
    : $player.repeatMode === 'all'
    ? 'Activar repetición de canción'
    : 'Desactivar repetición';

  function getFrac(el: HTMLElement, clientX: number): number {
    const rect = el.getBoundingClientRect();
    return Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
  }

  function onScrubDown(el: HTMLElement) {
    return (e: MouseEvent) => {
      scrubDragging = true;
      player.seek(getFrac(el, e.clientX) * $player.duration);
    };
  }

  function onScrubMove(el: HTMLElement) {
    return (e: MouseEvent) => {
      const rect = el.getBoundingClientRect();
      scrubHoverX = e.clientX - rect.left;
      scrubHoverTime = $player.duration > 0 ? fmtTime(getFrac(el, e.clientX) * $player.duration) : null;
    };
  }

  function onScrubLeave() {
    scrubHoverX = null;
    scrubHoverTime = null;
  }

  function onWindowMouseMove(e: MouseEvent) {
    if (!scrubDragging) return;
    const el = fullscreen && fsScrubEl ? fsScrubEl : scrubEl;
    if (el) player.seek(getFrac(el, e.clientX) * $player.duration);
  }

  function onVolClick(e: MouseEvent) {
    const bar = e.currentTarget as HTMLElement;
    const rect = bar.getBoundingClientRect();
    player.setVolume(Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)));
  }

  function navigateToAlbum() {
    if (album) goto(`/albums/${album.id}`);
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && fullscreen) fullscreen = false;
  }
</script>

<svelte:window
  on:mousemove={onWindowMouseMove}
  on:mouseup={() => scrubDragging = false}
  on:keydown={onKeydown}
/>

<!-- ───── Player Bar ───── -->
<div class="player-bar">
  <div class="bar-inner">

    <!-- LEFT: cover + info + fav -->
    <div class="bar-left">
      <div class="info" on:click={navigateToAlbum} role="button" tabindex="0"
           on:keydown={e => e.key === 'Enter' && navigateToAlbum()}>
        <CoverImage url={coverUrl} title={album?.title ?? ''} size={44} radius={6} />
        <div class="meta">
          <span class="track-name">{track?.name ?? 'Nothing playing'}</span>
          <span class="album-name">{album?.title ?? '—'}</span>
        </div>
      </div>
      {#if track && album}
        <button class="icon-btn star" class:active={isFav}
          on:click={toggleTrackFav} title="Favorite">
          {isFav ? '★' : '☆'}
        </button>
      {/if}
    </div>

    <!-- CENTER: transport + scrubber -->
    <div class="bar-center">
      <div class="transport">
        <button class="icon-btn indicator-btn" class:active={$player.isShuffle}
          class:mode-off={!$player.isShuffle}
          on:click={() => player.toggleShuffle()} title="Shuffle">🔀</button>
        <button class="icon-btn" on:click={playerPrev} title="Previous">⏮</button>
        <button class="play-btn" on:click={() => player.togglePlay()} title="Play/Pause">
          {#if $player.isPlaying}⏸{:else}▶{/if}
        </button>
        <button class="icon-btn" on:click={playerNext} title="Next">⏭</button>
        <button class="icon-btn indicator-btn"
          class:active={$player.repeatMode !== 'off'}
          class:mode-off={$player.repeatMode === 'off'}
          on:click={() => player.cycleRepeat()}
          title={repeatTitle}>
          {#if $player.repeatMode === 'one'}
            <span class="repeat-wrap">↻<sup class="repeat-1">1</sup></span>
          {:else}↻{/if}
        </button>
      </div>
      <div class="scrub-row">
        <span class="time-lbl">{fmtTime($player.currentTime)}</span>
        <div class="scrubber" bind:this={scrubEl}
          on:mousedown|preventDefault={onScrubDown(scrubEl)}
          on:mousemove={onScrubMove(scrubEl)}
          on:mouseleave={onScrubLeave}
          role="slider" aria-valuenow={Math.round(fraction*100)} aria-valuemin={0} aria-valuemax={100} tabindex="0">
          {#if scrubHoverTime !== null && scrubHoverX !== null}
            <div class="scrub-tip" style="left:{scrubHoverX}px">{scrubHoverTime}</div>
          {/if}
          <div class="scrub-track">
            <div class="scrub-fill" style="width:{fraction*100}%"></div>
          </div>
        </div>
        <span class="time-lbl">{fmtTime($player.duration)}</span>
      </div>
    </div>

    <!-- RIGHT: volume + queue + fullscreen -->
    <div class="bar-right">
      <div class="volume-wrap"
        on:mouseenter={() => volumeHovered = true}
        on:mouseleave={() => volumeHovered = false}>
        <button class="icon-btn" on:click={() => player.toggleMute()} title="Mute">
          {$player.isMuted || $player.volume === 0 ? '🔇' : $player.volume < 0.4 ? '🔉' : '🔊'}
        </button>
        {#if volumeHovered}
          <div class="vol-slider" on:click={onVolClick}
            role="slider" aria-valuenow={Math.round(volFrac*100)} aria-valuemin={0} aria-valuemax={100} tabindex="0">
            <div class="vol-track"><div class="vol-fill" style="width:{volFrac*100}%"></div></div>
          </div>
        {/if}
      </div>
      <button class="icon-btn" class:active={$player.showQueue}
        on:click={() => player.toggleQueue()} title="Queue">≡</button>
      <button class="icon-btn" on:click={() => fullscreen = true} title="Pantalla completa">⛶</button>
    </div>

  </div>
</div>

<!-- ───── Fullscreen Overlay ───── -->
{#if fullscreen}
  <div class="fs-overlay" role="dialog" aria-modal="true">
    {#if coverUrl}
      <div class="fs-bg" style="background-image:url('{api.coverURL(coverUrl)}')"></div>
    {/if}
    <button class="fs-close" on:click={() => fullscreen = false}>✕</button>

    <div class="fs-body">
      {#if coverUrl}
        <img class="fs-art" src={api.coverURL(coverUrl)} alt={album?.title ?? ''} />
      {:else}
        <div class="fs-art fs-art-placeholder"></div>
      {/if}
      <div class="fs-meta">
        <span class="fs-track">{track?.name ?? 'Nothing playing'}</span>
        <span class="fs-album">{album?.title ?? ''}</span>
      </div>
    </div>

    <div class="fs-controls">
      <div class="transport">
        <button class="icon-btn indicator-btn" class:active={$player.isShuffle}
          class:mode-off={!$player.isShuffle}
          on:click={() => player.toggleShuffle()} title="Shuffle">🔀</button>
        <button class="icon-btn" on:click={playerPrev} title="Previous">⏮</button>
        <button class="play-btn play-btn-lg" on:click={() => player.togglePlay()}>
          {#if $player.isPlaying}⏸{:else}▶{/if}
        </button>
        <button class="icon-btn" on:click={playerNext} title="Next">⏭</button>
        <button class="icon-btn indicator-btn"
          class:active={$player.repeatMode !== 'off'}
          class:mode-off={$player.repeatMode === 'off'}
          on:click={() => player.cycleRepeat()} title={repeatTitle}>
          {#if $player.repeatMode === 'one'}
            <span class="repeat-wrap">↻<sup class="repeat-1">1</sup></span>
          {:else}↻{/if}
        </button>
      </div>
      <div class="scrub-row fs-scrub">
        <span class="time-lbl">{fmtTime($player.currentTime)}</span>
        <div class="scrubber" bind:this={fsScrubEl}
          on:mousedown|preventDefault={onScrubDown(fsScrubEl)}
          on:mousemove={onScrubMove(fsScrubEl)}
          on:mouseleave={onScrubLeave}
          role="slider" aria-valuenow={Math.round(fraction*100)} aria-valuemin={0} aria-valuemax={100} tabindex="0">
          {#if scrubHoverTime !== null && scrubHoverX !== null}
            <div class="scrub-tip" style="left:{scrubHoverX}px">{scrubHoverTime}</div>
          {/if}
          <div class="scrub-track">
            <div class="scrub-fill" style="width:{fraction*100}%"></div>
          </div>
        </div>
        <span class="time-lbl">{fmtTime($player.duration)}</span>
      </div>
    </div>
  </div>
{/if}

<style>
  /* ── Player Bar ── */
  .player-bar {
    position: fixed;
    bottom: 0; left: 0; right: 0;
    height: var(--player-bar-h);
    background: rgba(15,15,26,0.96);
    backdrop-filter: blur(12px);
    border-top: 1px solid var(--separator);
    z-index: 100;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .bar-inner {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 0 16px;
    gap: 12px;
    height: 100%;
  }

  /* LEFT */
  .bar-left {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .info {
    display: flex;
    align-items: center;
    gap: 10px;
    cursor: pointer;
    min-width: 0;
  }
  .info:hover .meta { opacity: 0.8; }
  .meta { display: flex; flex-direction: column; min-width: 0; }
  .track-name {
    font-size: 13px; font-weight: 600;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    color: var(--text);
  }
  .album-name {
    font-size: 11px; color: var(--text-sec);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }

  /* CENTER */
  .bar-center {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    min-width: 320px;
    max-width: 560px;
  }
  .transport {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .scrub-row {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
  }
  .time-lbl {
    font-size: 11px;
    font-variant-numeric: tabular-nums;
    color: var(--text-muted);
    white-space: nowrap;
    flex-shrink: 0;
  }
  .scrubber {
    flex: 1;
    height: 16px;
    display: flex;
    align-items: center;
    cursor: pointer;
    position: relative;
  }
  .scrub-track {
    width: 100%;
    height: 4px;
    background: rgba(255,255,255,0.14);
    border-radius: 2px;
    overflow: hidden;
    transition: height 0.15s;
  }
  .scrubber:hover .scrub-track { height: 6px; }
  .scrub-fill {
    height: 100%;
    background: var(--accent);
    transition: width 0.1s linear;
  }
  .scrub-tip {
    position: absolute;
    bottom: calc(100% + 4px);
    transform: translateX(-50%);
    background: rgba(30,30,40,0.92);
    border: 1px solid var(--separator);
    color: var(--text);
    font-size: 11px;
    font-variant-numeric: tabular-nums;
    padding: 2px 6px;
    border-radius: 4px;
    pointer-events: none;
    white-space: nowrap;
    z-index: 10;
  }

  /* RIGHT */
  .bar-right {
    display: flex;
    align-items: center;
    gap: 4px;
    justify-content: flex-end;
  }
  .volume-wrap {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .vol-slider {
    width: 80px; height: 16px;
    display: flex; align-items: center;
    cursor: pointer;
  }
  .vol-track {
    width: 100%; height: 4px;
    background: rgba(255,255,255,0.12);
    border-radius: 2px; overflow: hidden;
  }
  .vol-fill { height: 100%; background: var(--accent); }

  /* Shared buttons */
  .play-btn {
    width: 40px; height: 40px;
    border-radius: 50%;
    background: white;
    color: #131320;
    font-size: 16px;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
  }
  .icon-btn {
    width: 36px; height: 36px;
    display: flex; align-items: center; justify-content: center;
    font-size: 15px;
    color: var(--text-sec);
    border-radius: var(--r-sm);
    transition: color 0.15s;
    flex-shrink: 0;
  }
  .icon-btn:hover { color: var(--text); }
  .icon-btn.active { color: var(--accent); }
  .star.active { color: var(--accent); }
  .mode-off { opacity: 0.35; }
  .mode-off:hover { opacity: 1; }

  /* Dot indicator */
  .indicator-btn { position: relative; }
  .indicator-btn::after {
    content: '';
    position: absolute;
    bottom: 3px; left: 50%; transform: translateX(-50%);
    width: 4px; height: 4px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0;
    transition: opacity 0.15s;
  }
  .indicator-btn.active::after { opacity: 1; }

  /* Repeat-one badge */
  .repeat-wrap { position: relative; display: inline-flex; }
  .repeat-1 {
    position: absolute;
    top: -4px; right: -6px;
    font-size: 8px;
    line-height: 1;
    color: var(--accent);
  }

  /* ── Fullscreen ── */
  .fs-overlay {
    position: fixed;
    inset: 0;
    z-index: 200;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-end;
    padding-bottom: 60px;
    background: rgba(8,8,18,0.92);
    overflow: hidden;
  }
  .fs-bg {
    position: absolute;
    inset: 0;
    background-size: cover;
    background-position: center;
    filter: blur(60px) brightness(0.25) saturate(1.4);
    transform: scale(1.1);
  }
  .fs-close {
    position: absolute;
    top: 20px; right: 24px;
    font-size: 18px;
    color: var(--text-muted);
    z-index: 1;
  }
  .fs-close:hover { color: var(--text); }
  .fs-body {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
    margin-bottom: 40px;
  }
  .fs-art {
    width: 240px; height: 240px;
    object-fit: cover;
    border-radius: 12px;
    box-shadow: 0 16px 48px rgba(0,0,0,0.7);
  }
  .fs-art-placeholder {
    background: var(--surface-hi);
    border-radius: 12px;
  }
  .fs-meta {
    display: flex; flex-direction: column;
    align-items: center; gap: 4px;
    text-align: center;
  }
  .fs-track {
    font-size: 20px; font-weight: 700;
    color: var(--text);
  }
  .fs-album {
    font-size: 14px; color: var(--text-sec);
  }
  .fs-controls {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    width: min(480px, 90vw);
  }
  .fs-scrub { width: 100%; }
  .play-btn-lg {
    width: 52px; height: 52px;
    font-size: 20px;
  }
</style>
