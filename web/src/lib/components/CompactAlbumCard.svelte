<script lang="ts">
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from './CoverImage.svelte';
  import { fmtDuration } from '$lib/utils';

  export let album: AlbumSummary;

  let showTooltip = false;
  let hoverTimer: ReturnType<typeof setTimeout> | null = null;

  function onEnter() {
    hoverTimer = setTimeout(() => { showTooltip = true; }, 80);
  }
  function onLeave() {
    if (hoverTimer) clearTimeout(hoverTimer);
    showTooltip = false;
  }
</script>

<div
  class="compact-card"
  on:mouseenter={onEnter}
  on:mouseleave={onLeave}
  on:click
  role="button"
  tabindex="0"
  on:keydown
>
  <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={160} radius={8} />

  {#if showTooltip}
    <div class="tooltip">
      <div class="tooltip-title-row">
        <span class="tooltip-title">{album.title}</span>
        {#if album.isFavorite}<span class="tooltip-star">★</span>{/if}
      </div>
      <span class="tooltip-sub">
        {album.platform || album.albumType}{album.year ? `  ·  ${album.year}` : ''}{album.totalDurationSec ? `  ·  ${fmtDuration(album.totalDurationSec)}` : ''}
      </span>
    </div>
  {/if}
</div>

<style>
  .compact-card { position: relative; cursor: pointer; border-radius: 8px; overflow: visible; }
  .tooltip {
    position: absolute;
    top: -8px;
    left: 50%;
    transform: translate(-50%, -100%);
    background: rgba(0,0,0,0.9);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 6px;
    padding: 6px 8px;
    white-space: nowrap;
    z-index: 10;
    pointer-events: none;
  }
  .tooltip-title-row { display: flex; align-items: center; gap: 4px; }
  .tooltip-title { font-size: 12px; font-weight: 600; color: var(--text); }
  .tooltip-star { font-size: 10px; color: var(--accent); }
  .tooltip-sub { font-size: 10px; color: var(--text-sec); }
</style>
