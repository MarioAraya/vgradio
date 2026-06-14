<script lang="ts">
  import { currentUser, logout } from '$lib/stores/auth';
  import { api } from '$lib/api';

  export let onLogin: () => void = () => {};

  let open = false;

  function toggle() { open = !open; }

  function onOutsideClick(e: MouseEvent) {
    if (!(e.target as HTMLElement).closest('.user-menu')) open = false;
  }

  async function handleLogout() {
    open = false;
    await logout(api.baseURL());
  }
</script>

<svelte:window on:click={onOutsideClick} />

<div class="user-menu">
  {#if $currentUser}
    <button class="user-btn" on:click={toggle}>
      <span class="avatar">{$currentUser.username[0].toUpperCase()}</span>
      <span class="username">@{$currentUser.username}</span>
      <span class="caret">{open ? '▴' : '▾'}</span>
    </button>
    {#if open}
      <div class="dropdown">
        <div class="dropdown-email">{$currentUser.email}</div>
        <button class="dropdown-item logout" on:click={handleLogout}>Cerrar sesión</button>
      </div>
    {/if}
  {:else}
    <button class="login-btn" on:click={onLogin}>Entrar</button>
  {/if}
</div>

<style>
  .user-menu { position: relative; }

  .user-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 8px;
    border-radius: var(--r-md, 8px);
    font-size: 12px;
    color: var(--text-sec);
    width: 100%;
  }
  .user-btn:hover { background: rgba(255,255,255,0.05); color: var(--text); }

  .avatar {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--accent-soft);
    color: var(--accent);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    flex-shrink: 0;
  }
  .username {
    flex: 1;
    text-align: left;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
    color: var(--text);
  }
  .caret { font-size: 9px; color: var(--text-muted); }

  .dropdown {
    position: absolute;
    bottom: calc(100% + 4px);
    left: 0;
    right: 0;
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-md, 8px);
    overflow: hidden;
    z-index: 100;
    box-shadow: 0 4px 16px rgba(0,0,0,0.4);
  }
  .dropdown-email {
    padding: 8px 12px;
    font-size: 11px;
    color: var(--text-muted);
    border-bottom: 1px solid var(--separator);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dropdown-item {
    display: block;
    width: 100%;
    text-align: left;
    padding: 8px 12px;
    font-size: 13px;
    color: var(--text);
  }
  .dropdown-item:hover { background: rgba(255,255,255,0.05); }
  .logout { color: var(--red, #f87171); }
  .logout:hover { background: rgba(248,113,113,0.1); }

  .login-btn {
    width: 100%;
    padding: 8px 12px;
    background: var(--accent-soft);
    color: var(--accent);
    border-radius: var(--r-md, 8px);
    font-size: 13px;
    font-weight: 600;
    transition: background 0.15s;
  }
  .login-btn:hover { background: rgba(203,168,39,0.18); }
</style>
