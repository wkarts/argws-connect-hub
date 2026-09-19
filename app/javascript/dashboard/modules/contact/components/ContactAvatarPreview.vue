<script>
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

export default {
  components: { Thumbnail },
  props: {
    src: {
      type: String,
      default: '',
    },
    username: {
      type: String,
      default: '',
    },
    status: {
      type: String,
      default: '',
    },
    size: {
      type: String,
      default: '56px',
    },
  },
  data() {
    return {
      isOpen: false,
    };
  },
  methods: {
    openPreview() {
      if (this.src) this.isOpen = true;
    },
    closePreview() {
      this.isOpen = false;
    },
  },
};
</script>

<template>
  <div class="contact-avatar-preview">
    <button
      type="button"
      class="contact-avatar-preview__trigger"
      :class="{ 'is-clickable': !!src }"
      :disabled="!src"
      :aria-label="src ? 'Ampliar foto do contato' : 'Contato sem foto'"
      @click="openPreview"
    >
      <Thumbnail
        :src="src"
        :size="size"
        :username="username"
        :status="status"
      />
    </button>

    <div
      v-if="isOpen"
      class="contact-avatar-preview__overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Foto ampliada do contato"
      tabindex="-1"
      @click.self="closePreview"
      @keydown.esc="closePreview"
    >
      <div class="contact-avatar-preview__dialog">
        <button
          type="button"
          class="contact-avatar-preview__close"
          aria-label="Fechar foto ampliada"
          @click="closePreview"
        >
          ×
        </button>
        <img
          :src="src"
          :alt="username ? `Foto de ${username}` : 'Foto do contato'"
          class="contact-avatar-preview__image"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.contact-avatar-preview__trigger {
  padding: 0;
  margin: 0;
  border: 0;
  background: transparent;
  cursor: default;
}

.contact-avatar-preview__trigger.is-clickable {
  cursor: zoom-in;
}

.contact-avatar-preview__trigger:focus-visible {
  outline: 3px solid #93c5fd;
  outline-offset: 3px;
  border-radius: 9999px;
}

.contact-avatar-preview__overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: rgba(15, 23, 42, 0.78);
}

.contact-avatar-preview__dialog {
  position: relative;
  width: min(92vw, 720px);
  max-height: 90vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

.contact-avatar-preview__image {
  max-width: 100%;
  max-height: 86vh;
  object-fit: contain;
  border-radius: 16px;
  background: white;
  box-shadow: 0 24px 70px rgba(0, 0, 0, 0.36);
}

.contact-avatar-preview__close {
  position: absolute;
  top: -14px;
  right: -14px;
  z-index: 2;
  width: 38px;
  height: 38px;
  border: 0;
  border-radius: 9999px;
  background: white;
  color: #0f172a;
  font-size: 28px;
  line-height: 1;
  cursor: pointer;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.24);
}
</style>
