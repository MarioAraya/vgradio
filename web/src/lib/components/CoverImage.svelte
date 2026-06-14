<script lang="ts">
  import { api } from '$lib/api';
  import { letterGradient } from '$lib/utils';

  export let url: string = '';
  export let title: string = '';
  export let size: number = 44;
  export let radius: number = 6;

  let error = false;
  $: resolvedUrl = url ? api.coverURL(url) : '';
  $: error = false, resolvedUrl; // reset on url change
</script>

{#if resolvedUrl && !error}
  <img
    src={resolvedUrl}
    alt={title}
    width={size}
    height={size}
    style="width:{size}px;height:{size}px;border-radius:{radius}px;object-fit:cover;display:block;"
    on:error={() => error = true}
  />
{:else}
  <div class="fallback" style="width:{size}px;height:{size}px;border-radius:{radius}px;background:{letterGradient(title)};font-size:{size*0.42}px;">
    {title.charAt(0).toUpperCase() || '?'}
  </div>
{/if}

<style>
  .fallback {
    display: flex;
    align-items: center;
    justify-content: center;
    color: rgba(255,255,255,0.9);
    font-weight: 700;
    flex-shrink: 0;
  }
</style>
