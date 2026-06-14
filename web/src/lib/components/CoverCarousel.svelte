<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import CoverImage from './CoverImage.svelte';

  export let covers: { url: string }[] = [];
  export let index: number = 0;
  export let size: number = 220;

  const dispatch = createEventDispatcher<{ change: number; open: number }>();

  let swipeStartX = 0;

  function prev() {
    if (index > 0) { index--; dispatch('change', index); }
  }
  function next() {
    if (index < covers.length - 1) { index++; dispatch('change', index); }
  }

  function onPointerDown(e: PointerEvent) { swipeStartX = e.clientX; }
  function onPointerUp(e: PointerEvent) {
    const dx = e.clientX - swipeStartX;
    if (Math.abs(dx) < 5) {
      dispatch('open', index);
      return;
    }
    if (dx > 50) prev();
    else if (dx < -50) next();
  }
</script>

<div class="carousel" style="--sz: {size}px">
  <div
    class="img-wrap"
    on:pointerdown={onPointerDown}
    on:pointerup={onPointerUp}
    role="button"
    tabindex="0"
    aria-label="Open cover fullscreen"
    on:keydown={(e) => e.key === 'Enter' && dispatch('open', index)}
  >
    <CoverImage url={covers[index]?.url ?? ''} title="" {size} radius={10} />

    {#if covers.length > 1}
      <button
        class="nav-btn left"
        on:click|stopPropagation={prev}
        on:pointerdown|stopPropagation
        on:pointerup|stopPropagation
        disabled={index === 0}
        tabindex="-1"
        aria-label="Previous cover"
      >‹</button>
      <button
        class="nav-btn right"
        on:click|stopPropagation={next}
        on:pointerdown|stopPropagation
        on:pointerup|stopPropagation
        disabled={index === covers.length - 1}
        tabindex="-1"
        aria-label="Next cover"
      >›</button>
    {/if}
  </div>

  {#if covers.length > 1}
    <div class="dots">
      {#each covers as _, i}
        <button
          class="dot"
          class:active={i === index}
          on:click={() => { index = i; dispatch('change', i); }}
          aria-label="Cover {i + 1}"
        ></button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .carousel {
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
    flex-shrink: 0;
  }
  .img-wrap {
    position: relative;
    width: var(--sz);
    height: var(--sz);
    cursor: pointer;
    border-radius: 10px;
    overflow: hidden;
    user-select: none;
    touch-action: pan-y;
  }
  .img-wrap:focus { outline: 2px solid var(--accent); }

  .nav-btn {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 36px; height: 36px;
    background: rgba(0,0,0,0.45);
    backdrop-filter: blur(4px);
    border-radius: 50%;
    font-size: 22px;
    color: white;
    display: flex; align-items: center; justify-content: center;
    opacity: 0;
    transition: opacity 0.15s;
    z-index: 2;
    line-height: 1;
  }
  .img-wrap:hover .nav-btn { opacity: 1; }
  .nav-btn:disabled { opacity: 0 !important; }
  .nav-btn.left { left: 6px; }
  .nav-btn.right { right: 6px; }

  .dots {
    display: flex;
    gap: 6px;
    justify-content: center;
  }
  .dot {
    width: 7px; height: 7px;
    border-radius: 50%;
    background: var(--text-muted);
    transition: background 0.15s;
  }
  .dot.active { background: var(--accent); }
</style>
