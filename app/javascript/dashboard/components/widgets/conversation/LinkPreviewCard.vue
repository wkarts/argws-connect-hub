<script>
export default {
  props: {
    preview: {
      type: Object,
      default: null,
    },
    loading: {
      type: Boolean,
      default: false,
    },
    dismissible: {
      type: Boolean,
      default: false,
    },
    compact: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      imageFailed: false,
    };
  },
  computed: {
    hasPreview() {
      return !!this.preview?.url;
    },
    hostLabel() {
      return this.preview?.site_name || this.preview?.host || '';
    },
  },
  watch: {
    preview() {
      this.imageFailed = false;
    },
  },
};
</script>

<template>
  <div
    v-if="loading || hasPreview"
    class="link-preview-card"
    :class="{ 'link-preview-card--compact': compact }"
  >
    <div v-if="loading" class="link-preview-card__loading">
      <span class="link-preview-card__loading-image" />
      <span class="link-preview-card__loading-copy">
        <span />
        <span />
      </span>
    </div>

    <a
      v-else
      :href="preview.url"
      target="_blank"
      rel="noopener noreferrer nofollow"
      class="link-preview-card__content"
    >
      <img
        v-if="preview.image_url && !imageFailed"
        :src="preview.image_url"
        :alt="preview.title || hostLabel"
        class="link-preview-card__image"
        loading="lazy"
        referrerpolicy="no-referrer"
        @error="imageFailed = true"
      />
      <span class="link-preview-card__copy">
        <small v-if="hostLabel">{{ hostLabel }}</small>
        <strong v-if="preview.title">{{ preview.title }}</strong>
        <span v-if="preview.description">{{ preview.description }}</span>
        <em>{{ preview.url }}</em>
      </span>
    </a>

    <button
      v-if="dismissible && !loading"
      type="button"
      class="link-preview-card__dismiss"
      aria-label="Remover pré-visualização"
      title="Remover pré-visualização"
      @click.stop="$emit('dismiss')"
    >
      ×
    </button>
  </div>
</template>

<style lang="scss" scoped>
.link-preview-card {
  @apply relative flex overflow-hidden w-full max-w-[34rem] rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm;
}

.link-preview-card__content {
  @apply flex w-full min-w-0 no-underline text-left;
}

.link-preview-card__image {
  @apply w-28 h-24 shrink-0 object-cover bg-slate-100 dark:bg-slate-700;
}

.link-preview-card__copy {
  @apply flex flex-col justify-center min-w-0 gap-0.5 px-3 py-2;

  small {
    @apply truncate text-[11px] font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400;
  }

  strong {
    @apply line-clamp-2 text-sm font-semibold leading-5 text-slate-800 dark:text-slate-100;
  }

  span {
    @apply line-clamp-2 text-xs leading-4 text-slate-600 dark:text-slate-300;
  }

  em {
    @apply truncate not-italic text-[11px] text-slate-400 dark:text-slate-500;
  }
}

.link-preview-card__dismiss {
  @apply absolute top-1.5 right-1.5 flex items-center justify-center w-6 h-6 rounded-full border-0 bg-white/90 dark:bg-slate-900/90 text-slate-600 dark:text-slate-200 shadow cursor-pointer;
}

.link-preview-card__loading {
  @apply flex w-full animate-pulse;
}

.link-preview-card__loading-image {
  @apply w-28 h-24 shrink-0 bg-slate-200 dark:bg-slate-700;
}

.link-preview-card__loading-copy {
  @apply flex flex-1 flex-col justify-center gap-2 px-3;

  span {
    @apply block h-3 rounded bg-slate-200 dark:bg-slate-700;
  }

  span:first-child {
    @apply w-3/4;
  }

  span:last-child {
    @apply w-1/2;
  }
}

.link-preview-card--compact {
  @apply mt-1 max-w-[28rem];

  .link-preview-card__image {
    @apply w-24 h-20;
  }

  .link-preview-card__copy {
    @apply py-1.5;
  }
}
</style>
