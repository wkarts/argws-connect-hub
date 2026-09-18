/* Native HTML dialog, no external dependency and no browser alert/confirm. */
(() => {
  if (window.__hubOperationsLoaded) return;
  window.__hubOperationsLoaded = true;
  const approved = new WeakSet();
  document.addEventListener('submit', event => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    const button = event.submitter;
    const text = button?.dataset.hubConfirm || form.dataset.hubConfirm;
    if (approved.has(form)) { approved.delete(form); return; }
    if (!text) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const dialog = document.createElement('dialog');
    dialog.className = 'hub-ops hub-ops-dialog';
    dialog.setAttribute('aria-label', 'Confirmar operação');
    const title = document.createElement('h2'); title.textContent = 'Confirmar operação';
    const description = document.createElement('p'); description.textContent = text;
    const actions = document.createElement('div'); actions.className = 'hub-ops-toolbar';
    const cancel = document.createElement('button'); cancel.type = 'button'; cancel.textContent = 'Cancelar';
    const accept = document.createElement('button'); accept.type = 'button'; accept.className = 'hub-primary'; accept.textContent = 'Confirmar';
    const required = button?.dataset.hubConfirmValue || form.dataset.hubConfirmValue;
    dialog.append(title, description);
    if (required) {
      const label = document.createElement('label'); label.textContent = `Digite ${required} para confirmar`;
      const input = document.createElement('input'); input.type = 'text'; input.autocomplete = 'off';
      label.append(input); dialog.append(label); accept.disabled = true;
      input.addEventListener('input', () => { accept.disabled = input.value !== required; });
    }
    actions.append(cancel, accept); dialog.append(actions); document.body.append(dialog);
    cancel.addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => { dialog.remove(); button?.focus(); }, { once: true });
    accept.addEventListener('click', () => {
      approved.add(form); dialog.close(); form.requestSubmit(button || undefined);
    }, { once: true });
    if (typeof dialog.showModal === 'function') {
      dialog.showModal(); cancel.focus();
    } else {
      dialog.setAttribute('open', '');
      accept.disabled = true;
      description.textContent = 'Atualize o navegador para confirmar esta operação com segurança.';
      cancel.addEventListener('click', () => dialog.remove(), { once: true });
    }
  }, true);
})();
