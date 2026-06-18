<script lang="ts">
  import { player } from '$lib/stores/player';
  import { fmtTime } from '$lib/utils';

  let dragFrom: number | null = null;
  let dropTarget: number | null = null;
  let collapsed = false;

  function onDragStart(i: number) { dragFrom = i; }

  function onDragOver(e: DragEvent, i: number) {
    e.preventDefault();
    const el = e.currentTarget as HTMLElement;
    const rect = el.getBoundingClientRect();
    dropTarget = e.clientY < rect.top + rect.height / 2 ? i : i + 1;
  }

  function onDragEnd() { dragFrom = null; dropTarget = null; }

  function onDrop(e: DragEvent, i: number) {
    e.preventDefault();
    if (dragFrom !== null && dropTarget !== null) {
      let target = dropTarget;
      if (dragFrom < target) target--;
      if (target !== dragFrom) player.moveInQueue(dragFrom, target);
    }
    dragFrom = null;
    dropTarget = null;
  }

  $: q = $player.queue;
</script>

{#if $player.showQueue}
  <div class="panel" on:dragend={onDragEnd}>
    <button class="header" on:click={() => collapsed = !collapsed}>
      <span>Queue ({q.length})</span>
      <span class="chevron">{collapsed ? '▸' : '▾'}</span>
    </button>
    {#if !collapsed}
      <div class="list">
        {#each q as track, i (i)}
          <div
            class="row"
            class:current={i === $player.queueIndex}
            class:drop-above={dropTarget === i && dragFrom !== i && dragFrom !== i - 1}
            class:drop-below={dropTarget === i + 1 && i === q.length - 1 && dragFrom !== i}
            draggable="true"
            on:dragstart={() => onDragStart(i)}
            on:dragover={(e) => onDragOver(e, i)}
            on:drop={(e) => onDrop(e, i)}
            role="listitem"
          >
            <span class="num">{i + 1}</span>
            <button class="play-row" on:click={() => {
              const s = $player;
              if (s.currentAlbum) player.play(track, s.currentAlbum, s.queue, s.currentCovers);
            }}>
              <span class="track-name">{track.name}</span>
              {#if $player.currentAlbum}
                <span class="album-name">{$player.currentAlbum.title}</span>
              {/if}
            </button>
            <span class="dur">{fmtTime(track.durationSec)}</span>
            <button class="rm" on:click={() => player.removeFromQueue(i)}>✕</button>
          </div>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .panel {
    position: fixed;
    bottom: calc(var(--player-bar-h) + 8px);
    right: 12px;
    width: 320px;
    max-height: 420px;
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-lg);
    display: flex;
    flex-direction: column;
    z-index: 200;
    overflow: hidden;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 14px;
    border-bottom: 1px solid var(--separator);
    font-size: 12px;
    font-weight: 600;
    color: var(--text-sec);
    cursor: pointer;
    width: 100%;
    text-align: left;
    transition: color 0.1s;
  }
  .header:hover { color: var(--text); }
  .chevron { font-size: 12px; color: var(--text-muted); }
  .list {
    overflow-y: auto;
    flex: 1;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 7px 10px;
    border-top: 2px solid transparent;
    border-bottom: 2px solid transparent;
    transition: background 0.1s;
  }
  .row.current {
    background: rgba(203, 168, 39, 0.18);
    border-left: 2px solid var(--accent);
  }
  .row:hover .rm { opacity: 1; }
  .row.drop-above { border-top-color: var(--accent); }
  .row.drop-below { border-bottom-color: var(--accent); }
  .num { font-size: 10px; color: var(--text-muted); width: 20px; text-align: right; flex-shrink: 0; }
  .row.current .num { color: var(--accent); }
  .play-row {
    flex: 1;
    text-align: left;
    display: flex;
    flex-direction: column;
    gap: 1px;
    overflow: hidden;
  }
  .track-name {
    font-size: 12px;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .album-name {
    font-size: 10px;
    color: var(--text-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .row.current .track-name { color: var(--accent); font-weight: 600; }
  .play-row:hover .track-name { color: var(--accent); }
  .dur { font-size: 11px; color: var(--text-muted); flex-shrink: 0; }
  .rm {
    font-size: 11px;
    color: var(--text-muted);
    opacity: 0;
    transition: opacity 0.15s;
    flex-shrink: 0;
    width: 20px;
  }
  .rm:hover { color: var(--red); }
</style>
