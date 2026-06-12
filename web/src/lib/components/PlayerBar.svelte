<script lang="ts">
  import { player, playerNext, playerPrev } from '$lib/stores/player';
  import { favorites } from '$lib/stores/favorites';
  import { fmtTime } from '$lib/utils';
  import CoverImage from './CoverImage.svelte';
  import { goto } from '$app/navigation';

  let volumeHovered = false;
  let scrubDragging = false;

  $: track = $player.queue[$player.queueIndex] ?? null;
  $: album = $player.currentAlbum;
  $: covers = $player.currentCovers;
  $: coverUrl = covers[$player.currentCoverIndex]?.url ?? '';
  $: isFav = track ? $favorites.some(f => f.id === track!.id) : false;

  function onScrubClick(e: MouseEvent) {
    const bar = (e.currentTarget as HTMLElement);
    const rect = bar.getBoundingClientRect();
    const frac = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    player.seek(frac * $player.duration);
  }

  function onScrubDrag(e: MouseEvent) {
    if (!scrubDragging) return;
    const bar = document.getElementById('scrub-bar')!;
    const rect = bar.getBoundingClientRect();
    const frac = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    player.seek(frac * $player.duration);
  }

  function onVolClick(e: MouseEvent) {
    const bar = (e.currentTarget as HTMLElement);
    const rect = bar.getBoundingClientRect();
    player.setVolume(Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)));
  }

  function navigateToAlbum() {
    if (album) goto(`/albums/${album.id}`);
  }

  $: repeatActive = $player.repeatMode !== 'off';
  $: fraction = $player.duration > 0 ? $player.currentTime / $player.duration : 0;
  $: volFrac = $player.isMuted ? 0 : $player.volume;
</script>

<svelte:window
  on:mousemove={onScrubDrag}
  on:mouseup={() => scrubDragging = false}
/>

<div class="player-bar">
  <!-- Scrubber -->
  <div
    id="scrub-bar"
    class="scrubber"
    on:mousedown|preventDefault={(e) => { scrubDragging = true; onScrubClick(e); }}
    on:click={onScrubClick}
    role="slider"
    aria-valuenow={Math.round(fraction * 100)}
    aria-valuemin={0}
    aria-valuemax={100}
    tabindex="0"
  >
    <div class="scrub-track">
      <div class="scrub-fill" style="width:{fraction*100}%"></div>
    </div>
  </div>

  <div class="row">
    <!-- Transport -->
    <div class="transport">
      <button class="icon-btn" on:click={playerPrev} title="Previous">⏮</button>
      <button class="play-btn" on:click={() => player.togglePlay()} title="Play/Pause">
        {#if $player.isPlaying}⏸{:else}▶{/if}
      </button>
      <button class="icon-btn" on:click={playerNext} title="Next">⏭</button>
      <span class="time">{fmtTime($player.currentTime)} / {fmtTime($player.duration)}</span>
    </div>

    <!-- Cover + info -->
    <div class="info" on:click={navigateToAlbum} role="button" tabindex="0" on:keydown={e => e.key === 'Enter' && navigateToAlbum()}>
      <CoverImage url={coverUrl} title={album?.title ?? ''} size={44} radius={6} />
      <div class="meta">
        <span class="track-name">{track?.name ?? 'Nothing playing'}</span>
        <span class="album-name">{album?.title ?? '—'}</span>
      </div>
    </div>

    <div class="spacer"></div>

    <!-- Volume -->
    <div class="volume-wrap" on:mouseenter={() => volumeHovered = true} on:mouseleave={() => volumeHovered = false}>
      {#if volumeHovered}
        <div class="vol-slider" on:click={onVolClick} role="slider" aria-valuenow={Math.round(volFrac*100)} aria-valuemin={0} aria-valuemax={100} tabindex="0">
          <div class="vol-track"><div class="vol-fill" style="width:{volFrac*100}%"></div></div>
        </div>
      {/if}
      <button class="icon-btn" on:click={() => player.toggleMute()} title="Mute">
        {$player.isMuted || $player.volume === 0 ? '🔇' : $player.volume < 0.4 ? '🔉' : '🔊'}
      </button>
    </div>

    <!-- Star -->
    {#if track && album}
      <button class="icon-btn star" class:active={isFav} on:click={() => favorites.toggle(track!, album!)} title="Favorite">
        {isFav ? '★' : '☆'}
      </button>
    {/if}

    <!-- Repeat / Shuffle / Queue -->
    <button
      class="icon-btn indicator-btn"
      class:active={repeatActive}
      class:repeat-off={!repeatActive}
      on:click={() => player.cycleRepeat()}
      title={$player.repeatMode === 'off' ? 'Repeat off' : $player.repeatMode === 'all' ? 'Repeat album' : 'Repeat track'}
    >
      {$player.repeatMode === 'one' ? '🔂' : '🔁'}
    </button>
    <button
      class="icon-btn indicator-btn"
      class:active={$player.isShuffle}
      on:click={() => player.toggleShuffle()}
      title="Shuffle"
    >🔀</button>
    <button class="icon-btn" class:active={$player.showQueue} on:click={() => player.toggleQueue()} title="Queue">≡</button>
  </div>
</div>

<style>
  .player-bar {
    position: fixed;
    bottom: 0; left: 0; right: 0;
    height: var(--player-bar-h);
    background: rgba(15,15,26,0.95);
    backdrop-filter: blur(12px);
    border-top: 1px solid var(--separator);
    display: flex;
    flex-direction: column;
    z-index: 100;
  }
  .scrubber {
    height: 4px;
    cursor: pointer;
    flex-shrink: 0;
  }
  .scrub-track {
    height: 4px;
    background: rgba(255,255,255,0.12);
    position: relative;
  }
  .scrub-fill {
    height: 100%;
    background: var(--accent);
    transition: width 0.1s linear;
  }
  .row {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 0 16px;
  }
  .transport {
    display: flex;
    align-items: center;
    gap: 2px;
  }
  .play-btn {
    width: 40px; height: 40px;
    border-radius: 50%;
    background: white;
    color: #131320;
    font-size: 16px;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0;
  }
  .time {
    font-size: 11px;
    font-variant-numeric: tabular-nums;
    color: var(--text-sec);
    margin-left: 10px;
    white-space: nowrap;
  }
  .info {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-left: 14px;
    cursor: pointer;
    min-width: 0;
    max-width: 260px;
  }
  .info:hover .meta { opacity: 0.8; }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .track-name {
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: var(--text);
  }
  .album-name {
    font-size: 11px;
    color: var(--text-sec);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .spacer { flex: 1; }
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

  /* Dot indicator below icon when active */
  .indicator-btn { position: relative; flex-direction: column; gap: 0; }
  .indicator-btn::after {
    content: '';
    position: absolute;
    bottom: 3px;
    left: 50%; transform: translateX(-50%);
    width: 4px; height: 4px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0;
    transition: opacity 0.15s;
  }
  .indicator-btn.active::after { opacity: 1; }

  /* Dim when repeat/shuffle is off */
  .repeat-off { opacity: 0.35; }
  .repeat-off:hover { opacity: 1; }
  .volume-wrap {
    display: flex;
    align-items: center;
    gap: 6px;
    position: relative;
  }
  .vol-slider {
    width: 80px;
    height: 16px;
    display: flex;
    align-items: center;
    cursor: pointer;
  }
  .vol-track {
    width: 100%;
    height: 4px;
    background: rgba(255,255,255,0.12);
    border-radius: 2px;
    overflow: hidden;
  }
  .vol-fill {
    height: 100%;
    background: var(--accent);
  }
</style>
