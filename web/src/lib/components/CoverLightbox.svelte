<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { api } from '$lib/api';

  export let covers: { url: string }[] = [];
  export let index: number = 0;
  export let open: boolean = false;

  const dispatch = createEventDispatcher<{ close: void; change: number }>();

  function origURL(url: string): string {
    return url.replace(/(cover_\d+)(\.[^.]+)$/, '$1_orig$2');
  }

  // Always show display version immediately; upgrade to orig in background
  let displayedURL = '';

  $: {
    const url = covers[index]?.url ?? '';
    if (url) {
      const display = api.coverURL(url);
      displayedURL = display; // show display immediately — no blank flash
      const orig = api.coverURL(origURL(url));
      if (orig !== display) {
        const probe = new Image();
        probe.onload = () => { displayedURL = orig; };
        probe.src = orig;
      }
    } else {
      displayedURL = '';
    }
  }

  function prev() {
    if (index > 0) { index--; dispatch('change', index); }
  }
  function next() {
    if (index < covers.length - 1) { index++; dispatch('change', index); }
  }

  // Keyboard nav
  function onKeydown(e: KeyboardEvent) {
    if (!open) return;
    if (e.key === 'Escape') { dispatch('close'); }
    if (e.key === 'ArrowLeft') prev();
    if (e.key === 'ArrowRight') next();
  }

  // Swipe
  let swipeStartX = 0;
  function onPointerDown(e: PointerEvent) { swipeStartX = e.clientX; }
  function onPointerUp(e: PointerEvent) {
    const dx = e.clientX - swipeStartX;
    if (dx > 50) prev();
    else if (dx < -50) next();
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <!-- svelte-ignore a11y-no-static-element-interactions -->
  <div class="overlay" on:click|self={() => dispatch('close')}>
    <div
      class="stage"
      on:pointerdown={onPointerDown}
      on:pointerup={onPointerUp}
      role="dialog"
      aria-modal="true"
    >
      {#if covers.length > 1}
        <button class="nav-btn left" on:click|stopPropagation={prev} disabled={index === 0} aria-label="Previous cover">‹</button>
      {/if}

      <div class="img-wrap">
        <img
          src={displayedURL}
          alt="Cover {index + 1}"
          class="cover-img"
          draggable="false"
        />
      </div>

      {#if covers.length > 1}
        <button class="nav-btn right" on:click|stopPropagation={next} disabled={index === covers.length - 1} aria-label="Next cover">›</button>
      {/if}

      <button class="close-btn" on:click={() => dispatch('close')} aria-label="Close">✕</button>

      {#if covers.length > 1}
        <div class="dots">
          {#each covers as _, i}
            <button
              class="dot"
              class:active={i === index}
              on:click|stopPropagation={() => { index = i; dispatch('change', i); }}
              aria-label="Cover {i + 1}"
            ></button>
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.88);
    display: flex; align-items: center; justify-content: center;
    z-index: 1000;
  }
  .stage {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    max-width: 90vw;
    max-height: 90vh;
    user-select: none;
    touch-action: pan-y;
  }
  .img-wrap {
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .cover-img {
    max-width: min(80vw, 800px);
    max-height: 80vh;
    object-fit: contain;
    border-radius: 6px;
    display: block;
    pointer-events: none;
  }
  .nav-btn {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 48px; height: 48px;
    background: rgba(255,255,255,0.12);
    backdrop-filter: blur(4px);
    border-radius: 50%;
    font-size: 28px;
    color: white;
    display: flex; align-items: center; justify-content: center;
    transition: background 0.15s, opacity 0.15s;
    z-index: 10;
    line-height: 1;
  }
  .nav-btn:hover { background: rgba(255,255,255,0.22); }
  .nav-btn:disabled { opacity: 0.2; cursor: default; }
  .nav-btn.left { left: -60px; }
  .nav-btn.right { right: -60px; }
  .close-btn {
    position: fixed;
    top: 20px; right: 24px;
    width: 36px; height: 36px;
    background: rgba(255,255,255,0.1);
    border-radius: 50%;
    color: white;
    font-size: 16px;
    display: flex; align-items: center; justify-content: center;
    transition: background 0.15s;
  }
  .close-btn:hover { background: rgba(255,255,255,0.2); }
  .dots {
    position: absolute;
    bottom: -32px;
    left: 50%; transform: translateX(-50%);
    display: flex; gap: 8px;
  }
  .dot {
    width: 8px; height: 8px;
    border-radius: 50%;
    background: rgba(255,255,255,0.3);
    transition: background 0.15s;
  }
  .dot.active { background: white; }
</style>
