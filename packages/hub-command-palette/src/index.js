class HubCommandPalette extends HTMLElement {
  constructor() {
    super();
    this._data = [];
    this._parent = null;
    this._query = '';
    this._selectedIndex = 0;
    this.attachShadow({ mode: 'open' });
    this.render();
    this.handleGlobalKeydown = this.handleGlobalKeydown.bind(this);
  }

  connectedCallback() {
    window.addEventListener('keydown', this.handleGlobalKeydown);
  }

  disconnectedCallback() {
    window.removeEventListener('keydown', this.handleGlobalKeydown);
  }

  set data(value) {
    this._data = Array.isArray(value) ? value : [];
    this.render();
  }

  get data() {
    return this._data;
  }

  get visibleActions() {
    const q = this._query.trim().toLowerCase();
    return this._data.filter(action => {
      const parentMatches = this._parent ? action.parent === this._parent : !action.parent;
      if (!parentMatches) return false;
      if (!q) return true;
      return `${action.title || ''} ${action.section || ''}`.toLowerCase().includes(q);
    });
  }

  open(options = {}) {
    this._parent = options?.parent || null;
    this._query = '';
    this._selectedIndex = 0;
    this.setAttribute('open', '');
    this.render();
    queueMicrotask(() => this.shadowRoot?.querySelector('input')?.focus());
  }

  close() {
    if (!this.hasAttribute('open')) return;
    this.removeAttribute('open');
    this._parent = null;
    this._query = '';
    this.render();
    this.dispatchEvent(new CustomEvent('closed', { bubbles: true, composed: true }));
  }

  handleGlobalKeydown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      this.open();
      return;
    }
    if (!this.hasAttribute('open')) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      if (this._parent) {
        this._parent = null;
        this._query = '';
        this.render();
      } else {
        this.close();
      }
    }
  }

  activate(action) {
    if (!action) return;
    if (Array.isArray(action.children) && action.children.length) {
      this._parent = action.id;
      this._query = '';
      this._selectedIndex = 0;
      this.render();
      queueMicrotask(() => this.shadowRoot?.querySelector('input')?.focus());
      return;
    }
    try {
      action.handler?.(action);
    } finally {
      this.dispatchEvent(
        new CustomEvent('selected', {
          detail: { action },
          bubbles: true,
          composed: true,
        })
      );
      this.close();
    }
  }

  render() {
    if (!this.shadowRoot) return;
    const actions = this.visibleActions;
    this.shadowRoot.innerHTML = `
      <style>
        :host{font-family:var(--hub-command-font-family,system-ui,sans-serif);position:fixed;inset:0;display:none;z-index:9999}
        :host([open]){display:block}
        .overlay{position:absolute;inset:0;background:var(--hub-command-overflow-background,rgba(15,23,42,.42));display:flex;justify-content:center;align-items:flex-start;padding-top:min(18vh,160px)}
        .panel{width:min(680px,calc(100vw - 32px));max-height:min(68vh,640px);overflow:hidden;background:var(--hub-command-modal-background,#fff);color:var(--hub-command-text-color,#111827);border-radius:14px;box-shadow:0 24px 70px rgba(0,0,0,.25);border:1px solid rgba(148,163,184,.25)}
        .search{display:flex;gap:8px;align-items:center;padding:12px;border-bottom:1px solid rgba(148,163,184,.2)}
        input{width:100%;border:0;outline:0;background:transparent;color:inherit;font:inherit;font-size:15px}
        .back{border:0;background:transparent;color:var(--hub-command-secondary-text-color,#64748b);cursor:pointer;font-size:18px}
        .list{max-height:52vh;overflow:auto;padding:8px}
        button.action{width:100%;display:flex;align-items:center;justify-content:space-between;text-align:left;border:0;background:transparent;color:inherit;padding:10px 12px;border-radius:9px;cursor:pointer}
        button.action:hover,button.action.active{background:var(--hub-command-selected-background,#f1f5f9)}
        .content{display:flex;align-items:center;gap:10px;min-width:0}.icon{display:inline-flex;flex:0 0 auto;color:var(--hub-command-icon-color,currentColor)}.copy{min-width:0}.title{font-size:14px;font-weight:600}.section{font-size:11px;color:var(--hub-command-secondary-text-color,#64748b);margin-top:2px}.chev{opacity:.55}.empty{padding:24px;text-align:center;color:var(--hub-command-secondary-text-color,#64748b)}
      </style>
      <div class="overlay" part="overlay">
        <div class="panel" role="dialog" aria-modal="true">
          <div class="search">
            ${this._parent ? '<button class="back" type="button" aria-label="Voltar">←</button>' : ''}
            <input type="search" autocomplete="off" placeholder="${this.getAttribute('placeholder') || 'Buscar comando'}" value="${this._query.replace(/"/g, '&quot;')}" />
          </div>
          <div class="list">
            ${actions.length ? actions.map((action, index) => `
              <button class="action ${index === this._selectedIndex ? 'active' : ''}" type="button" data-index="${index}">
                <span class="content">${action.icon ? `<span class="icon">${action.icon}</span>` : ''}<span class="copy"><div class="title">${String(action.title || action.id || '').replace(/</g, '&lt;')}</div><div class="section">${String(action.section || '').replace(/</g, '&lt;')}</div></span></span>
                ${action.children?.length ? '<span class="chev">›</span>' : ''}
              </button>`).join('') : '<div class="empty">Nenhum comando encontrado</div>'}
          </div>
        </div>
      </div>`;

    const input = this.shadowRoot.querySelector('input');
    input?.addEventListener('input', event => {
      this._query = event.target.value;
      this._selectedIndex = 0;
      this.render();
      queueMicrotask(() => {
        const next = this.shadowRoot?.querySelector('input');
        next?.focus();
        next?.setSelectionRange(this._query.length, this._query.length);
      });
    });
    input?.addEventListener('keydown', event => {
      const current = this.visibleActions;
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        this._selectedIndex = Math.min(this._selectedIndex + 1, Math.max(0, current.length - 1));
        this.render();
        queueMicrotask(() => this.shadowRoot?.querySelector('input')?.focus());
      } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        this._selectedIndex = Math.max(0, this._selectedIndex - 1);
        this.render();
        queueMicrotask(() => this.shadowRoot?.querySelector('input')?.focus());
      } else if (event.key === 'Enter') {
        event.preventDefault();
        this.activate(current[this._selectedIndex]);
      }
    });
    this.shadowRoot.querySelector('.overlay')?.addEventListener('mousedown', event => {
      if (event.target.classList.contains('overlay')) this.close();
    });
    this.shadowRoot.querySelector('.back')?.addEventListener('click', () => {
      this._parent = null;
      this._query = '';
      this._selectedIndex = 0;
      this.render();
    });
    this.shadowRoot.querySelectorAll('button.action').forEach(button => {
      button.addEventListener('click', () => this.activate(this.visibleActions[Number(button.dataset.index)]));
    });
  }
}

if (!customElements.get('hub-command-palette')) {
  customElements.define('hub-command-palette', HubCommandPalette);
}

export default HubCommandPalette;
