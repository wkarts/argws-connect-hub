<script>
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';

export default {
  components: { Thumbnail },
  props: {
    src: {
      type: String,
      default: '',
    },
    previewSrc: {
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
      isPreviewLoading: false,
      previewFailed: false,
    };
  },
  computed: {
    largeImageSrc() {
      return this.previewSrc || this.src;
    },
  },
  methods: {
    openPreview() {
      if (!this.largeImageSrc) return;
      this.previewFailed = false;
      this.isPreviewLoading = true;
      this.isOpen = true;
      this.$nextTick(() => this.$refs.previewOverlay?.focus());
    },
    closePreview() {
      this.isOpen = false;
      this.isPreviewLoading = false;
      this.previewFailed = false;
    },
    onPreviewLoad() {
      this.isPreviewLoading = false;
    },
    onPreviewError() {
      this.isPreviewLoading = false;
      this.previewFailed = true;
    },
  },
};
</script>

<template>
  <div class="contact-avatar-preview">
    <button
      type="button"
      class="contact-avatar-preview__trigger"
      :class="{ 'is-clickable': !!largeImageSrc }"
      :disabled="!largeImageSrc"
      :aria-label="largeImageSrc ? 'Ampliar foto do contato' : 'Contato sem foto'"
      @click="openPreview"
    >
      <Thumbnail
        :src="src"
        :size="size"
        :username="username"
        :status="status"
      />
    </button>

    <transition name="avatar-preview-fade">
      <div
        v-if="isOpen"
        ref="previewOverlay"
        class="contact-avatar-preview__overlay"
        role="dialog"
        aria-modal="true"
        aria-label="Foto ampliada do contato"
        tabindex="-1"
        @click.self="closePreview"
        @keydown.esc="closePreview"
      >
        <div class="contact-avatar-preview__dialog">
          <header class="contact-avatar-preview__header">
            <div class="contact-avatar-preview__identity">
              <span>Foto do perfil</span>
              <strong>{{ username || 'Contato do WhatsApp' }}</strong>
            </div>
            <button
              type="button"
              class="contact-avatar-preview__close"
              aria-label="Fechar foto ampliada"
              @click="closePreview"
            >
              <fluent-icon icon="dismiss" size="20" />
            </button>
          </header>

          <div class="contact-avatar-preview__stage">
            <div
              v-if="isPreviewLoading"
              class="contact-avatar-preview__loading"
              aria-live="polite"
            >
              <span class="contact-avatar-preview__spinner" />
              <span>Carregando imagem em alta qualidade…</span>
            </div>

            <div
              v-if="previewFailed"
              class="contact-avatar-preview__error"
              role="status"
            >
              <fluent-icon icon="image" size="30" />
              <strong>Não foi possível carregar a imagem ampliada.</strong>
              <span>A miniatura do contato continua disponível.</span>
            </div>

            <img
              v-show="!previewFailed"
              :src="largeImageSrc"
              :alt="username ? `Foto de ${username}` : 'Foto do contato'"
              class="contact-avatar-preview__image"
              draggable="false"
              @load="onPreviewLoad"
              @error="onPreviewError"
            />
          </div>

          <footer class="contact-avatar-preview__footer">
            <span>Imagem de perfil sincronizada com o contato.</span>
            <a
              v-if="!previewFailed"
              :href="largeImageSrc"
              target="_blank"
              rel="noopener noreferrer"
            >
              Abrir imagem
              <fluent-icon icon="open" size="14" />
            </a>
          </footer>
        </div>
      </div>
    </transition>
  </div>
</template>

<style scoped>
.contact-avatar-preview {
  position: relative;
  display: inline-flex;
}

.contact-avatar-preview__trigger {
  position: relative;
  padding: 0;
  margin: 0;
  border: 0;
  border-radius: 9999px;
  background: transparent;
  cursor: default;
}

.contact-avatar-preview__trigger.is-clickable {
  cursor: pointer;
}

.contact-avatar-preview__trigger:focus-visible {
  outline: 3px solid rgba(59, 130, 246, 0.55);
  outline-offset: 3px;
}

.contact-avatar-preview__overlay {
  position: fixed;
  inset: 0;
  z-index: 10040;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: clamp(16px, 4vw, 48px);
  background: rgba(2, 6, 23, 0.78);
  backdrop-filter: blur(14px) saturate(115%);
  -webkit-backdrop-filter: blur(14px) saturate(115%);
}

.contact-avatar-preview__overlay:focus {
  outline: none;
}

.contact-avatar-preview__dialog {
  width: min(92vw, 880px);
  max-height: 92vh;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 22px;
  background: rgba(15, 23, 42, 0.96);
  color: white;
  box-shadow:
    0 30px 90px rgba(0, 0, 0, 0.5),
    0 8px 26px rgba(0, 0, 0, 0.22);
}

.contact-avatar-preview__header,
.contact-avatar-preview__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 14px 18px;
  background: rgba(15, 23, 42, 0.92);
}

.contact-avatar-preview__header {
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.contact-avatar-preview__footer {
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  color: #94a3b8;
  font-size: 12px;
}

.contact-avatar-preview__footer a {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: #dbeafe;
  font-weight: 600;
}

.contact-avatar-preview__identity {
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.contact-avatar-preview__identity span {
  color: #94a3b8;
  font-size: 11px;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.contact-avatar-preview__identity strong {
  max-width: min(65vw, 680px);
  overflow: hidden;
  color: #f8fafc;
  font-size: 15px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.contact-avatar-preview__close {
  width: 40px;
  height: 40px;
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 9999px;
  background: rgba(255, 255, 255, 0.08);
  color: white;
  cursor: pointer;
  transition:
    background-color 0.15s ease,
    transform 0.15s ease;
}

.contact-avatar-preview__close:hover {
  background: rgba(255, 255, 255, 0.16);
  transform: scale(1.03);
}

.contact-avatar-preview__stage {
  position: relative;
  min-height: min(62vh, 620px);
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  padding: clamp(14px, 3vw, 28px);
  background:
    radial-gradient(circle at 50% 25%, rgba(71, 85, 105, 0.34), transparent 48%),
    #020617;
}

.contact-avatar-preview__image {
  display: block;
  max-width: 100%;
  max-height: min(72vh, 720px);
  object-fit: contain;
  border-radius: 14px;
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.38);
  image-rendering: auto;
}

.contact-avatar-preview__loading,
.contact-avatar-preview__error {
  position: absolute;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  color: #cbd5e1;
  font-size: 13px;
}

.contact-avatar-preview__error {
  max-width: 360px;
  flex-direction: column;
  text-align: center;
}

.contact-avatar-preview__error strong {
  color: #f8fafc;
}

.contact-avatar-preview__error span {
  color: #94a3b8;
}

.contact-avatar-preview__spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgba(255, 255, 255, 0.22);
  border-top-color: white;
  border-radius: 9999px;
  animation: avatar-preview-spin 0.8s linear infinite;
}

.avatar-preview-fade-enter-active,
.avatar-preview-fade-leave-active {
  transition: opacity 0.16s ease;
}

.avatar-preview-fade-enter,
.avatar-preview-fade-leave-to {
  opacity: 0;
}

@keyframes avatar-preview-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (max-width: 640px) {
  .contact-avatar-preview__overlay {
    align-items: flex-end;
    padding: 10px;
  }

  .contact-avatar-preview__dialog {
    width: 100%;
    max-height: 94vh;
    border-radius: 20px;
  }

  .contact-avatar-preview__stage {
    min-height: 56vh;
  }

  .contact-avatar-preview__footer > span {
    display: none;
  }
}
</style>
