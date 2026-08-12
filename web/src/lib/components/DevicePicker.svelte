<script lang="ts">
  import {
    devices, otherDevices, activeDeviceId, deviceId, transferTo, connected,
  } from '$lib/stores/connect';

  let open = false;

  function icon(type: string): string {
    return type === 'macos' ? '🖥' : type === 'tv' ? '📺' : '🌐';
  }

  function pick(id: string) {
    open = false;
    transferTo(id, true);
  }

  function label(d: { id: string; name: string }): string {
    return d.id === deviceId ? `${d.name} — esta pestaña` : d.name;
  }
</script>

<!-- A lone device has nothing to connect to, so the control stays hidden rather
     than offering a menu with one dead entry. -->
{#if $otherDevices.length > 0}
  <div class="picker-wrap">
    <button
      class="icon-btn"
      class:active={$activeDeviceId !== '' && $activeDeviceId !== deviceId}
      on:click={() => (open = !open)}
      title="Dispositivos"
      aria-haspopup="menu"
      aria-expanded={open}
    >⧉</button>

    {#if open}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="backdrop" on:click={() => (open = false)}></div>
      <div class="popover" role="menu">
        <div class="head">
          Dispositivos
          {#if !$connected}<span class="offline">sin conexión</span>{/if}
        </div>
        {#each $devices as d (d.id)}
          <button class="row" class:is-active={d.isActive} role="menuitem" on:click={() => pick(d.id)}>
            <span class="dot">{d.isActive ? '●' : '○'}</span>
            <span class="ico">{icon(d.type)}</span>
            <span class="name">{label(d)}</span>
            {#if d.isActive}<span class="tag">sonando</span>{/if}
          </button>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .picker-wrap { position: relative; display: inline-flex; }

  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
  }

  .popover {
    position: absolute;
    bottom: calc(100% + 10px);
    right: 0;
    z-index: 41;
    min-width: 240px;
    padding: 6px;
    background: var(--surface);
    border: 1px solid var(--border60);
    border-radius: var(--r-lg);
    box-shadow: 0 12px 32px var(--shadow);
  }

  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    padding: 6px 10px 8px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
  }

  .offline { text-transform: none; letter-spacing: 0; color: var(--red); }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 8px 10px;
    border: 0;
    border-radius: var(--r-sm);
    background: transparent;
    color: var(--text);
    font: inherit;
    font-size: 13px;
    text-align: left;
    cursor: pointer;
  }

  .row:hover { background: var(--hover-md); }
  .row.is-active { color: var(--accent); }

  .dot { width: 10px; font-size: 10px; }
  .ico { width: 18px; }
  .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tag { font-size: 10px; color: var(--accent); }
</style>
