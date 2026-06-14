<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { api } from '$lib/api';
  import { currentUser } from '$lib/stores/auth';
  import { addToast } from '$lib/stores/toasts';

  export let open = false;

  const dispatch = createEventDispatcher<{ done: void }>();

  let tab: 'login' | 'register' = 'login';
  let loading = false;
  let error = '';

  // login
  let loginEmail = '';
  let loginPassword = '';

  // register
  let regUsername = '';
  let regEmail = '';
  let regPassword = '';

  function close() {
    open = false;
    error = '';
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
  }

  async function submitLogin() {
    error = '';
    loading = true;
    try {
      const user = await api.login(loginEmail, loginPassword);
      currentUser.set(user);
      close();
      dispatch('done');
    } catch (e) {
      error = e instanceof Error ? e.message : 'Error al iniciar sesión';
    } finally {
      loading = false;
    }
  }

  async function submitRegister() {
    error = '';
    loading = true;
    try {
      const user = await api.register(regUsername, regEmail, regPassword);
      currentUser.set(user);
      close();
      dispatch('done');
      addToast(`Bienvenido, @${user.username}!`);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Error al crear cuenta';
    } finally {
      loading = false;
    }
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
  <div class="overlay" on:click|self={close}>
    <div class="modal" role="dialog" aria-modal="true">
      <button class="close-btn" on:click={close}>✕</button>

      <div class="tabs">
        <button class="tab" class:active={tab === 'login'} on:click={() => { tab = 'login'; error = ''; }}>
          Iniciar sesión
        </button>
        <button class="tab" class:active={tab === 'register'} on:click={() => { tab = 'register'; error = ''; }}>
          Crear cuenta
        </button>
      </div>

      {#if tab === 'login'}
        <form on:submit|preventDefault={submitLogin} class="form">
          <label>
            Email
            <input type="email" bind:value={loginEmail} required autocomplete="email" />
          </label>
          <label>
            Contraseña
            <input type="password" bind:value={loginPassword} required autocomplete="current-password" />
          </label>
          {#if error}<p class="err">{error}</p>{/if}
          <button type="submit" class="submit-btn" disabled={loading}>
            {loading ? 'Entrando…' : 'Entrar'}
          </button>
        </form>

      {:else}
        <form on:submit|preventDefault={submitRegister} class="form">
          <label>
            Usuario
            <input type="text" bind:value={regUsername} required minlength="3" maxlength="30"
              placeholder="min 3 chars, letras/números/-/_" autocomplete="username" />
          </label>
          <label>
            Email
            <input type="email" bind:value={regEmail} required autocomplete="email" />
          </label>
          <label>
            Contraseña
            <input type="password" bind:value={regPassword} required minlength="8"
              placeholder="mínimo 8 caracteres" autocomplete="new-password" />
          </label>
          {#if error}<p class="err">{error}</p>{/if}
          <button type="submit" class="submit-btn" disabled={loading}>
            {loading ? 'Creando cuenta…' : 'Crear cuenta'}
          </button>
        </form>
      {/if}
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 3000;
  }
  .modal {
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-lg, 12px);
    padding: 28px 28px 24px;
    width: 340px;
    position: relative;
  }
  .close-btn {
    position: absolute;
    top: 12px;
    right: 14px;
    font-size: 14px;
    color: var(--text-muted);
  }
  .close-btn:hover { color: var(--text); }
  .tabs {
    display: flex;
    gap: 4px;
    margin-bottom: 20px;
    border-bottom: 1px solid var(--separator);
    padding-bottom: 0;
  }
  .tab {
    padding: 8px 14px;
    font-size: 13px;
    font-weight: 500;
    color: var(--text-muted);
    border-bottom: 2px solid transparent;
    margin-bottom: -1px;
  }
  .tab.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
    font-weight: 600;
  }
  .form {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 5px;
    font-size: 12px;
    color: var(--text-muted);
    font-weight: 500;
  }
  input {
    background: var(--surface-hi, rgba(255,255,255,0.06));
    border: 1px solid var(--separator);
    border-radius: var(--r-sm, 6px);
    padding: 8px 10px;
    font-size: 13px;
    color: var(--text);
    outline: none;
    width: 100%;
  }
  input:focus { border-color: var(--accent); }
  .err {
    font-size: 12px;
    color: var(--red, #f87171);
    margin: -4px 0;
  }
  .submit-btn {
    margin-top: 4px;
    padding: 9px;
    background: var(--accent);
    color: #131320;
    border-radius: var(--r-sm, 6px);
    font-size: 13px;
    font-weight: 700;
    transition: opacity 0.1s;
  }
  .submit-btn:disabled { opacity: 0.6; cursor: default; }
  .submit-btn:not(:disabled):hover { opacity: 0.9; }
</style>
