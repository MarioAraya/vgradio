<script lang="ts">
  import { player } from '$lib/stores/player';
  import { fmtTime } from '$lib/utils';

  let dragFrom: number | null = null;

  function onDragStart(i: number) { dragFrom = i; }
  function onDrop(i: number) {
    if (dragFrom !== null && dragFrom !== i) player.moveInQueue(dragFrom, i);
    dragFrom = null;
  }
</script>

{#if $player.showQueue}
  <div class="panel">
    <div class="header">
      <span>Queue ({$player.queue.length})</span>
      <button on:click={() => player.toggleQueue()}>✕</button>
    </div>
    <div class="list">
      {#each $player.queue as track, i (i)}
        <div
          class="row"
          class:current={i === $player.queueIndex}
          draggable="true"
          on:dragstart={() => onDragStart(i)}
          on:dragover|preventDefault
          on:drop={() => onDrop(i)}
          role="listitem"
        >
          <span class="num">{i + 1}</span>
          <button class="play-row" on:click={() => {
            const s = $player;
            if (s.currentAlbum) player.play(track, s.currentAlbum, s.queue, s.currentCovers);
          }}>{track.name}</button>
          <span class="dur">{fmtTime(track.durationSec)}</span>
          <button class="rm" on:click={() => player.removeFromQueue(i)}>✕</button>
        </div>
      {/each}
    </div>
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
  }
  .list {
    overflow-y: auto;
    flex: 1;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 10px;
    border-bottom: 1px solid var(--border60);
  }
  .row.current { background: var(--accent-bg); }
  .row:hover .rm { opacity: 1; }
  .num { font-size: 10px; color: var(--text-muted); width: 20px; text-align: right; flex-shrink: 0; }
  .play-row {
    flex: 1;
    text-align: left;
    font-size: 12px;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .play-row:hover { color: var(--accent); }
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
