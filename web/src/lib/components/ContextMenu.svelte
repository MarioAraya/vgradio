<script lang="ts">
  import { onMount, onDestroy } from 'svelte';

  export let x = 0;
  export let y = 0;
  export let onClose: () => void;

  let menuEl: HTMLDivElement;

  function handlePointerDown(e: PointerEvent) {
    if (menuEl && !menuEl.contains(e.target as Node)) onClose();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') onClose();
  }

  onMount(() => {
    // Capture phase + next tick so the click that opened the menu doesn't also close it.
    setTimeout(() => {
      window.addEventListener('pointerdown', handlePointerDown, true);
      window.addEventListener('keydown', handleKeydown, true);
    }, 0);
  });

  onDestroy(() => {
    window.removeEventListener('pointerdown', handlePointerDown, true);
    window.removeEventListener('keydown', handleKeydown, true);
  });
</script>

<div class="menu" bind:this={menuEl} style="left:{x}px; top:{y}px;" role="menu">
  <slot />
</div>

<style>
  .menu {
    position: fixed;
    z-index: 1000;
    min-width: 180px;
    padding: 4px;
    background: var(--surface, #1a1a20);
    border: 1px solid var(--separator, var(--hover-hi));
    border-radius: 8px;
    box-shadow: 0 8px 24px var(--shadow);
  }
  .menu :global(button) {
    display: flex; align-items: center; gap: 8px;
    width: 100%;
    padding: 7px 10px;
    background: none; border: none;
    font-size: 13px;
    color: var(--text, #eee);
    text-align: left;
    border-radius: 5px;
    cursor: pointer;
  }
  .menu :global(button:hover) {
    background: var(--hover-md);
  }
  .menu :global(.divider) {
    height: 1px;
    margin: 4px 6px;
    background: var(--separator, var(--hover-hi));
  }
</style>
