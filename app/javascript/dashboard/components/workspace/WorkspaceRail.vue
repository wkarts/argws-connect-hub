<script>
export default {
  props: { label: { type: String, required: true }, activeId: { type: Number, default: null } },
  data() { return { canUp: false, canDown: false }; },
  watch: { activeId() { this.$nextTick(this.revealActive); } },
  mounted() {
    if (typeof ResizeObserver !== 'undefined') {
      this.observer = new ResizeObserver(this.measure);
      this.observer.observe(this.$refs.viewport);
      this.observer.observe(this.$refs.items);
    }
    window.addEventListener('resize', this.measure);
    this.$nextTick(this.measure);
  },
  updated() { this.measure(); },
  beforeDestroy() { this.observer?.disconnect(); window.removeEventListener('resize', this.measure); },
  methods: {
    measure() {
      const el = this.$refs.viewport;
      if (!el) return;
      this.canUp = el.scrollTop > 1;
      this.canDown = el.scrollTop + el.clientHeight < el.scrollHeight - 1;
    },
    scroll(direction) {
      const el = this.$refs.viewport;
      el.scrollTop += direction * Math.max(56, el.clientHeight * .7);
      this.measure();
    },
    reveal(target) {
      const el = this.$refs.viewport;
      if (!target || !el) return;
      const item = target.getBoundingClientRect();
      const view = el.getBoundingClientRect();
      if (item.top < view.top) el.scrollTop -= view.top - item.top;
      else if (item.bottom > view.bottom) el.scrollTop += item.bottom - view.bottom;
      this.measure();
    },
    revealActive() { this.reveal(this.$refs.items.querySelector('[aria-pressed="true"]')); },
    onKey(event) {
      const controls = [...this.$refs.items.querySelectorAll('button:not(:disabled), a[href], [tabindex="0"]')];
      const current = controls.indexOf(document.activeElement);
      let index;
      if (event.key === 'ArrowDown') index = Math.min(controls.length - 1, current + 1);
      else if (event.key === 'ArrowUp') index = Math.max(0, current - 1);
      else if (event.key === 'Home') index = 0;
      else if (event.key === 'End') index = controls.length - 1;
      else if (event.key === 'PageDown' || event.key === 'PageUp') {
        event.preventDefault(); this.scroll(event.key === 'PageDown' ? 1 : -1); return;
      } else return;
      event.preventDefault();
      controls[index]?.focus({ preventScroll: true });
      this.reveal(controls[index]);
    },
  },
};
</script>

<template>
  <div class="workspace-rail" :aria-label="label">
    <button v-show="canUp || canDown" type="button" class="workspace-rail__arrow" :disabled="!canUp" :aria-label="$t('WORKSPACE_APPS.SCROLL_UP')" @click="scroll(-1)"><fluent-icon icon="chevron-up" size="14" /></button>
    <div ref="viewport" class="workspace-rail__viewport" @scroll.passive="measure" @keydown="onKey" @focusin="reveal($event.target)">
      <div ref="items" class="workspace-rail__items"><slot /></div>
    </div>
    <button v-show="canUp || canDown" type="button" class="workspace-rail__arrow" :disabled="!canDown" :aria-label="$t('WORKSPACE_APPS.SCROLL_DOWN')" @click="scroll(1)"><fluent-icon icon="chevron-down" size="14" /></button>
  </div>
</template>

<style scoped>
.workspace-rail { display: flex; flex-direction: column; width: 100%; min-height: 0; flex: 1; }
.workspace-rail__viewport { min-height: 0; flex: 1; overflow-x: hidden; overflow-y: auto; scrollbar-width: none; -ms-overflow-style: none; overscroll-behavior: contain; touch-action: pan-y; }
.workspace-rail__viewport::-webkit-scrollbar { display: none; width: 0; height: 0; }
.workspace-rail__items { display: flex; flex-direction: column; align-items: center; }
.workspace-rail__arrow { flex-shrink: 0; height: 18px; padding: 0; border: 0; background: transparent; color: #64748b; display: flex; align-items: center; justify-content: center; cursor: pointer; }
.workspace-rail__arrow:disabled { opacity: .25; cursor: default; }
.workspace-rail__arrow:focus-visible { outline: 2px solid #3b82f6; outline-offset: -2px; }
</style>
