<script lang="ts">
  import { toasts } from '$lib/stores/toasts';
</script>

<div class="toast-container">
  {#each $toasts as t (t.id)}
    <div class="toast" class:error={t.type === 'error'}>
      {t.message}
    </div>
  {/each}
</div>

<style>
  .toast-container {
    position: fixed;
    bottom: calc(var(--player-bar-h) + 12px);
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
    z-index: 2000;
    pointer-events: none;
  }
  .toast {
    padding: 9px 18px;
    background: var(--surface-hi);
    border: 1px solid var(--separator);
    border-radius: 20px;
    font-size: 13px;
    color: var(--text);
    white-space: nowrap;
    animation: fadein 0.2s ease;
  }
  .toast.error {
    background: #3a1a1a;
    border-color: #7a3030;
    color: #f87171;
  }
  @keyframes fadein {
    from { opacity: 0; transform: translateY(6px); }
    to   { opacity: 1; transform: translateY(0); }
  }
</style>
